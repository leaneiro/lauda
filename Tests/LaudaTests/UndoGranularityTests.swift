import AppKit
import SwiftUI
import Testing
@testable import Lauda

/// Exercises the real Coordinator + NSTextView undo pipeline: typing goes
/// through insertText (delegate callbacks included) with a runloop turn per
/// keystroke, mirroring real events. Serialized because pumping the runloop
/// lets other main-actor work in, and NSTextView coalesces undo by timing.
@MainActor
@Suite(.serialized)
struct UndoGranularityTests {
    private func makeEditor() -> (NSTextView, MarkdownTextView.Coordinator) {
        let view = MarkdownTextView(
            text: .constant(""),
            scrollSync: .constant(ScrollSync()),
            actions: EditorActions(),
            fileURL: nil
        )
        let coordinator = view.makeCoordinator()
        let textView = NSTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.delegate = coordinator
        coordinator.textView = textView
        return (textView, coordinator)
    }

    private func type(_ text: String, into textView: NSTextView) {
        for character in text {
            textView.insertText(String(character), replacementRange: textView.selectedRange())
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
    }

    @Test func undoStepsBackWordByWord() {
        let (textView, coordinator) = makeEditor()
        type("hello world", into: textView)
        #expect(textView.string == "hello world")

        coordinator.textUndoManager.undo()
        #expect(textView.string == "hello", "the first ⌘Z removes only the last word")

        coordinator.textUndoManager.undo()
        #expect(textView.string == "")
    }

    @Test func redoRestoresWordByWord() {
        let (textView, coordinator) = makeEditor()
        type("one two three", into: textView)

        coordinator.textUndoManager.undo()
        coordinator.textUndoManager.undo()
        #expect(textView.string == "one")

        #expect(coordinator.textUndoManager.canRedo)
        coordinator.textUndoManager.redo()
        #expect(textView.string == "one two")
        coordinator.textUndoManager.redo()
        #expect(textView.string == "one two three")
    }

    @Test func formattingActionIsItsOwnUndoStep() {
        let (textView, coordinator) = makeEditor()
        type("writing", into: textView)

        textView.setSelectedRange(NSRange(location: 0, length: 7))
        coordinator.toggleInlineMarker("**")
        #expect(textView.string == "**writing**")

        coordinator.textUndoManager.undo()
        #expect(textView.string == "writing", "⌘Z undoes only the bold, not the typing")
    }
}
