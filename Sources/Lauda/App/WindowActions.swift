import SwiftUI
import AppKit

enum ViewMode: Int {
    case editorOnly
    case split
    case previewOnly
}

/// Bridges menu commands and the find bar to a document's editor pane.
final class EditorActions: EditorFinding {
    weak var coordinator: MarkdownTextView.Coordinator?

    func toggleBold() { coordinator?.toggleInlineMarker("**") }
    func toggleItalic() { coordinator?.toggleInlineMarker("*") }
    func insertLink() { coordinator?.insertLink() }
    func performFind(_ action: NSTextFinder.Action) { coordinator?.performFindAction(action) }
    func findUpdate(_ query: String) -> (current: Int, total: Int) {
        coordinator?.find.update(query) ?? (0, 0)
    }
    func findStep(forward: Bool) -> (current: Int, total: Int) {
        coordinator?.find.step(forward: forward) ?? (0, 0)
    }
    func findClear() { coordinator?.find.clear() }
    func setFindCountsHandler(_ handler: @escaping (Int, Int) -> Void) {
        coordinator?.find.countsChanged = handler
    }
    func placeCaret(atSourceLine line: Int) { coordinator?.placeCaret(atSourceLine: line) }
    /// False while there is no editor pane to take the keyboard.
    func focus() -> Bool { coordinator?.focus() ?? false }
}

/// Bridges the find bar to a document's preview pane.
final class PreviewActions: PreviewFinding {
    weak var coordinator: PreviewWebView.Coordinator?

    func find(_ query: String, forward: Bool, restart: Bool, completion: @escaping (Int, Int) -> Void) {
        if let coordinator {
            coordinator.find(query, forward: forward, restart: restart, completion: completion)
        } else {
            completion(0, 0)
        }
    }

    func clearFind() { coordinator?.clearFind() }
    /// False while there is no preview pane to take the keyboard.
    func focus() -> Bool { coordinator?.focus() ?? false }
}

/// What exporting a document offers.
struct ExportActions {
    var exportHTML: () -> Void
    var exportPDF: () -> Void
}
