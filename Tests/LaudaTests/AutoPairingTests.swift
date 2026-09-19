import AppKit
import SwiftUI
import Testing
@testable import Lauda

/// Text with the caret as ‸, or a selection between « and ».
private func parse(_ marked: String) -> (text: String, selection: NSRange) {
    let string = marked as NSString
    let caret = string.range(of: "‸")
    if caret.location != NSNotFound {
        return (string.replacingCharacters(in: caret, with: ""), NSRange(location: caret.location, length: 0))
    }
    let open = string.range(of: "«")
    let close = string.range(of: "»")
    if open.location != NSNotFound, close.location != NSNotFound {
        let text = string.replacingOccurrences(of: "«", with: "").replacingOccurrences(of: "»", with: "")
        return (text, NSRange(location: open.location, length: close.location - open.location - 1))
    }
    return (marked, NSRange(location: string.length, length: 0))
}

private func render(_ text: String, _ selection: NSRange) -> String {
    let string = text as NSString
    guard selection.length > 0 else {
        return string.replacingCharacters(in: selection, with: "‸")
    }
    return string.replacingCharacters(in: selection, with: "«" + string.substring(with: selection) + "»")
}

/// The real editor, typed into the way keys type: through insertText with
/// no range, a runloop turn per key, and Delete as a command.
@MainActor
private final class Editor {
    let textView: EditorTextView
    let coordinator: MarkdownTextView.Coordinator

    init(_ marked: String = "") {
        let view = MarkdownTextView(
            text: .constant(""),
            scrollSync: .constant(ScrollSync()),
            actions: EditorActions(),
            fileURL: nil
        )
        coordinator = view.makeCoordinator()
        textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.isRichText = false
        textView.allowsUndo = true
        textView.delegate = coordinator
        coordinator.textView = textView
        let (text, selection) = parse(marked)
        textView.string = text
        textView.setSelectedRange(selection)
    }

    var state: String { render(textView.string, textView.selectedRange()) }

