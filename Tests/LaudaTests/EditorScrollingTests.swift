import AppKit
import Testing
@testable import Lauda

/// How the editor pane keeps its place when its text reflows, with the
/// panes scrolling together or apart.
@MainActor
struct EditorScrollingTests {
    /// The app's own editor, 80 short lines in a 300 by 100 scroll view,
    /// with a shared position standing in for the preview's.
    private func makePane(sharedLine: Double) -> (EditorScrolling, SourceLineLayout, NSScrollView) {
        let (scrollView, textView) = EditorTextView.inScrollView()
        scrollView.frame = NSRect(x: 0, y: 0, width: 300, height: 100)
        scrollView.tile()
        textView.string = (0..<80).map { "line \($0)" }.joined(separator: "\n")
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        textView.sizeToFit()
        let lines = SourceLineLayout()
        lines.textView = textView
        let scrolling = EditorScrolling(lines: lines)
        scrolling.textView = textView
        scrolling.sharedPosition = { ScrollSync(line: sharedLine, fraction: 0.5) }
        return (scrolling, lines, scrollView)
    }

    /// Scrolls the pane to a line and lets the sync hear it, as a reader's
    /// scroll would.
    private func scroll(
        _ scrollView: NSScrollView, toLine line: Double, in lines: SourceLineLayout, heardBy scrolling: EditorScrolling
    ) throws {
        let offset = try #require(lines.scrollOffset(forLine: line))
        scrollView.scrollVertically(to: offset)
        scrolling.boundsDidChange(Notification(name: NSView.boundsDidChangeNotification, object: scrollView.contentView))
    }

    /// Narrows the pane, as a divider drag would, and lets the sync hear it.
    private func narrow(_ scrollView: NSScrollView, heardBy scrolling: EditorScrolling) {
        scrollView.setFrameSize(NSSize(width: 200, height: scrollView.frame.height))
        scrollView.tile()
        scrolling.frameDidChange(Notification(name: NSView.frameDidChangeNotification, object: scrollView.contentView))
    }

    private func lineShown(by scrollView: NSScrollView, in lines: SourceLineLayout) throws -> Double {
        try #require(lines.line(atScrollOffset: scrollView.contentView.bounds.origin.y))
    }

    @Test func togetherAReflowKeepsTheSharedLine() throws {
        let (scrolling, lines, scrollView) = makePane(sharedLine: 30)
        try scroll(scrollView, toLine: 10, in: lines, heardBy: scrolling)
        narrow(scrollView, heardBy: scrolling)
        #expect(abs(try lineShown(by: scrollView, in: lines) - 30) < 0.01)
    }

    @Test func apartAReflowKeepsThePanesOwnLine() throws {
        let (scrolling, lines, scrollView) = makePane(sharedLine: 30)
        scrolling.isLinked = false
        try scroll(scrollView, toLine: 10, in: lines, heardBy: scrolling)
        narrow(scrollView, heardBy: scrolling)
        #expect(abs(try lineShown(by: scrollView, in: lines) - 10) < 0.01)
    }

    @Test func tellsWhetherTheTextIsTallerThanThePane() throws {
        let (scrolling, lines, scrollView) = makePane(sharedLine: 0)
        try scroll(scrollView, toLine: 0, in: lines, heardBy: scrolling)
        #expect(scrolling.scrollable == true)
        let textView = try #require(scrollView.documentView as? NSTextView)
        textView.string = "one line"
        textView.sizeToFit()
        scrolling.contentDidChange(Notification(name: NSView.frameDidChangeNotification, object: textView))
        #expect(scrolling.scrollable == false)
    }

    @Test func apartAJumpTakenIsTheLineKept() throws {
        let (scrolling, lines, scrollView) = makePane(sharedLine: 30)
        scrolling.isLinked = false
        try scroll(scrollView, toLine: 10, in: lines, heardBy: scrolling)
        scrolling.applyRemote(ScrollSync(line: 50, fraction: 0.6, source: .navigation))
        narrow(scrollView, heardBy: scrolling)
        #expect(abs(try lineShown(by: scrollView, in: lines) - 50) < 0.01)
    }
}
