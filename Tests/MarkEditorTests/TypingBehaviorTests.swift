import XCTest
@testable import MarkEditor

final class ListContinuationTests: XCTestCase {
    func testContinuesBulletList() {
        let action = ListContinuation.newlineAction(forLine: "- item", caretOffset: 6)
        XCTAssertEqual(action, .continueList(insertion: "\n- "))
    }

    func testContinuesIndentedBullet() {
        let action = ListContinuation.newlineAction(forLine: "  * sub", caretOffset: 7)
        XCTAssertEqual(action, .continueList(insertion: "\n  * "))
    }

    func testIncrementsOrderedList() {
        let action = ListContinuation.newlineAction(forLine: "3. passo", caretOffset: 8)
        XCTAssertEqual(action, .continueList(insertion: "\n4. "))
    }

    func testKeepsOrderedDelimiterStyle() {
        let action = ListContinuation.newlineAction(forLine: "1) passo", caretOffset: 8)
        XCTAssertEqual(action, .continueList(insertion: "\n2) "))
    }

    func testContinuesTaskListUnchecked() {
        let action = ListContinuation.newlineAction(forLine: "- [x] feito", caretOffset: 11)
        XCTAssertEqual(action, .continueList(insertion: "\n- [ ] "))
    }

    func testEmptyItemEndsList() {
        let action = ListContinuation.newlineAction(forLine: "- ", caretOffset: 2)
        XCTAssertEqual(action, .endList(prefixLength: 2))
    }

    func testEmptyTaskItemEndsList() {
        let action = ListContinuation.newlineAction(forLine: "- [ ] ", caretOffset: 6)
        XCTAssertEqual(action, .endList(prefixLength: 6))
    }

    func testNonListLineDoesNothing() {
        XCTAssertEqual(ListContinuation.newlineAction(forLine: "texto normal", caretOffset: 5), .none)
    }

    func testCaretInsideMarkerDoesNothing() {
        XCTAssertEqual(ListContinuation.newlineAction(forLine: "- item", caretOffset: 1), .none)
    }

    func testHorizontalRuleIsNotAList() {
        XCTAssertEqual(ListContinuation.newlineAction(forLine: "---", caretOffset: 3), .none)
    }

    func testLineInfoIndentUnit() {
        XCTAssertEqual(ListContinuation.lineInfo(forLine: "- item")?.indentUnit, 2)
        XCTAssertEqual(ListContinuation.lineInfo(forLine: "10. item")?.indentUnit, 4)
        XCTAssertEqual(ListContinuation.lineInfo(forLine: "- [ ] tarefa")?.indentUnit, 2)
        XCTAssertNil(ListContinuation.lineInfo(forLine: "sem lista"))
    }
}

final class TypingSubstitutionsTests: XCTestCase {
    private func substitute(text: String, typing: String, at location: Int) -> (NSRange, String)? {
        TypingSubstitutions.substitution(
            in: text as NSString,
            affectedRange: NSRange(location: location, length: 0),
            replacement: typing
        )
    }

    func testRightArrow() {
        let result = substitute(text: "a -", typing: ">", at: 3)
        XCTAssertEqual(result?.0, NSRange(location: 2, length: 1))
        XCTAssertEqual(result?.1, "→")
    }

    func testLeftArrow() {
        let result = substitute(text: "a <", typing: "-", at: 3)
        XCTAssertEqual(result?.0, NSRange(location: 2, length: 1))
        XCTAssertEqual(result?.1, "←")
    }

    func testNoSubstitutionWithoutPriorCharacter() {
        XCTAssertNil(substitute(text: "abc", typing: ">", at: 3))
        XCTAssertNil(substitute(text: "", typing: ">", at: 0))
    }

    func testPlainDashIsUntouched() {
        XCTAssertNil(substitute(text: "a b", typing: "-", at: 3))
    }
}

final class EditorTextViewURLTests: XCTestCase {
    func testAcceptsHTTPAndHTTPS() {
        XCTAssertTrue(EditorTextView.isLikelyURL("https://example.com/pagina"))
        XCTAssertTrue(EditorTextView.isLikelyURL("http://example.com"))
    }

    func testRejectsPlainTextAndOtherSchemes() {
        XCTAssertFalse(EditorTextView.isLikelyURL("apenas texto"))
        XCTAssertFalse(EditorTextView.isLikelyURL("file:///etc/passwd"))
        XCTAssertFalse(EditorTextView.isLikelyURL("texto com https://example.com dentro"))
        XCTAssertFalse(EditorTextView.isLikelyURL(""))
    }
}
