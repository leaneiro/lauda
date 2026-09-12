import AppKit
import Testing
@testable import Lauda

@MainActor
struct EditorFindTests {
    private func makeFind(_ text: String, caret: Int = 0) -> (EditorFind, NSTextView) {
        let textView = NSTextView()
        textView.string = text
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        let find = EditorFind()
        find.textView = textView
        return (find, textView)
    }

    @Test func countsMatchesCaseInsensitivelyStartingAtTheCaret() {
        let (find, _) = makeFind("Cat, cat and CAT", caret: 3)
        let counts = find.update("cat")
        #expect(counts.total == 3)
        #expect(counts.current == 2)
    }

    @Test func steppingWrapsAround() {
        let (find, _) = makeFind("a a a")
        #expect(find.update("a").current == 1)
        #expect(find.step(forward: true).current == 2)
        #expect(find.step(forward: true).current == 3)
        #expect(find.step(forward: true).current == 1)
        #expect(find.step(forward: false).current == 3)
    }

    @Test func editsRefreshTheCountsAndTellTheFindBar() {
        let (find, textView) = makeFind("one two")
        #expect(find.update("o").total == 2)
        var reported: (current: Int, total: Int)?
        find.countsChanged = { reported = ($0, $1) }
        textView.string = "one two too"
        find.refreshAfterEdit()
        #expect(reported?.total == 4)
    }

    @Test func clearForgetsTheQuery() {
        let (find, _) = makeFind("abc")
        _ = find.update("b")
        find.clear()
        #expect(find.query == "")
        #expect(find.step(forward: true).total == 0)
    }
}
