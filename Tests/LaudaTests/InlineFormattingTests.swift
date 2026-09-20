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

    @Test func strikethroughWrapsAndUnwrapsLikeTheOtherMarkers() {
        let text = "keep it short" as NSString
        let selection = NSRange(location: 8, length: 5)
        let wrapped = InlineFormatting.toggle("~~", in: text, selection: selection, wordRange: selection)
        #expect(apply(wrapped, to: text) == "keep it ~~short~~")
        #expect(wrapped.selection == NSRange(location: 10, length: 5))

        let struck = "keep it ~~short~~" as NSString
        let undone = InlineFormatting.toggle(
            "~~", in: struck, selection: NSRange(location: 10, length: 5), wordRange: NSRange(location: 10, length: 5))
        #expect(apply(undone, to: struck) == "keep it short")
    }

    @Test func underlineWrapsTheSelectionInItsTags() {
        let text = "read this part" as NSString
        let selection = NSRange(location: 5, length: 4)
        let edit = InlineFormatting.toggle("<u>", "</u>", in: text, selection: selection, wordRange: selection)
        #expect(apply(edit, to: text) == "read <u>this</u> part")
        #expect(edit.selection == NSRange(location: 8, length: 4))
    }

    @Test func underlineIsUndoneFromInsideOrOutsideItsTags() {
        let text = "read <u>this</u> part" as NSString
        let inside = NSRange(location: 8, length: 4)
        let fromInside = InlineFormatting.toggle("<u>", "</u>", in: text, selection: inside, wordRange: inside)
        #expect(apply(fromInside, to: text) == "read this part")
        #expect(fromInside.selection == NSRange(location: 5, length: 4))

        let whole = NSRange(location: 5, length: 11)
        let fromOutside = InlineFormatting.toggle("<u>", "</u>", in: text, selection: whole, wordRange: whole)
        #expect(apply(fromOutside, to: text) == "read this part")
        #expect(fromOutside.selection == NSRange(location: 5, length: 4))
    }

    @Test func underlineWithTheCaretOutsideAWordLeavesItBetweenTheTags() {
        let text = "one  two" as NSString
        let caret = NSRange(location: 4, length: 0)
        let edit = InlineFormatting.toggle("<u>", "</u>", in: text, selection: caret, wordRange: NSRange(location: 3, length: 2))
        #expect(apply(edit, to: text) == "one <u></u> two")
        #expect(edit.selection == NSRange(location: 7, length: 0))
    }

    // MARK: - A URL pasted over a selection

    @Test func pastingAURLOverWordsMakesALinkOfThem() throws {
        let text = "see the docs here" as NSString
        let selection = NSRange(location: 4, length: 8)
        let edit = try #require(InlineFormatting.linkFromPaste(
            in: text, selection: selection, clipboard: " https://example.com\n"))
        #expect(apply(edit, to: text) == "see [the docs](https://example.com) here")
        // The caret lands after the link, where typing goes on.
        #expect(edit.selection == NSRange(location: 35, length: 0))
    }

    @Test(arguments: [
        ("nothing selected", NSRange(location: 4, length: 0), "https://example.com"),
        ("the clipboard is not a URL", NSRange(location: 4, length: 8), "just words"),
        ("the clipboard is empty", NSRange(location: 4, length: 8), ""),
    ])
    func pastingAsUsualWhenTheRuleDoesNotApply(_ reason: String, selection: NSRange, clipboard: String) {
        let text = "see the docs here" as NSString
        #expect(
            InlineFormatting.linkFromPaste(in: text, selection: selection, clipboard: clipboard) == nil,
            "\(reason)"
        )
    }

    /// Over a URL, replacing is what pasting a URL means.
    @Test func pastingAURLOverAURLReplacesIt() {
        let text = "see https://old.example here" as NSString
        let selection = NSRange(location: 4, length: 19)
        #expect(InlineFormatting.linkFromPaste(
            in: text, selection: selection, clipboard: "https://new.example") == nil)
    }

    /// A selection across lines would put a line break inside the link text.
    @Test func pastingAURLOverSeveralLinesReplacesThem() {
        let text = "first line\nsecond line" as NSString
        let selection = NSRange(location: 0, length: 16)
        #expect(InlineFormatting.linkFromPaste(
            in: text, selection: selection, clipboard: "https://example.com") == nil)
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
