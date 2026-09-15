import AppKit
import Testing
import WebKit
@testable import Lauda

/// The real preview page (template, stylesheet and script in its content
/// world), loaded in an offscreen web view the way the app loads it.
@MainActor
private final class PreviewPage: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private let window: NSWindow
    private let schemeHandler = DocumentSchemeHandler()
    private var finished: CheckedContinuation<Void, Never>?

    init(width: CGFloat, height: CGFloat) {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: DocumentSchemeHandler.scheme)
        configuration.userContentController.addUserScript(WKUserScript(
            source: PreviewTemplate.script,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: PreviewWebView.contentWorld
        ))
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height), configuration: configuration)
        window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: width, height: height),
            styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        window.contentView = webView
        window.orderFrontRegardless()
        webView.navigationDelegate = self
    }

    func load(markdown: String) async throws {
        await withCheckedContinuation { continuation in
            finished = continuation
            webView.loadHTMLString(PreviewTemplate.html, baseURL: DocumentSchemeHandler.baseURL)
        }
        let content = HTMLRenderer.renderWithLines(markdown)
        try await run("setContent(html, lines, lineCount)", [
            "html": content.html, "lines": content.blockLines, "lineCount": content.lineCount,
        ])
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished?.resume()
        finished = nil
    }

    /// What switching view modes does to the preview pane.
    func resize(width: CGFloat) {
        let height = webView.frame.height
        window.setContentSize(NSSize(width: width, height: height))
        webView.frame = NSRect(x: 0, y: 0, width: width, height: height)
    }

    @discardableResult
    func run(_ script: String, _ arguments: [String: Any] = [:]) async throws -> Any? {
        try await webView.callAsyncJavaScript(script, arguments: arguments, contentWorld: PreviewWebView.contentWorld)
    }

    func number(_ script: String) async throws -> Double {
        (try await run(script) as? NSNumber)?.doubleValue ?? .nan
    }

    /// The fractional source line at the top of the page.
    func topLine() async throws -> Double {
        try await number("return interpolate(lineAnchors(), window.scrollY, 1, 0)")
    }

    /// What following the editor does: the synced line goes to the top.
    func scroll(toLine line: Double) async throws {
        try await run("setScrollPosition(line, true, 0, false, 0, 0, 1)", ["line": line])
    }

    /// Changes the column width the way nothing in the app does: without
    /// putting the page back, so the text drifts away from the synced line.
    func driftWithBareWidthChange(rem: Int) async throws {
        try await run("""
            document.documentElement.classList.add('reflowing');
            document.documentElement.style.setProperty('--article-max', rem + 'rem');
            document.body.getBoundingClientRect();
            document.documentElement.classList.remove('reflowing');
            """, ["rem": rem])
    }

    /// Polls until `condition` holds or two seconds pass; returns the last top line.
    func topLine(settlingWithin tolerance: Double, of target: Double) async throws -> Double {
        var line = try await topLine()
        for _ in 0..<40 where abs(line - target) >= tolerance {
            try await Task.sleep(for: .milliseconds(50))
            line = try await topLine()
        }
        return line
    }
}

/// Switching view modes resizes the preview pane, and the column width and
/// font settings reflow the text too; the synced line must stay at the top.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct PreviewReflowTests {
    /// 160 long paragraphs, one source line each with a blank line between:
    /// paragraph 80 starts on line 158.
    private static let markdown = (1...160).map { index in
        "Paragraph \(index). " + String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 12)
    }.joined(separator: "\n\n")

    private func openPage(width: CGFloat = 1600) async throws -> PreviewPage {
        let page = PreviewPage(width: width, height: 700)
        try await page.load(markdown: Self.markdown)
        try await page.scroll(toLine: 158)
        return page
    }

    /// Guards the other tests: in this setup a reflow really moves the text.
    @Test func aBareWidthChangeLandsFarFromTheLine() async throws {
        let page = try await openPage()
        let before = try await page.topLine()
        try await page.driftWithBareWidthChange(rem: 90)
        let after = try await page.topLine()
        #expect(abs(before - 158) < 0.5, "setup: expected line 158 at the top, got \(before)")
        #expect(after - before > 20, "expected a jump like the reported one, got \(before) → \(after)")
    }

    @Test func wideningTheColumnKeepsTheSyncedLine() async throws {
        let page = try await openPage()
        try await page.run("setContentWidth(rem)", ["rem": 90])
        #expect(abs(try await page.topLine() - 158) < 0.5)
        #expect(try await page.number("return document.querySelector('#content').getBoundingClientRect().width") > 1000,
                "the column really got wider")
        try await Task.sleep(for: .milliseconds(500))
        let later = try await page.topLine()
        #expect(abs(later - 158) < 0.5, "half a second later the top line is \(later)")
    }

    @Test func changingTheFontSizeKeepsTheSyncedLine() async throws {
        let page = try await openPage()
        try await page.run("setStyle(family, size, lineHeight)", ["family": "Georgia, serif", "size": 24, "lineHeight": 1.8])
        #expect(abs(try await page.topLine() - 158) < 0.5)
    }

    /// Entering or leaving preview-only mode resizes the pane; the reported
    /// jumps came from this, not only from the column width.
    @Test(arguments: [700.0, 1200.0])
    func resizingThePaneKeepsTheSyncedLine(width: Double) async throws {
        let page = try await openPage(width: width == 700 ? 1600 : 700)
        page.resize(width: width)
        let line = try await page.topLine(settlingWithin: 0.5, of: 158)
        #expect(try await page.number("return window.innerWidth") == width, "the pane really resized")
        #expect(abs(line - 158) < 0.5, "after resizing to \(width) px the top line is \(line)")
    }

    /// The version this replaces kept whatever line was at the top when the
    /// width changed, even if the text had already drifted, and locked that in.
    @Test func aWidthChangeGoesBackToTheSyncedLineNotTheDriftedOne() async throws {
        let page = try await openPage()
        try await page.driftWithBareWidthChange(rem: 90)
        let drifted = try await page.topLine()
        #expect(abs(drifted - 158) > 20, "setup: the text drifted (\(drifted))")
        try await page.run("setContentWidth(rem)", ["rem": 46])
        let after = try await page.topLine()
        #expect(abs(after - 158) < 0.5, "expected the synced line 158, got \(after)")
    }

    /// Editing at the end of a document keeps both panes at their ends.
    @Test func aPageFollowingAnEditorAtItsEndStaysAtTheEnd() async throws {
        let page = try await openPage()
        try await page.run("setScrollPosition(300, true, 300, true, 1, 0, 60)")
        try await page.run("setContentWidth(rem)", ["rem": 90])
        let offset = try await page.number("return window.scrollY")
        let max = try await page.number("return maxScroll()")
        #expect(max > 0)
        #expect(abs(offset - max) < 1, "scrollY \(offset) of \(max)")
    }
}
