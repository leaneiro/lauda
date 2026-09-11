import AppKit
import WebKit
import UniformTypeIdentifiers

/// Exports the rendered document: standalone HTML (written directly) or a
/// paginated PDF (offscreen WKWebView + print operation with save-to-file).
final class DocumentExporter: NSObject, WKNavigationDelegate {
    /// Keeps exporters alive for the duration of their async PDF export.
    private static var active: Set<DocumentExporter> = []

    // MARK: - Standalone HTML

    static func standaloneHTML(markdown: String, title: String, style: PreviewStyle = .current()) -> String {
        PreviewTemplate.standalone(
            title: title,
            bodyHTML: HTMLRenderer.renderForPrint(markdown, strictLineBreaks: style.strictLineBreaks),
            fontFamily: FontOption.cssFamily(for: style.fontName),
            fontSize: style.fontSize,
            lineHeight: style.lineHeight
        )
    }

    static func promptAndExportHTML(markdown: String, title: String, baseDirectory: URL?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = title + ".html"
        panel.directoryURL = baseDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try standaloneHTML(markdown: markdown, title: title)
                .write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: - PDF

    static func promptAndExportPDF(markdown: String, title: String, baseDirectory: URL?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = title + ".pdf"
        panel.directoryURL = baseDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportPDF(markdown: markdown, title: title, baseDirectory: baseDirectory, to: url)
    }

    static func exportPDF(
        markdown: String,
        title: String,
        baseDirectory: URL?,
        to destination: URL,
        completion: ((Bool) -> Void)? = nil
    ) {
        let exporter = DocumentExporter(destination: destination, completion: completion)
        active.insert(exporter)
        exporter.start(
            html: standaloneHTML(markdown: markdown, title: title),
            baseDirectory: baseDirectory
        )
    }

    private let destination: URL
    private let completion: ((Bool) -> Void)?
    private var webView: WKWebView?
    private var hostWindow: NSWindow?
    private let schemeHandler = DocumentSchemeHandler()

    private init(destination: URL, completion: ((Bool) -> Void)?) {
        self.destination = destination
        self.completion = completion
    }

    private func start(html: String, baseDirectory: URL?) {
        schemeHandler.baseDirectory = baseDirectory
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: DocumentSchemeHandler.scheme)

        // Offscreen view sized roughly like an A4 page at 96dpi.
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 794, height: 1123),
            configuration: configuration
        )
        webView.navigationDelegate = self
        self.webView = webView
        webView.loadHTMLString(html, baseURL: DocumentSchemeHandler.baseURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Give images a moment to finish loading before pagination.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.runPrintOperation()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Log.export.failure("Loading the page for the PDF", error)
        finish(success: false)
    }

    private func runPrintOperation() {
        guard let webView else {
            finish(success: false)
            return
        }
        let printInfo = NSPrintInfo(dictionary: [.jobSavingURL: destination])
        printInfo.jobDisposition = .save
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false
        printInfo.topMargin = 42
        printInfo.bottomMargin = 42
        printInfo.leftMargin = 42
        printInfo.rightMargin = 42

        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        // WKWebView's print view starts zero-sized; without a real frame the
        // output comes out blank.
        operation.view?.frame = webView.bounds

        // Always run modally, for a window of our own that is never shown.
        // WKWebView works out its page rects asynchronously; a synchronous
        // run() asks for them too early, gets "unlimited pages of 1×1
        // points" back and keeps writing pages until the disk fills up.
        let host = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        host.isReleasedWhenClosed = false
        hostWindow = host
        operation.runModal(
            for: host,
            delegate: self,
            didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
            contextInfo: nil
        )
    }

    @objc private func printOperationDidRun(
        _ printOperation: NSPrintOperation,
        success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        finish(success: success)
    }

    private func finish(success: Bool) {
        if !success {
            Log.export.error("PDF export didn't finish")
        }
        completion?(success)
        webView = nil
        hostWindow = nil
        Self.active.remove(self)
    }
}
