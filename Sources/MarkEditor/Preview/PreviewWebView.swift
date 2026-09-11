import SwiftUI
import WebKit

/// Rendered-markdown preview: a WKWebView loaded once with a styled template,
/// then updated in place via JS (no flicker, scroll preserved). Markdown is
/// parsed off the main thread with a short debounce while typing.
struct PreviewWebView: NSViewRepresentable {
    let markdown: String
    let baseURL: URL?
    @Binding var scrollSync: ScrollSync
    let contentWidthRem: Double
    let actions: PreviewActions

    @AppStorage(SettingsKeys.previewFontName) private var fontName = SettingsDefaults.previewFontName
    @AppStorage(SettingsKeys.previewFontSize) private var fontSize = SettingsDefaults.previewFontSize
    @AppStorage(SettingsKeys.previewLineHeight) private var lineHeight = SettingsDefaults.previewLineHeight
    @AppStorage(SettingsKeys.strictLineBreaks) private var strictLineBreaks = SettingsDefaults.strictLineBreaks

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
        actions.coordinator = coordinator
        coordinator.schemeHandler.baseDirectory = baseURL
        coordinator.setStyle(fontFamily: FontOption.cssFamily(for: fontName), size: fontSize, lineHeight: lineHeight)
        coordinator.setContentWidth(contentWidthRem)
        coordinator.setMarkdown(markdown, strictLineBreaks: strictLineBreaks)
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
        private var lastScroll = ScrollSync()
        private var isRendering = false
        private var needsRender = false
        private var pendingContent: RenderedContent?

        // MARK: - Content

        private var lastStrictLineBreaks = SettingsDefaults.strictLineBreaks

        func setMarkdown(_ markdown: String, strictLineBreaks: Bool) {
            // Toggling the setting must re-render even when the text is unchanged.
            guard markdown != lastMarkdown || strictLineBreaks != lastStrictLineBreaks else { return }
            lastMarkdown = markdown
            lastStrictLineBreaks = strictLineBreaks
            needsRender = true
            renderNextIfIdle()
        }

        /// Renders immediately — no debounce — but never stacks work: while a
        /// render/apply is in flight, newer text only marks it dirty, and the
        /// latest text renders as soon as the current one finishes. Under a
        /// typing burst this self-paces to whatever the machine sustains.
        private func renderNextIfIdle() {
            guard needsRender, !isRendering, let markdown = lastMarkdown else { return }
            let strictLineBreaks = lastStrictLineBreaks
            needsRender = false
            isRendering = true
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                let content = HTMLRenderer.renderWithLines(markdown, strictLineBreaks: strictLineBreaks)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.pushContent(content) {
                        self.isRendering = false
                        self.renderNextIfIdle()
                    }
                }
            }
        }

        typealias RenderedContent = (html: String, blockLines: [Int], lineCount: Int)

        private func pushContent(_ content: RenderedContent, completion: @escaping () -> Void) {
            guard let webView, isReady else {
                pendingContent = content
                completion()
                return
            }
            webView.callAsyncJavaScript(
                "setContent(html, lines, lineCount)",
                arguments: [
                    "html": content.html,
                    "lines": content.blockLines,
                    "lineCount": content.lineCount,
                ],
                in: nil,
                in: .page
            ) { [weak self] _ in
                self?.alignScrollAfterContentChange()
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

        // MARK: - Content width (preview-only mode levels)

        private var lastContentWidthRem: Double?

        func setContentWidth(_ rem: Double) {
            guard rem != lastContentWidthRem else { return }
            lastContentWidthRem = rem
            guard let webView, isReady else { return }
            webView.callAsyncJavaScript(
                "document.documentElement.style.setProperty('--article-max', rem + 'rem')",
                arguments: ["rem": rem],
                in: nil,
                in: .page
            ) { _ in }
        }

        // MARK: - Find in preview (⌘3 mode)

        func find(
            _ query: String,
            forward: Bool,
            restart: Bool,
            completion: @escaping (Int, Int) -> Void
        ) {
            guard let webView, isReady else {
                completion(0, 0)
                return
            }
            webView.callAsyncJavaScript(
                "return findRun(query, forward, restart)",
                arguments: ["query": query, "forward": forward, "restart": restart],
                in: nil,
                in: .page
            ) { result in
                if case .success(let value) = result,
                   let counts = value as? [Any], counts.count == 2,
                   let current = (counts[0] as? NSNumber)?.intValue,
                   let total = (counts[1] as? NSNumber)?.intValue {
                    completion(current, total)
                } else {
                    completion(0, 0)
                }
            }
        }

        func clearFind() {
            guard let webView, isReady else { return }
            webView.callAsyncJavaScript("findClear()", arguments: [:], in: nil, in: .page) { _ in }
        }

        // MARK: - Scroll sync (bidirectional)

        private var pendingScroll: ScrollSync?

        func syncScroll(_ sync: ScrollSync) {
            // Template (or content) not loaded yet, e.g. this pane was just
            // (re)created by a view-mode switch. Remember the position and
            // apply it once the content lands, whichever pane scrolled last.
            guard isReady else {
                pendingScroll = sync
                return
            }
            // Track preview-sourced positions so a later editor push compares
            // against where the preview actually is, then only follow the editor.
            if sync.source == .preview {
                lastScroll = sync
                return
            }
            guard sync.differs(from: lastScroll) else { return }
            lastScroll = sync
            applyScroll(sync)
        }

        /// Runs after each content push: applies a position that arrived
        /// before the page was ready, or re-aligns to the last one, since
        /// edits shift where each source line sits in the preview.
        private func alignScrollAfterContentChange() {
            if let pending = pendingScroll {
                pendingScroll = nil
                lastScroll = pending
            }
            applyScroll(lastScroll)
        }

        private func applyScroll(_ sync: ScrollSync) {
            guard let webView, isReady else { return }
            webView.callAsyncJavaScript(
                "setScrollPosition(line, hasLine, endLine, hasEndLine, fraction, toEndDistance)",
                arguments: [
                    "line": sync.line ?? 0,
                    "hasLine": sync.line != nil,
                    "endLine": sync.endLine ?? 0,
                    "hasEndLine": sync.endLine != nil,
                    "fraction": Double(sync.fraction),
                    "toEndDistance": sync.toEndDistance,
                ],
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
                  let values = message.body as? [Any], values.count == 4,
                  let fraction = (values[2] as? NSNumber)?.doubleValue,
                  let toEndDistance = (values[3] as? NSNumber)?.doubleValue else { return }
            let sync = ScrollSync(
                line: (values[0] as? NSNumber)?.doubleValue,
                fraction: CGFloat(min(max(fraction, 0), 1)),
                endLine: (values[1] as? NSNumber)?.doubleValue,
                toEndDistance: max(toEndDistance, 0),
                source: .preview
            )
            lastScroll = sync
            parent?.scrollSync = sync
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            if let style = lastStyle {
                lastStyle = nil
                setStyle(fontFamily: style.family, size: style.size, lineHeight: style.lineHeight)
            }
            if let widthRem = lastContentWidthRem {
                lastContentWidthRem = nil
                setContentWidth(widthRem)
            }
            if let content = pendingContent {
                pendingContent = nil
                pushContent(content) { [weak self] in
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
