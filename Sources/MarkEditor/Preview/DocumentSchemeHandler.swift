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

    static func resolveTarget(for url: URL, baseDirectory: URL) -> URL? {
        let relativePath = url.path.removingPercentEncoding ?? url.path
        guard !relativePath.isEmpty else { return nil }

        // Symlinks are resolved on both sides, so a link inside the folder
        // can't serve a file from outside it.
        let base = baseDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let target = base.appendingPathComponent(relativePath).standardizedFileURL.resolvingSymlinksInPath()
        guard target.path == base.path || target.path.hasPrefix(base.path + "/") else {
            return nil // path traversal (e.g. ../../…) or a symlink pointing out
        }
        guard ImageFileTypes.isImage(target) else {
            return nil
        }
        return target
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, let baseDirectory else {
            urlSchemeTask.didFailWithError(CocoaError(.fileReadNoSuchFile))
            return
        }
        guard let target = Self.resolveTarget(for: url, baseDirectory: baseDirectory) else {
            // Refused on purpose (see resolveTarget), but it shows up as a
            // broken image, so it's worth a line when someone asks why.
            Log.preview.notice("Refused a preview image outside the document's folder or not an image file")
            urlSchemeTask.didFailWithError(CocoaError(.fileReadNoPermission))
            return
        }
        guard let data = try? Data(contentsOf: target) else {
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
