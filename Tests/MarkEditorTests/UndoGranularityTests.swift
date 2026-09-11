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
        type("ola mundo", into: textView)
        XCTAssertEqual(textView.string, "ola mundo")

        coordinator.textUndoManager.undo()
        XCTAssertEqual(textView.string, "ola", "primeiro ⌘Z remove só a última palavra")

        coordinator.textUndoManager.undo()
        XCTAssertEqual(textView.string, "")
    }

    func testRedoRestoresWordByWord() {
        let (textView, coordinator) = makeEditor()
        type("um dois tres", into: textView)

        coordinator.textUndoManager.undo()
        coordinator.textUndoManager.undo()
        XCTAssertEqual(textView.string, "um")

        XCTAssertTrue(coordinator.textUndoManager.canRedo)
        coordinator.textUndoManager.redo()
        XCTAssertEqual(textView.string, "um dois")
        coordinator.textUndoManager.redo()
        XCTAssertEqual(textView.string, "um dois tres")
    }

    func testFormattingActionIsItsOwnUndoStep() {
        let (textView, coordinator) = makeEditor()
        type("palavra", into: textView)

        textView.setSelectedRange(NSRange(location: 0, length: 7))
        coordinator.toggleInlineMarker("**")
        XCTAssertEqual(textView.string, "**palavra**")

        coordinator.textUndoManager.undo()
        XCTAssertEqual(textView.string, "palavra", "⌘Z undoes only the bold, not the typing")
    }
}
