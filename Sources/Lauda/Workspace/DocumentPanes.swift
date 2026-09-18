import SwiftUI

/// One document's part of the window: its editor and preview, the find bar
/// over them and the status bar under them. Each open document has its own,
/// so what a pane holds (the scroll position, the caret, undo, a search)
/// stays with its document while another tab is in front.
struct DocumentPanes: View {
    @Bindable var document: MarkdownDocument
    let workspace: Workspace

    @AppStorage(AppSettings.previewWidthLevel) private var previewWidthLevel: Int

    var body: some View {
        EditorPanes(
            text: Binding(get: { document.text }, set: { document.edit($0) }),
            fileURL: document.fileURL,
            viewMode: workspace.viewMode,
            splitFraction: Binding(get: { workspace.splitFraction }, set: { workspace.splitFraction = $0 }),
            scrollSync: $document.scrollSync,
            editorActions: document.editorActions,
            previewActions: document.previewActions,
            previewWidth: PreviewWidth.showing(level: previewWidthLevel, in: workspace.viewMode),
            animatesModeChanges: workspace.selected === document
        )
        .overlay(alignment: .topTrailing) {
            DocumentFindBar(session: document.findSession, mode: workspace.viewMode)
        }
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
