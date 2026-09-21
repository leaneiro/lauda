import Foundation
import Testing
@testable import Lauda

struct ListContinuationTests {
    @Test func continuesBulletList() {
        #expect(ListContinuation.newlineAction(forLine: "- item", caretOffset: 6) == .continueList(insertion: "\n- "))
    }

    @Test func continuesIndentedBullet() {
        #expect(ListContinuation.newlineAction(forLine: "  * sub", caretOffset: 7) == .continueList(insertion: "\n  * "))
    }

    @Test func incrementsOrderedList() {
        #expect(ListContinuation.newlineAction(forLine: "3. passo", caretOffset: 8) == .continueList(insertion: "\n4. "))
    }

    @Test func keepsOrderedDelimiterStyle() {
        #expect(ListContinuation.newlineAction(forLine: "1) passo", caretOffset: 8) == .continueList(insertion: "\n2) "))
    }

    @Test func continuesTaskListUnchecked() {
        #expect(ListContinuation.newlineAction(forLine: "- [x] done", caretOffset: 10) == .continueList(insertion: "\n- [ ] "))
    }

    @Test func emptyItemEndsList() {
        #expect(ListContinuation.newlineAction(forLine: "- ", caretOffset: 2) == .endList(prefixLength: 2))
    }

    @Test func emptyTaskItemEndsList() {
        #expect(ListContinuation.newlineAction(forLine: "- [ ] ", caretOffset: 6) == .endList(prefixLength: 6))
    }

    @Test func nonListLineDoesNothing() {
        #expect(ListContinuation.newlineAction(forLine: "plain text", caretOffset: 5) == .none)
    }

    @Test func caretInsideMarkerDoesNothing() {
        #expect(ListContinuation.newlineAction(forLine: "- item", caretOffset: 1) == .none)
    }

    @Test func horizontalRuleIsNotAList() {
        #expect(ListContinuation.newlineAction(forLine: "---", caretOffset: 3) == .none)
    }

    @Test func lineInfoIndentUnit() {
        #expect(ListContinuation.lineInfo(forLine: "- item")?.indentUnit == 2)
        #expect(ListContinuation.lineInfo(forLine: "10. item")?.indentUnit == 4)
        #expect(ListContinuation.lineInfo(forLine: "- [ ] task")?.indentUnit == 2)
        #expect(ListContinuation.lineInfo(forLine: "no list") == nil)
    }

    // MARK: - The edits Return, Tab and Shift-Tab make

    private func apply(_ edit: TextEdit, to text: NSString) -> String {
        text.replacingCharacters(in: edit.range, with: edit.replacement)
    }

    @Test func returnOnAnItemWritesTheNextOnesPrefix() throws {
        let text = "- one" as NSString
        let edit = try #require(ListContinuation.newlineEdit(in: text, selection: NSRange(location: 5, length: 0)))
        #expect(apply(edit, to: text) == "- one\n- ")
        #expect(edit.selection == NSRange(location: 8, length: 0))
    }

    @Test func returnOnAnEmptyItemTakesTheItemWithIt() throws {
        let text = "- one\n- " as NSString
        let edit = try #require(ListContinuation.newlineEdit(in: text, selection: NSRange(location: 8, length: 0)))
        #expect(apply(edit, to: text) == "- one\n")
        #expect(edit.selection == NSRange(location: 6, length: 0))
    }

    @Test func returnOutsideAListIsLeftAlone() {
        let text = "a paragraph" as NSString
        #expect(ListContinuation.newlineEdit(in: text, selection: NSRange(location: 11, length: 0)) == nil)
        // Nor with a selection: that is a replacement, not a continuation.
        let list = "- one" as NSString
        #expect(ListContinuation.newlineEdit(in: list, selection: NSRange(location: 2, length: 3)) == nil)
    }

    @Test func tabIndentsTheItemByItsOwnMarkersWidth() throws {
        let text = "- one\n- two" as NSString
        guard case .edit(let edit) = ListContinuation.indent(
            in: text, selection: NSRange(location: 8, length: 0), outdent: false
        ) else { Issue.record("expected an edit"); return }
        #expect(apply(edit, to: text) == "- one\n  - two")
        #expect(edit.selection == NSRange(location: 10, length: 0))

        let numbered = "1. one" as NSString
        guard case .edit(let numberedEdit) = ListContinuation.indent(
            in: numbered, selection: NSRange(location: 3, length: 0), outdent: false
        ) else { Issue.record("expected an edit"); return }
        // A number's marker is wider, so its step is too.
        #expect(apply(numberedEdit, to: numbered) == "   1. one")
    }

    @Test func shiftTabTakesOneStepBack() throws {
        let text = "  - deep" as NSString
        guard case .edit(let edit) = ListContinuation.indent(
            in: text, selection: NSRange(location: 4, length: 0), outdent: true
        ) else { Issue.record("expected an edit"); return }
        #expect(apply(edit, to: text) == "- deep")
        #expect(edit.selection == NSRange(location: 2, length: 0))
    }

    @Test func shiftTabOnATabIndentTakesTheTab() throws {
        let text = "\t- deep" as NSString
        guard case .edit(let edit) = ListContinuation.indent(
            in: text, selection: NSRange(location: 3, length: 0), outdent: true
        ) else { Issue.record("expected an edit"); return }
        #expect(apply(edit, to: text) == "- deep")
    }

    /// At the left edge there is nothing to take off, and Shift-Tab still
    /// belongs to the list rather than to the text view.
    @Test func shiftTabAtTheLeftEdgeChangesNothing() {
        let text = "- one" as NSString
        #expect(ListContinuation.indent(in: text, selection: NSRange(location: 2, length: 0), outdent: true)
            == .nothingToRemove)
    }

    @Test func tabFurtherAlongTheLineIsATab() {
        let text = "- one two" as NSString
        #expect(ListContinuation.indent(in: text, selection: NSRange(location: 7, length: 0), outdent: false)
            == .notAList)
        let paragraph = "plain text" as NSString
        #expect(ListContinuation.indent(in: paragraph, selection: NSRange(location: 2, length: 0), outdent: false)
            == .notAList)
    }
}
