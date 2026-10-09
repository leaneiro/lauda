import AppKit
import SwiftUI
import Testing
import WebKit
@testable import Lauda

/// A document's two panes in an offscreen window, driven the way a reader
/// drives them: a scroll in one pane, and a look at where the other is.
@MainActor
private final class PanesWindow {
    let document = MarkdownDocument()
    private let workspace: Workspace
    private let window: NSWindow
    private var textView: NSTextView?
    private var webView: WKWebView?

    init(paragraphs: Int) {
        let defaults = TestDefaults()
        AppSettings.registerDefaults(in: defaults)
        workspace = Workspace(defaults: defaults, showsWindow: false)
        document.text = (0..<paragraphs).map { "Paragraph \($0) of the document." }.joined(separator: "\n\n")
        window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 1200, height: 700),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: DocumentPanes(document: document, workspace: workspace))
        window.orderFrontRegardless()
    }

    /// Takes the panes down. Left up, their page and editor keep drawing
    /// off screen, and the WebKit tests that time frames lose some.
    func close() {
        window.contentView = nil
        window.close()
    }

    /// Waits for both panes to come up, with the page answering.
    func waitUntilUp() async throws {
        for _ in 0..<100 {
            if textView == nil { textView = Self.find(NSTextView.self, in: window.contentView) }
            if webView == nil, let found = Self.find(WKWebView.self, in: window.contentView) {
                found.keepRunningOffscreen()
                webView = found
            }
            if textView != nil, webView != nil, (try? await number("return maxScroll()")) != nil {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("The panes never came up")
    }

    /// Polls for up to two seconds until `condition` holds.
    func waitUntil(_ condition: () async throws -> Bool) async throws -> Bool {
        for _ in 0..<40 where try await !condition() {
            try await Task.sleep(for: .milliseconds(50))
        }
        return try await condition()
    }

    /// Whether each pane has measured itself once: the editor has a reading
    /// of its own, and the page has told the app.
    func bothPanesMeasured() async throws -> Bool {
        let editor = document.editorActions.coordinator?.scrolling.scrollable != nil
        let page = try await number("return toldScrollable === null ? 0 : 1") == 1
        return editor && page
    }

    private static func find<View: NSView>(_ type: View.Type, in view: NSView?) -> View? {
        guard let view else { return nil }
        if let found = view as? View { return found }
        for subview in view.subviews {
            if let found = find(type, in: subview) { return found }
        }
        return nil
    }

    private func number(_ script: String, _ arguments: [String: Any] = [:]) async throws -> Double {
        let webView = try #require(webView)
        let value = try await webView.callAsyncJavaScript(script, arguments: arguments, contentWorld: PreviewWebView.contentWorld)
        return (value as? NSNumber)?.doubleValue ?? .nan
    }

    /// The fractional source line at the top of the editor.
    func editorTopLine() throws -> Double {
        let coordinator = try #require(document.editorActions.coordinator)
        let scrollView = try #require(textView?.enclosingScrollView)
        return try #require(coordinator.lines.line(atScrollOffset: scrollView.contentView.bounds.origin.y))
    }

    /// The fractional source line at the top of the page.
    func pageTopLine() async throws -> Double {
        try await number("return interpolate(lineAnchors(), window.scrollY, 1, 0)")
    }

    /// Scrolls the editor to a line, as the reader's wheel would.
    func scrollEditor(toLine line: Double) throws {
        let coordinator = try #require(document.editorActions.coordinator)
        let scrollView = try #require(textView?.enclosingScrollView)
        scrollView.scrollVertically(to: try #require(coordinator.lines.scrollOffset(forLine: line)))
    }

    /// Scrolls the page to a line, as the reader's wheel would.
    func scrollPage(toLine line: Double) async throws {
        let webView = try #require(webView)
        try await webView.callAsyncJavaScript(
            "window.scrollTo(0, interpolate(lineAnchors(), line, 0, 1))",
            arguments: ["line": line], contentWorld: PreviewWebView.contentWorld)
    }

    /// Polls for up to two seconds until a reading comes within `tolerance`
    /// of `target`; returns the last reading.
    func settled(_ read: () async throws -> Double, within tolerance: Double, of target: Double) async throws -> Double {
        var reading = try await read()
        for _ in 0..<40 where abs(reading - target) >= tolerance {
            try await Task.sleep(for: .milliseconds(50))
            reading = try await read()
        }
        return reading
    }

    /// Long enough for a scroll to have reached the other pane, had it been
    /// meant to; and for the page to take the next scroll for the reader's,
    /// since for a moment after a position it was given it takes scrolls
    /// for echoes of it.
    func pause() async throws {
        try await Task.sleep(for: .milliseconds(300))
    }
}

/// The chain on the divider: apart, each pane scrolls on its own; joined
/// again, the editor comes to the preview, and both follow each other.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)), .enabled(if: TestMachine.drawsWithMetal, "the panes draw through Metal"))
struct ScrollLinkPanesTests {
    private static let tolerance = 1.5

    @Test func apartThePanesScrollOnTheirOwnAndRejoinAtThePreview() async throws {
        let panes = PanesWindow(paragraphs: 300)
        defer { panes.close() }
        try await panes.waitUntilUp()
        // Both panes have told the document they have more than fits.
        #expect(try await panes.waitUntil { panes.document.panesScroll })

        // Together, the preview follows the editor.
        try panes.scrollEditor(toLine: 200)
        let followed = try await panes.settled(panes.pageTopLine, within: Self.tolerance, of: 200)
        #expect(abs(followed - 200) < Self.tolerance)

        // Apart, neither follows the other.
        panes.document.scrollsLinked = false
        try await panes.pause()
        try await panes.scrollPage(toLine: 250)
        try await panes.pause()
        #expect(abs(try panes.editorTopLine() - 200) < Self.tolerance)
        try panes.scrollEditor(toLine: 100)
        try await panes.pause()
        #expect(abs(try await panes.pageTopLine() - 250) < Self.tolerance)

        // Joined again, the editor comes to the preview, though the editor
        // scrolled last, and follows it from there.
        panes.document.scrollsLinked = true
        let rejoined = try await panes.settled(panes.editorTopLine, within: Self.tolerance, of: 250)
        #expect(abs(rejoined - 250) < Self.tolerance)
        try await panes.pause()
        try await panes.scrollPage(toLine: 50)
        let following = try await panes.settled(panes.editorTopLine, within: Self.tolerance, of: 50)
        #expect(abs(following - 50) < Self.tolerance)
    }

    @Test func aTextThatFitsLeavesNothingToScroll() async throws {
        let panes = PanesWindow(paragraphs: 2)
        defer { panes.close() }
        try await panes.waitUntilUp()
        #expect(try await panes.waitUntil(panes.bothPanesMeasured))
        try await panes.pause()
        #expect(!panes.document.editorScrollable)
        #expect(!panes.document.previewScrollable)
        #expect(!panes.document.panesScroll)
    }
}
