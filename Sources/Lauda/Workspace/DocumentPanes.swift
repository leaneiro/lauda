import AppKit
import SwiftUI

/// One document's part of the window: its editor and preview, the find bar
/// over them and the status bar under them. Each open document has its own,
/// so what a pane holds (the scroll position, the caret, undo, a search)
/// stays with its document while another tab is in front.
struct DocumentPanes: View {
    @Bindable var document: MarkdownDocument
    let workspace: Workspace

    @AppStorage(AppSettings.previewWidthLevel) private var previewWidthLevel: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        EditorPanes(
            text: Binding(get: { document.text }, set: { document.edit($0) }),
            fileURL: document.fileURL,
            viewMode: workspace.viewMode,
            splitFraction: Binding(get: { workspace.splitFraction }, set: { workspace.splitFraction = $0 }),
            scrollSync: $document.scrollSync,
            scrollsLinked: $document.scrollsLinked,
            editorScrollable: $document.editorScrollable,
            previewScrollable: $document.previewScrollable,
            panesScroll: document.panesScroll,
            editorActions: document.editorActions,
            previewActions: document.previewActions,
            previewWidth: PreviewWidth.showing(level: previewWidthLevel, in: workspace.viewMode),
            isEditable: !document.isInTrash,
            animatesModeChanges: workspace.selected === document
        )
        .overlay(alignment: .topTrailing) {
            DocumentFindBar(session: document.findSession, mode: workspace.viewMode)
        }
        // Over the find bar too: in the Trash, nothing in the panes answers.
        .overlay {
            if document.isInTrash {
                TrashNotice(fileURL: document.fileURL)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: ModeChange.duration), value: document.isInTrash)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusBar(
                text: document.text,
                fileURL: document.fileURL,
                // A document that has no file yet was never saved, whatever
                // text it started with (the welcome guide starts with some).
                lastSavedText: document.fileURL == nil ? nil : document.savedText,
                lastSaveDate: document.savedDate
            )
        }
        .onChange(of: workspace.viewMode) {
            document.findSession.modeChanged(to: workspace.viewMode)
        }
        .onChange(of: document.isInTrash) { _, isInTrash in
            keyboardFollowsTrash(isInTrash)
        }
    }

    /// In the Trash the panes let go of the keyboard, the preview's as well
    /// as the editor's. Put back, the document in front takes it again,
    /// unless something else has taken it in the meantime.
    private func keyboardFollowsTrash(_ isInTrash: Bool) {
        if isInTrash {
            // An open find bar goes too, ours or the editor's own for
            // replacing: its field would keep the keyboard.
            document.findSession.close()
            document.editorActions.hideFindBar()
        }
        guard let window = workspace.window, let panes = workspace.stack.panes(of: document) else { return }
        if isInTrash {
            if let responder = window.firstResponder as? NSView, responder.isDescendant(of: panes) {
                window.makeFirstResponder(nil)
            }
        } else if workspace.selected === document, window.firstResponder === window {
            _ = document.takeKeyboard(in: workspace.viewMode)
        }
    }
}

private struct DocumentFindBar: View {
    @Bindable var session: FindSession
    let mode: ViewMode

    var body: some View {
        if session.isPresented {
            FindBar(
                query: $session.query,
                current: session.current,
                total: session.total,
                onQueryChanged: { session.search(in: mode) },
                onNext: { session.step(forward: true, in: mode) },
                onPrevious: { session.step(forward: false, in: mode) },
                onClose: session.close
            )
        }
    }
}
