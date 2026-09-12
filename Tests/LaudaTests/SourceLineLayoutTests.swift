import AppKit
import Testing
@testable import Lauda

/// The line ↔ position math behind scroll sync and outline navigation.
@MainActor
struct SourceLineLayoutTests {
    private func makeLayout(lines count: Int) -> (SourceLineLayout, NSTextView, NSScrollView) {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 0, height: 10)
        scrollView.documentView = textView
        textView.string = (0..<count).map { "line \($0)" }.joined(separator: "\n")
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        textView.sizeToFit()
        let layout = SourceLineLayout()
        layout.textView = textView
        return (layout, textView, scrollView)
    }

    @Test func topPaddingMapsToNegativeLines() {
        let (layout, _, _) = makeLayout(lines: 20)
        #expect(layout.line(atScrollOffset: 0) == -1)
        #expect(layout.scrollOffset(forLine: -1) == 0)
        #expect(layout.scrollOffset(forLine: 0) == 10)
    }

    @Test(arguments: [0.0, 3.0, 7.5, 12.0])
    func lineAndOffsetRoundTrip(line: Double) throws {
        let (layout, _, _) = makeLayout(lines: 20)
        let offset = try #require(layout.scrollOffset(forLine: line))
        let roundTripped = try #require(layout.line(atScrollOffset: offset))
        #expect(abs(roundTripped - line) < 0.01, "line \(line) came back as \(roundTripped)")
    }

    @Test func followsProportionallyWithoutALineMap() throws {
        let (layout, textView, scrollView) = makeLayout(lines: 40)
        let maxOffset = textView.frame.height - scrollView.contentView.bounds.height
        let target = try #require(layout.targetOffset(for: ScrollSync(line: nil, fraction: 0.5)))
        #expect(abs(target - maxOffset * 0.5) < 0.5, "target \(target) for max \(maxOffset)")
    }
}