    func type(_ keys: String) {
        for key in keys {
            textView.insertText(String(key), replacementRange: NSRange(location: NSNotFound, length: 0))
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
    }

    func deleteBackward(times: Int = 1) {
        for _ in 0..<times {
            textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
    }

    func moveCaret(to location: Int) {
        textView.setSelectedRange(NSRange(location: location, length: 0))
    }

    /// A key an input method composes first, like the backtick on a
    /// Brazilian keyboard: marked, then committed by the next key.
    func typeWithDeadKey(_ key: String) {
        textView.setMarkedText(
            key,
            selectedRange: NSRange(location: (key as NSString).length, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        textView.insertText(key, replacementRange: NSRange(location: NSNotFound, length: 0))
        RunLoop.current.run(until: Date().addingTimeInterval(0.005))
    }
}

@MainActor
@Suite(.serialized)
struct AutoPairingTypingTests {
    static let pairs = [("(", ")"), ("[", "]"), ("{", "}"), ("\"", "\""), ("*", "*"), ("_", "_"), ("`", "`")]

    @Test(arguments: pairs)
    func anOpeningCharacterBringsItsClosingOne(pair: (String, String)) {
        let editor = Editor()
        editor.type(pair.0)
        #expect(editor.state == pair.0 + "‸" + pair.1)
    }

    @Test(arguments: pairs)
    func typingTheClosingCharacterStepsOverIt(pair: (String, String)) {
        let editor = Editor()
        editor.type(pair.0 + "a" + pair.1)
        #expect(editor.state == pair.0 + "a" + pair.1 + "‸")
    }

    @Test func boldAndBoldItalicTypeThrough() {
        let bold = Editor()
        bold.type("**bold**")
        #expect(bold.state == "**bold**‸")

        let both = Editor()
        both.type("***both***")
        #expect(both.state == "***both***‸")
    }

    @Test func linksAndTaskListsTypeThrough() {
        let link = Editor()
        link.type("[text](https://example.com)")
        #expect(link.state == "[text](https://example.com)‸")

        let task = Editor()
        task.type("- [ ] task")
        #expect(task.state == "- [ ] task‸")
    }

    /// A star followed by a space closes nothing: a list item, or arithmetic.
    @Test func aStarAndASpaceCloseNothing() {
        let list = Editor()
        list.type("* item")
        #expect(list.state == "* item‸")

        let nested = Editor("- first\n‸")
        nested.type("  * second")
        #expect(nested.state == "- first\n  * second‸")

        let arithmetic = Editor()
        arithmetic.type("2 * 3")
        #expect(arithmetic.state == "2 * 3‸")
    }

    @Test func deletingIntoAnEmptyPairRemovesBoth() {
        let parens = Editor()
        parens.type("(")
        parens.deleteBackward()
        #expect(parens.state == "‸")

        let bold = Editor()
        bold.type("**")
        bold.deleteBackward()
        #expect(bold.state == "*‸*")
        bold.deleteBackward()
        #expect(bold.state == "‸")
    }

    @Test func deletingWhatWasTypedInsideKeepsThePairUntilItIsEmpty() {
        let editor = Editor()
        editor.type("(a")
        editor.deleteBackward()
        #expect(editor.state == "(‸)")
        editor.deleteBackward()
        #expect(editor.state == "‸")
    }

    @Test func typingOverASelectionWrapsIt() {
        let bold = Editor("«word»")
        bold.type("*")
        #expect(bold.state == "*«word»*")
        bold.type("*")
        #expect(bold.state == "**«word»**")

        let link = Editor("see «this» page")
        link.type("[")
        #expect(link.state == "see [«this»] page")
    }

    /// Typed right before a word, the character is marking it by hand.
    @Test(arguments: ["(", "[", "\"", "*", "_", "`"])
    func nothingPairsRightBeforeAWord(opener: String) {
        let editor = Editor("‸word")
        editor.type(opener)
        #expect(editor.state == opener + "‸word")
    }

    /// After a letter or a digit, a quote or a marker closes something.
    @Test func quotesAndMarkersAfterAWordCloseRatherThanOpen() {
        let snake = Editor()
        snake.type("snake_case")
        #expect(snake.state == "snake_case‸")

        let inches = Editor()
        inches.type("5\"")
        #expect(inches.state == "5\"‸")

        let italic = Editor("*word‸")
        italic.type("*")
        #expect(italic.state == "*word*‸")
    }

    @Test func bracketsStillPairAfterAWord() {
        let editor = Editor()
        editor.type("f(")
        #expect(editor.state == "f(‸)")
    }

    @Test func anEscapedCharacterDoesNotPair() {
        let editor = Editor()
        editor.type("\\*")
        #expect(editor.state == "\\*‸")
    }

    /// In code, Markdown's markers are plain characters; brackets still pair.
    @Test func codeBlocksPairBracketsButNotMarkers() {
        let editor = Editor("```\n‸\n```")
        editor.type("*")
        #expect(editor.state == "```\n*‸\n```")
        editor.type("(")
        #expect(editor.state == "```\n*(‸)\n```")
    }

    @Test func inlineCodeClosesWithoutPairingInside() {
        let editor = Editor()
        editor.type("`")
        editor.type("a*b")
        #expect(editor.state == "`a*b‸`")
        editor.type("`")
        #expect(editor.state == "`a*b`‸")
    }

    /// Only a closing character the editor typed is stepped over.
    @Test func aClosingCharacterTypedByHandIsKept() {
        let editor = Editor("(a‸)")
        editor.type(")")
        #expect(editor.state == "(a)‸)")
    }

    @Test func leavingAPairMakesItTheWritersOwn() {
        let editor = Editor()
        editor.type("(")
        editor.moveCaret(to: 0)
        editor.moveCaret(to: 1)
        editor.type(")")
        #expect(editor.state == "()‸)")
    }

    /// On a Brazilian keyboard the backtick is a dead key: it arrives
    /// composed, and still opens and closes inline code.
    @Test func aBacktickFromADeadKeyPairsAndCloses() {
        let editor = Editor()
        editor.typeWithDeadKey("`")
        #expect(editor.state == "`‸`")
        editor.type("code")
        editor.typeWithDeadKey("`")
        #expect(editor.state == "`code`‸")
    }

    /// ⌘Z takes back what was typed inside the pair, then the pair with the
    /// space before it, as it takes back a word: the caret stepping back
    /// between the two starts a new undo step.
    @Test func undoTakesBackWhatWasTypedInsideThenThePair() {
        let editor = Editor()
        editor.type("a (b)")
        #expect(editor.state == "a (b)‸")

        editor.coordinator.textUndoManager.undo()
        #expect(editor.textView.string == "a ()")
        editor.coordinator.textUndoManager.undo()
        #expect(editor.textView.string == "a")
        editor.coordinator.textUndoManager.undo()
        #expect(editor.textView.string == "")
    }

    @Test func afterUndoNothingIsSteppedOver() {
        let editor = Editor()
        editor.type("x (")
        editor.coordinator.textUndoManager.undo()
        editor.coordinator.textUndoManager.redo()
        #expect(editor.textView.string == "x ()")
        editor.moveCaret(to: 3)
        editor.type(")")
        #expect(editor.state == "x ()‸)")
    }

    @Test func arrowsStillReplaceTheirPair() {
        let editor = Editor()
        editor.type("a -> b")
        #expect(editor.state == "a → b‸")
    }
}

struct OpenPairsTests {
    @Test func aPairMovesWithTextTypedBeforeAndInsideIt() {
        var pairs = OpenPairs()
        pairs.opened(at: 4)
        pairs.textWillChange(in: NSRange(location: 5, length: 0), replacementLength: 3)
        #expect(pairs.innermost == .init(opener: 4, closer: 8))
        pairs.textWillChange(in: NSRange(location: 0, length: 0), replacementLength: 2)
        #expect(pairs.innermost == .init(opener: 6, closer: 10))
    }

    @Test func textAfterAPairLeavesItWhereItIs() {
        var pairs = OpenPairs()
        pairs.opened(at: 4)
        pairs.textWillChange(in: NSRange(location: 6, length: 0), replacementLength: 3)
        #expect(pairs.innermost == .init(opener: 4, closer: 5))
    }

    @Test(arguments: [NSRange(location: 4, length: 1), NSRange(location: 5, length: 1), NSRange(location: 2, length: 6)])
    func anEditTakingEitherCharacterEndsThePair(range: NSRange) {
        var pairs = OpenPairs()
        pairs.opened(at: 4)
        pairs.textWillChange(in: range, replacementLength: 0)
        #expect(pairs.innermost == nil)
    }

    @Test func aCaretOutsideThePairEndsIt() {
        var pairs = OpenPairs()
        pairs.opened(at: 4)
        pairs.selectionDidChange(to: NSRange(location: 5, length: 0))
        #expect(pairs.innermost != nil)
        pairs.selectionDidChange(to: NSRange(location: 4, length: 0))
        #expect(pairs.innermost == nil)

        pairs.opened(at: 4)
        pairs.selectionDidChange(to: NSRange(location: 6, length: 0))
        #expect(pairs.innermost == nil)
    }

    @Test func leavingAnInnerPairKeepsTheOuterOne() {
        var pairs = OpenPairs()
        pairs.opened(at: 0)
        pairs.textWillChange(in: NSRange(location: 1, length: 0), replacementLength: 2)
        pairs.opened(at: 1)
        #expect(pairs.innermost == .init(opener: 1, closer: 2))
        pairs.selectionDidChange(to: NSRange(location: 3, length: 0))
        #expect(pairs.innermost == .init(opener: 0, closer: 3))
    }
}
