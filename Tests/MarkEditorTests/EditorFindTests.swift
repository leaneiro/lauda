import XCTest
@testable import MarkEditor

final class EditorFindTests: XCTestCase {
    private func makeFind(_ text: String, caret: Int = 0) -> (EditorFind, NSTextView) {
        let textView = NSTextView()
        textView.string = text
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        let find = EditorFind()
        find.textView = textView
        return (find, textView)
    }

    func testCountsMatchesCaseInsensitivelyStartingAtTheCaret() {
        let (find, _) = makeFind("Cat, cat and CAT", caret: 3)
        let counts = find.update("cat")
        XCTAssertEqual(counts.total, 3)
        XCTAssertEqual(counts.current, 2)
    }

    func testSteppingWrapsAround() {
        let (find, _) = makeFind("a a a")
        XCTAssertEqual(find.update("a").current, 1)
        XCTAssertEqual(find.step(forward: true).current, 2)
        XCTAssertEqual(find.step(forward: true).current, 3)
        XCTAssertEqual(find.step(forward: true).current, 1)
        XCTAssertEqual(find.step(forward: false).current, 3)
    }

    func testEditsRefreshTheCountsAndTellTheFindBar() {
        let (find, textView) = makeFind("one two")
        XCTAssertEqual(find.update("o").total, 2)
        var reported: (current: Int, total: Int)?
        find.countsChanged = { reported = ($0, $1) }
        textView.string = "one two too"
        find.refreshAfterEdit()
        XCTAssertEqual(reported?.total, 4)
    }

    func testClearForgetsTheQuery() {
        let (find, _) = makeFind("abc")
        _ = find.update("b")
        find.clear()
        XCTAssertEqual(find.query, "")
        XCTAssertEqual(find.step(forward: true).total, 0)
    }
}
