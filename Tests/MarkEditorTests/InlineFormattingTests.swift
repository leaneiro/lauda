import XCTest
@testable import MarkEditor

final class InlineFormattingTests: XCTestCase {
    private func apply(_ edit: TextEdit, to text: NSString) -> String {
        text.replacingCharacters(in: edit.range, with: edit.replacement)
    }

    func testCaretOutsideAWordInsertsAnEmptyPairWithTheCaretInside() {
        let text = "one  two" as NSString
        let edit = InlineFormatting.toggle(
            "**", in: text, selection: NSRange(location: 4, length: 0), wordRange: NSRange(location: 3, length: 2))
        XCTAssertEqual(apply(edit, to: text), "one **** two")
        XCTAssertEqual(edit.selection, NSRange(location: 6, length: 0))
    }

    func testCaretInsideAWordWrapsTheWord() {
        let text = "say hello now" as NSString
        let edit = InlineFormatting.toggle(
            "**", in: text, selection: NSRange(location: 6, length: 0), wordRange: NSRange(location: 4, length: 5))
        XCTAssertEqual(apply(edit, to: text), "say **hello** now")
        XCTAssertEqual(edit.selection, NSRange(location: 6, length: 5))
    }

    func testSelectionIncludingTheMarkersIsUnwrapped() {
        let text = "a **bold** b" as NSString
        let selection = NSRange(location: 2, length: 8)
        let edit = InlineFormatting.toggle("**", in: text, selection: selection, wordRange: selection)
        XCTAssertEqual(apply(edit, to: text), "a bold b")
        XCTAssertEqual(edit.selection, NSRange(location: 2, length: 4))
    }

    func testMarkersJustOutsideTheSelectionAreRemoved() {
        let text = "a **bold** b" as NSString
        let selection = NSRange(location: 4, length: 4)
        let edit = InlineFormatting.toggle("**", in: text, selection: selection, wordRange: selection)
        XCTAssertEqual(apply(edit, to: text), "a bold b")
        XCTAssertEqual(edit.selection, NSRange(location: 2, length: 4))
    }

    func testPlainSelectionIsWrapped() {
        let text = "make it italic" as NSString
        let selection = NSRange(location: 8, length: 6)
        let edit = InlineFormatting.toggle("*", in: text, selection: selection, wordRange: selection)
        XCTAssertEqual(apply(edit, to: text), "make it *italic*")
        XCTAssertEqual(edit.selection, NSRange(location: 9, length: 6))
    }

    func testLinkTakesAURLFromTheClipboard() {
        let text = "see docs here" as NSString
        let edit = InlineFormatting.link(
            in: text, selection: NSRange(location: 4, length: 4), clipboard: " https://example.com ")
        XCTAssertEqual(apply(edit, to: text), "see [docs](https://example.com) here")
        XCTAssertEqual(edit.selection, NSRange(location: 11, length: 19))
    }

    func testLinkWithoutAURLLeavesTheCaretInTheParentheses() {
        let text = "see docs here" as NSString
        let edit = InlineFormatting.link(
            in: text, selection: NSRange(location: 4, length: 4), clipboard: "not a url")
        XCTAssertEqual(apply(edit, to: text), "see [docs]() here")
        XCTAssertEqual(edit.selection, NSRange(location: 11, length: 0))
    }

    func testLinkWithNothingSelectedPutsTheCaretInTheBrackets() {
        let text = "x" as NSString
        let edit = InlineFormatting.link(in: text, selection: NSRange(location: 1, length: 0), clipboard: nil)
        XCTAssertEqual(apply(edit, to: text), "x[]()")
        XCTAssertEqual(edit.selection, NSRange(location: 2, length: 0))
    }
}
