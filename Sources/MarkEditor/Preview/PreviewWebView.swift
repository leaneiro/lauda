import SwiftUI
import WebKit

/// Rendered-markdown preview: a WKWebView loaded once with a styled template,
/// then updated in place via JS (no flicker, scroll preserved). Markdown is
/// parsed off the main thread with a short debounce while typing.
struct PreviewWebView: NSViewRepresentable {
    let markdown: String
    let baseURL: URL?
    @Binding var scrollSync: ScrollSync
    let wide: Bool

    @AppStorage(SettingsKeys.previewFontName) private var fontName = SettingsDefaults.previewFontName
    @AppStorage(SettingsKeys.previewFontSize) private var fontSize = SettingsDefaults.previewFontSize
    @AppStorage(SettingsKeys.previewLineHeight) private var lineHeight = SettingsDefaults.previewLineHeight

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(context.coordinator.schemeHandler, forURLScheme: DocumentSchemeHandler.scheme)
        configuration.userContentController.add(context.coordinator, name: "previewScrolled")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = .textBackgroundColor
        webView.allowsMagnification = true

        context.coordinator.webView = webView
        context.coordinator.schemeHandler.baseDirectory = baseURL
        // Custom-scheme base: relative images resolve through the scheme
        // handler (scoped to the document's folder) instead of file access.
        webView.loadHTMLString(PreviewTemplate.html, baseURL: DocumentSchemeHandler.baseURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.schemeHandler.baseDirectory = baseURL
        coordinator.setStyle(fontFamily: FontOption.cssFamily(for: fontName), size: fontSize, lineHeight: lineHeight)
        coordinator.setWide(wide)
        coordinator.setMarkdown(markdown)
        coordinator.syncScroll(scrollSync)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "previewScrolled")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: PreviewWebView?
        weak var webView: WKWebView?
        let schemeHandler = DocumentSchemeHandler()

        private var isReady = false
        private var lastMarkdown: String?
        private var lastStyle: (family: String, size: Double, lineHeight: Double)?
        private var lastScrollFraction: CGFloat = 0
        private var isRendering = false
        private var needsRender = false
        private var pendingHTML: String?

        // MARK: - Content

        func setMarkdown(_ markdown: String) {
            guard markdown != lastMarkdown else { return }
            lastMarkdown = markdown
            needsRender = true
            renderNextIfIdle()
        }

        /// Renders immediately — no debounce — but never stacks work: while a
        /// render/apply is in flight, newer text only marks it dirty, and the
        /// latest text renders as soon as the current one finishes. Under a
        /// typing burst this self-paces to whatever the machine sustains.
        private func renderNextIfIdle() {
            guard needsRender, !isRendering, let markdown = lastMarkdown else { return }
            needsRender = false
            isRendering = true
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                let html = HTMLRenderer.render(markdown)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.pushContent(html) {
                        self.isRendering = false
                        self.renderNextIfIdle()
                    }
                }
            }
        }

        private func pushContent(_ html: String, completion: @escaping () -> Void) {
            guard let webView, isReady else {
                pendingHTML = html
                completion()
                return
            }
            webView.callAsyncJavaScript(
                "setContent(html)",
                arguments: ["html": html],
                in: nil,
                in: .page
            ) { [weak self] _ in
                self?.flushPendingScroll()
                completion()
            }
        }

        // MARK: - Style

        func setStyle(fontFamily: String, size: Double, lineHeight: Double) {
            if let lastStyle, lastStyle == (fontFamily, size, lineHeight) { return }
            lastStyle = (fontFamily, size, lineHeight)
            guard let webView, isReady else { return }
            webView.callAsyncJavaScript(
                "setStyle(family, size, lineHeight)",
                arguments: ["family": fontFamily, "size": size, "lineHeight": lineHeight],
                in: nil,
                in: .page
            ) { _ in }
        }

        // MARK: - Wide layout (preview-only mode)

        private var lastWide: Bool?

        func setWide(_ wide: Bool) {
            guard wide != lastWide else { return }
            lastWide = wide
            guard let webView, isReady else { return }
            webView.callAsyncJavaScript(
                "document.body.classList.toggle('wide', wide)",
                arguments: ["wide": wide],
                in: nil,
                in: .page
            ) { _ in }
        }

        // MARK: - Scroll sync (bidirectional)

        private var pendingScrollFraction: CGFloat?

        func syncScroll(_ sync: ScrollSync) {
            // Track preview-sourced positions so a later editor push compares
            // against where the preview actually is, then only follow the editor.
            if sync.source == .preview {
                lastScrollFraction = sync.fraction
                return
            }
            guard let webView, isReady else {
                // Template (or content) not loaded yet — e.g. this pane was just
                // (re)created by a view-mode switch. Remember the position and
                // apply it once the content lands.
                pendingScrollFraction = sync.fraction
                return
            }
            guard abs(sync.fraction - lastScrollFraction) > 0.0005 else { return }
            lastScrollFraction = sync.fraction
            webView.callAsyncJavaScript(
                "setScrollFraction(fraction)",
                arguments: ["fraction": Double(sync.fraction)],
                in: nil,
                in: .page
            ) { _ in }
        }

        /// Applies a scroll that arrived before the page/content was ready —
        /// runs after a content push completes, so the page has its height.
        private func flushPendingScroll() {
            guard let fraction = pendingScrollFraction else { return }
            pendingScrollFraction = nil
            guard let webView, isReady else { return }
            lastScrollFraction = fraction
            webView.callAsyncJavaScript(
                "setScrollFraction(fraction)",
                arguments: ["fraction": Double(fraction)],
                in: nil,
                in: .page
            ) { _ in }
        }

        // MARK: - WKScriptMessageHandler (preview → editor)

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "previewScrolled",
                  let fraction = message.body as? Double else { return }
            let clamped = CGFloat(min(max(fraction, 0), 1))
            lastScrollFraction = clamped
            parent?.scrollSync = ScrollSync(fraction: clamped, source: .preview)
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            if let style = lastStyle {
                lastStyle = nil
                setStyle(fontFamily: style.family, size: style.size, lineHeight: style.lineHeight)
            }
            if let wide = lastWide {
                lastWide = nil
                setWide(wide)
            }
            if let html = pendingHTML {
                pendingHTML = nil
                pushContent(html) { [weak self] in
                    self?.renderNextIfIdle()
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // Subframes (iframe embeds) load inside the preview.
            guard navigationAction.targetFrame?.isMainFrame ?? true else {
                decisionHandler(.allow)
                return
            }
            // Real link clicks open in the browser.
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url,
                   let scheme = url.scheme?.lowercased(),
                   ["http", "https", "mailto"].contains(scheme) {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }
            // Otherwise only the initial template load may navigate the main
            // frame (blocks JS/meta redirects from raw HTML in the document).
            decisionHandler(isReady ? .cancel : .allow)
        }
    }
}
