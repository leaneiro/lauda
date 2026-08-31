import WebKit
import UniformTypeIdentifiers

/// Serves relative image references (e.g. `![](./figura.png)`) to the preview
/// from the document's folder, via a custom scheme. Scoped on purpose: only
/// image files, only inside the document's directory — page JS gets no general
/// file-system access (a malicious .md must not be able to read local files).
final class DocumentSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "markeditor-doc"
    static let baseURL = URL(string: "\(scheme):///")!

    /// The open document's folder; updated when the file is (re)saved elsewhere.
    var baseDirectory: URL?

    private static let allowedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "tiff", "tif", "heic", "avif", "ico",
    ]

    static func resolveTarget(for url: URL, baseDirectory: URL) -> URL? {
        let relativePath = url.path.removingPercentEncoding ?? url.path
        guard !relativePath.isEmpty else { return nil }

        let base = baseDirectory.standardizedFileURL
        let target = base.appendingPathComponent(relativePath).standardizedFileURL
        guard target.path == base.path || target.path.hasPrefix(base.path + "/") else {
            return nil // path traversal (e.g. ../../…)
        }
        guard allowedExtensions.contains(target.pathExtension.lowercased()) else {
            return nil
        }
        return target
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let baseDirectory,
              let target = Self.resolveTarget(for: url, baseDirectory: baseDirectory),
              let data = try? Data(contentsOf: target)
        else {
            urlSchemeTask.didFailWithError(CocoaError(.fileReadNoSuchFile))
            return
        }

        let mimeType = UTType(filenameExtension: target.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        let response = URLResponse(
            url: url,
            mimeType: mimeType,
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
