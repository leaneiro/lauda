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
}

struct TypingSubstitutionsTests {
    private func substitute(text: String, typing: String, at location: Int) -> (NSRange, String)? {
        TypingSubstitutions.substitution(
            in: text as NSString,
            affectedRange: NSRange(location: location, length: 0),
            replacement: typing
        )
    }

    @Test func rightArrow() {
        let result = substitute(text: "a -", typing: ">", at: 3)
        #expect(result?.0 == NSRange(location: 2, length: 1))
        #expect(result?.1 == "→")
    }

    @Test func leftArrow() {
        let result = substitute(text: "a <", typing: "-", at: 3)
        #expect(result?.0 == NSRange(location: 2, length: 1))
        #expect(result?.1 == "←")
    }

    @Test func noSubstitutionWithoutPriorCharacter() {
        #expect(substitute(text: "abc", typing: ">", at: 3) == nil)
        #expect(substitute(text: "", typing: ">", at: 0) == nil)
    }

    @Test func plainDashIsUntouched() {
        #expect(substitute(text: "a b", typing: "-", at: 3) == nil)
    }
}

struct EditorTextViewURLTests {
    @Test(arguments: ["https://example.com/page", "http://example.com"])
    func acceptsHTTPAndHTTPS(text: String) {
        #expect(EditorTextView.isLikelyURL(text))
    }

    @Test(arguments: ["just text", "file:///etc/passwd", "text with https://example.com inside", ""])
    func rejectsPlainTextAndOtherSchemes(text: String) {
        #expect(!EditorTextView.isLikelyURL(text))
    }
}
