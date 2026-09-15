import Foundation
import Testing
@testable import Lauda

struct OutlineJumpTests {
    private let text = (0..<10).map { "line \($0)" }.joined(separator: "\n")
    private let heading = OutlineItem(id: 0, level: 2, title: "Section", line: 4)

    @Test func bothPanesScrollToTheHeadingsLine() {
        let jump = OutlineJump(to: heading, in: text, mode: .split)
        #expect(jump.scrollSync.line == 4)
        #expect(jump.scrollSync.fraction == 0.4)
        #expect(jump.scrollSync.source == .navigation)
    }

    @Test(arguments: [ViewMode.editorOnly, .split])
    func theCaretMovesWhenTheEditorIsShowing(mode: ViewMode) {
        #expect(OutlineJump(to: heading, in: text, mode: mode).caretLine == 4)
    }

    @Test func thePreviewOnlyModeLeavesTheCaretAlone() {
        #expect(OutlineJump(to: heading, in: text, mode: .previewOnly).caretLine == nil)
    }

    @Test func anEmptyDocumentDoesNotDivideByZero() {
        let first = OutlineItem(id: 0, level: 1, title: "Title", line: 0)
        let jump = OutlineJump(to: first, in: "", mode: .split)
        #expect(jump.scrollSync.fraction == 0)
        #expect(jump.scrollSync.line == 0)
    }
}
