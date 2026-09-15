import AppKit
import Observation

/// What the find bar needs from the editor pane.
protocol EditorFinding: AnyObject {
    func findUpdate(_ query: String) -> (current: Int, total: Int)
    func findStep(forward: Bool) -> (current: Int, total: Int)
    func findClear()
    func performFind(_ action: NSTextFinder.Action)
    /// Receives new counts later, when edits change the matches.
    func setFindCountsHandler(_ handler: @escaping (Int, Int) -> Void)
}

/// What the find bar needs from the preview pane.
protocol PreviewFinding: AnyObject {
    func find(_ query: String, forward: Bool, restart: Bool, completion: @escaping (Int, Int) -> Void)
    func clearFind()
}

/// A window's floating find bar: its query, the match counts and which pane
/// answers. The editor searches whenever it's visible; in preview-only mode
/// the preview does.
@Observable
final class FindSession {
    var isPresented = false
    var query = ""
    private(set) var current = 0
    private(set) var total = 0

    private let editor: EditorFinding
    private let preview: PreviewFinding

    init(editor: EditorFinding, preview: PreviewFinding) {
        self.editor = editor
        self.preview = preview
    }

    /// Shows the bar, searching again for a query that's already typed.
    func open(in mode: ViewMode) {
        isPresented = true
        editor.setFindCountsHandler { [weak self] current, total in
            DispatchQueue.main.async {
                self?.show(current: current, total: total)
            }
        }
        if !query.isEmpty {
            search(in: mode)
        }
    }

    /// Searches for the query from the top of the document.
    func search(in mode: ViewMode) {
        guard isPresented else { return }
        guard !query.isEmpty else {
            show(current: 0, total: 0)
            editor.findClear()
            preview.clearFind()
            return
        }
        if mode == .previewOnly {
            preview.find(query, forward: true, restart: true) { [weak self] current, total in
                self?.show(current: current, total: total)
            }
        } else {
            let counts = editor.findUpdate(query)
            show(current: counts.current, total: counts.total)
        }
    }

    /// The next or previous match; opens the bar when there's nothing to step through.
    func step(forward: Bool, in mode: ViewMode) {
        guard isPresented, !query.isEmpty else {
            open(in: mode)
            return
        }
        if mode == .previewOnly {
            preview.find(query, forward: forward, restart: false) { [weak self] current, total in
                self?.show(current: current, total: total)
            }
        } else {
            let counts = editor.findStep(forward: forward)
            show(current: counts.current, total: counts.total)
        }
    }

    /// The editor's own find-and-replace bar. The preview can't replace, so
    /// in preview-only mode this opens the find bar instead.
    func replace(in mode: ViewMode) {
        if mode == .previewOnly {
            open(in: mode)
        } else {
            close()
            editor.performFind(.showReplaceInterface)
        }
    }

    func close() {
        isPresented = false
        show(current: 0, total: 0)
        editor.findClear()
        preview.clearFind()
    }

    /// Switching modes recreates the panes, so an open search starts over in
    /// the new ones.
    func modeChanged(to mode: ViewMode) {
        guard isPresented else { return }
        editor.findClear()
        preview.clearFind()
        DispatchQueue.main.async { [weak self] in
            self?.search(in: mode)
        }
    }

    private func show(current: Int, total: Int) {
        self.current = current
        self.total = total
    }
}
