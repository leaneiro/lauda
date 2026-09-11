import XCTest
import SwiftUI
@testable import MarkEditor

/// Exercises the real Coordinator + NSTextView undo pipeline: typing goes
/// through insertText (delegate callbacks included) with a runloop turn per
/// keystroke, mirroring real events.
@MainActor
final class UndoGranularityTests: XCTestCase {
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

    func testUndoStepsBackWordByWord() {
        let (textView, coordinator) = makeEditor()
        type("hello world", into: textView)
        XCTAssertEqual(textView.string, "hello world")

        coordinator.textUndoManager.undo()
        XCTAssertEqual(textView.string, "hello", "the first ⌘Z removes only the last word")

        coordinator.textUndoManager.undo()
        XCTAssertEqual(textView.string, "")
    }

    func testRedoRestoresWordByWord() {
        let (textView, coordinator) = makeEditor()
        type("one two three", into: textView)

        coordinator.textUndoManager.undo()
        coordinator.textUndoManager.undo()
        XCTAssertEqual(textView.string, "one")

        XCTAssertTrue(coordinator.textUndoManager.canRedo)
        coordinator.textUndoManager.redo()
        XCTAssertEqual(textView.string, "one two")
        coordinator.textUndoManager.redo()
        XCTAssertEqual(textView.string, "one two three")
    }

    func testFormattingActionIsItsOwnUndoStep() {
        let (textView, coordinator) = makeEditor()
        type("writing", into: textView)

        textView.setSelectedRange(NSRange(location: 0, length: 7))
        coordinator.toggleInlineMarker("**")
        XCTAssertEqual(textView.string, "**writing**")

        coordinator.textUndoManager.undo()
        XCTAssertEqual(textView.string, "writing", "⌘Z undoes only the bold, not the typing")
    }
}
