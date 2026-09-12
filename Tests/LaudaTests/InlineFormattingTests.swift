import Foundation
import Testing
@testable import Lauda

struct InlineFormattingTests {
    private func apply(_ edit: TextEdit, to text: NSString) -> String {
        text.replacingCharacters(in: edit.range, with: edit.replacement)
    }

    @Test func caretOutsideAWordInsertsAnEmptyPairWithTheCaretInside() {
        let text = "one  two" as NSString
        let edit = InlineFormatting.toggle(
            "**", in: text, selection: NSRange(location: 4, length: 0), wordRange: NSRange(location: 3, length: 2))
        #expect(apply(edit, to: text) == "one **** two")
        #expect(edit.selection == NSRange(location: 6, length: 0))
    }

    @Test func caretInsideAWordWrapsTheWord() {
        let text = "say hello now" as NSString
        let edit = InlineFormatting.toggle(
            "**", in: text, selection: NSRange(location: 6, length: 0), wordRange: NSRange(location: 4, length: 5))
        #expect(apply(edit, to: text) == "say **hello** now")
        #expect(edit.selection == NSRange(location: 6, length: 5))
    }

    @Test func selectionIncludingTheMarkersIsUnwrapped() {
        let text = "a **bold** b" as NSString
        let selection = NSRange(location: 2, length: 8)
        let edit = InlineFormatting.toggle("**", in: text, selection: selection, wordRange: selection)
        #expect(apply(edit, to: text) == "a bold b")
        #expect(edit.selection == NSRange(location: 2, length: 4))
    }

    @Test func markersJustOutsideTheSelectionAreRemoved() {
        let text = "a **bold** b" as NSString
        let selection = NSRange(location: 4, length: 4)
        let edit = InlineFormatting.toggle("**", in: text, selection: selection, wordRange: selection)
        #expect(apply(edit, to: text) == "a bold b")
        #expect(edit.selection == NSRange(location: 2, length: 4))
    }

    @Test func plainSelectionIsWrapped() {
        let text = "make it italic" as NSString
        let selection = NSRange(location: 8, length: 6)
        let edit = InlineFormatting.toggle("*", in: text, selection: selection, wordRange: selection)
        #expect(apply(edit, to: text) == "make it *italic*")
        #expect(edit.selection == NSRange(location: 9, length: 6))
    }

    @Test func linkTakesAURLFromTheClipboard() {
        let text = "see docs here" as NSString
        let edit = InlineFormatting.link(
            in: text, selection: NSRange(location: 4, length: 4), clipboard: " https://example.com ")
        #expect(apply(edit, to: text) == "see [docs](https://example.com) here")
        #expect(edit.selection == NSRange(location: 11, length: 19))
    }

    @Test func linkWithoutAURLLeavesTheCaretInTheParentheses() {
        let text = "see docs here" as NSString
        let edit = InlineFormatting.link(
            in: text, selection: NSRange(location: 4, length: 4), clipboard: "not a url")
        #expect(apply(edit, to: text) == "see [docs]() here")
        #expect(edit.selection == NSRange(location: 11, length: 0))
    }

    @Test func linkWithNothingSelectedPutsTheCaretInTheBrackets() {
        let text = "x" as NSString
        let edit = InlineFormatting.link(in: text, selection: NSRange(location: 1, length: 0), clipboard: nil)
        #expect(apply(edit, to: text) == "x[]()")
        #expect(edit.selection == NSRange(location: 2, length: 0))
    }
}
