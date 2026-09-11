import SwiftUI
import AppKit

enum ViewMode: Int {
    case editorOnly
    case split
    case previewOnly
}

struct ViewModeKey: FocusedValueKey {
    typealias Value = Binding<ViewMode>
}

extension FocusedValues {
    var viewMode: Binding<ViewMode>? {
        get { self[ViewModeKey.self] }
        set { self[ViewModeKey.self] = newValue }
    }
}

/// Bridges menu commands to the focused window's editor coordinator.
final class EditorActions {
    weak var coordinator: MarkdownTextView.Coordinator?

    func toggleBold() { coordinator?.toggleInlineMarker("**") }
    func toggleItalic() { coordinator?.toggleInlineMarker("*") }
    func insertLink() { coordinator?.insertLink() }
    func performFind(_ action: NSTextFinder.Action) { coordinator?.performFindAction(action) }
    func findUpdate(_ query: String) -> (current: Int, total: Int) {
        coordinator?.findUpdate(query) ?? (0, 0)
    }
    func findStep(forward: Bool) -> (current: Int, total: Int) {
        coordinator?.findStep(forward: forward) ?? (0, 0)
    }
    func findClear() { coordinator?.findClear() }
    func placeCaret(atSourceLine line: Int) { coordinator?.placeCaret(atSourceLine: line) }
}

struct EditorActionsKey: FocusedValueKey {
    typealias Value = EditorActions
}

extension FocusedValues {
    var editorActions: EditorActions? {
        get { self[EditorActionsKey.self] }
        set { self[EditorActionsKey.self] = newValue }
    }
}

/// Bridges the find bar to the focused window's preview coordinator.
final class PreviewActions {
    weak var coordinator: PreviewWebView.Coordinator?

    func find(_ query: String, forward: Bool, restart: Bool, completion: @escaping (Int, Int) -> Void) {
        if let coordinator {
            coordinator.find(query, forward: forward, restart: restart, completion: completion)
        } else {
            completion(0, 0)
        }
    }

    func clearFind() { coordinator?.clearFind() }
}

/// Find commands routed per view mode: editor find bar when the editor is
/// visible; a floating find bar over the preview in preview-only mode.
struct FindActions {
    var find: () -> Void
    var findNext: () -> Void
    var findPrevious: () -> Void
    var replace: () -> Void
}

struct FindActionsKey: FocusedValueKey {
    typealias Value = FindActions
}

extension FocusedValues {
    var findActions: FindActions? {
        get { self[FindActionsKey.self] }
        set { self[FindActionsKey.self] = newValue }
    }
}

/// Export commands routed to the focused window's document.
struct ExportActions {
    var exportHTML: () -> Void
    var exportPDF: () -> Void
}

struct ExportActionsKey: FocusedValueKey {
    typealias Value = ExportActions
}

extension FocusedValues {
    var exportActions: ExportActions? {
        get { self[ExportActionsKey.self] }
        set { self[ExportActionsKey.self] = newValue }
    }
}
