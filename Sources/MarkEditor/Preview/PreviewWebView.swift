import SwiftUI
import WebKit

/// Rendered-markdown preview: a WKWebView loaded once with a styled template,
/// then updated in place via JS (no flicker, scroll preserved). Markdown is
/// parsed off the main thread with a short debounce while typing.
struct PreviewWebView: NSViewRepresentable {
    let markdown: String
    let baseURL: URL?
    let scrollFraction: CGFloat

    @AppStorage(SettingsKeys.previewFontName) private var fontName = SettingsDefaults.previewFontName
    @AppStorage(SettingsKeys.previewFontSize) private var fontSize = SettingsDefaults.previewFontSize
    @AppStorage(SettingsKeys.previewLineHeight) private var lineHeight = SettingsDefaults.previewLineHeight

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(context.coordinator.schemeHandler, forURLScheme: DocumentSchemeHandler.scheme)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = .white
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
        coordinator.schemeHandler.baseDirectory = baseURL
        coordinator.setStyle(fontFamily: FontOption.cssFamily(for: fontName), size: fontSize, lineHeight: lineHeight)
        coordinator.setMarkdown(markdown)
        coordinator.setScrollFraction(scrollFraction)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        let schemeHandler = DocumentSchemeHandler()

        private var isReady = false
        private var lastMarkdown: String?
        private var lastStyle: (family: String, size: Double, lineHeight: Double)?
        private var lastScrollFraction: CGFloat = 0
        private var pendingRender: DispatchWorkItem?
        private var renderGeneration = 0

        // MARK: - Content

        func setMarkdown(_ markdown: String) {
            guard markdown != lastMarkdown else { return }
            let isFirstRender = lastMarkdown == nil
            lastMarkdown = markdown

            pendingRender?.cancel()
            renderGeneration += 1
            let generation = renderGeneration

            let work = DispatchWorkItem { [weak self] in
                let html = HTMLRenderer.render(markdown)
                DispatchQueue.main.async {
                    guard let self, self.renderGeneration == generation else { return }
                    self.pushContent(html)
                }
            }
            pendingRender = work
            // No debounce on first render (opening a file); short debounce while typing.
            let delay: TimeInterval = isFirstRender ? 0 : 0.15
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: work)
        }

        private var pendingHTML: String?

        private func pushContent(_ html: String) {
            guard let webView, isReady else {
                pendingHTML = html
                return
            }
            webView.callAsyncJavaScript(
                "setContent(html)",
                arguments: ["html": html],
                in: nil,
                in: .page
            ) { _ in }
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

        // MARK: - Scroll sync (editor → preview)

        func setScrollFraction(_ fraction: CGFloat) {
            guard abs(fraction - lastScrollFraction) > 0.0005 else { return }
            lastScrollFraction = fraction
            guard let webView, isReady else { return }
            webView.callAsyncJavaScript(
                "setScrollFraction(fraction)",
                arguments: ["fraction": Double(fraction)],
                in: nil,
                in: .page
            ) { _ in }
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            if let style = lastStyle {
                lastStyle = nil
                setStyle(fontFamily: style.family, size: style.size, lineHeight: style.lineHeight)
            }
            if let html = pendingHTML {
                pendingHTML = nil
                pushContent(html)
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
