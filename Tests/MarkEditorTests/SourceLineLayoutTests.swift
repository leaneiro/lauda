import XCTest
@testable import MarkEditor

/// The line ↔ position math behind scroll sync and outline navigation.
final class SourceLineLayoutTests: XCTestCase {
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

    func testTopPaddingMapsToNegativeLines() {
        let (layout, _, _) = makeLayout(lines: 20)
        XCTAssertEqual(layout.line(atScrollOffset: 0), -1)
        XCTAssertEqual(layout.scrollOffset(forLine: -1), 0)
        XCTAssertEqual(layout.scrollOffset(forLine: 0), 10)
    }

    func testLineAndOffsetRoundTrip() throws {
        let (layout, _, _) = makeLayout(lines: 20)
        for line in [0.0, 3.0, 7.5, 12.0] {
            let offset = try XCTUnwrap(layout.scrollOffset(forLine: line))
            XCTAssertEqual(try XCTUnwrap(layout.line(atScrollOffset: offset)), line, accuracy: 0.01)
        }
    }

    func testFollowsProportionallyWithoutALineMap() throws {
        let (layout, textView, scrollView) = makeLayout(lines: 40)
        let maxOffset = textView.frame.height - scrollView.contentView.bounds.height
        let target = try XCTUnwrap(layout.targetOffset(for: ScrollSync(line: nil, fraction: 0.5)))
        XCTAssertEqual(target, maxOffset * 0.5, accuracy: 0.5)
    }
}
