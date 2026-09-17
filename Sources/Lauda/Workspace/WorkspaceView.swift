import SwiftUI

/// What the workspace window shows: the open documents' panes, the selected
/// one's in front, and the toolbar.
struct WorkspaceView: View {
    let workspace: Workspace

    @AppStorage(AppSettings.previewWidthLevel) private var previewWidthLevel: Int
    @State private var outlinePresented = false
    /// How wide the window is, which decides how much room the tabs get.
    @State private var windowWidth: CGFloat = 1200

    private var viewMode: Binding<ViewMode> {
        Binding(get: { workspace.viewMode }, set: { workspace.viewMode = $0 })
    }

    private var effectivePreviewWidth: PreviewWidth {
        .showing(level: previewWidthLevel, in: workspace.viewMode)
    }

    var body: some View {
        DocumentStack(documents: workspace.documents, selected: workspace.selected, workspace: workspace)
            .frame(minWidth: 700, minHeight: 440)
            .background(GeometryReader { proxy in
                Color.clear.onChange(of: proxy.size.width, initial: true) { _, width in
                    windowWidth = width
                }
            })
            .toolbar {
                DocumentToolbar(
                    workspace: workspace,
                    viewMode: viewMode,
                    outlinePresented: $outlinePresented,
                    text: workspace.selected?.text ?? "",
                    previewWidth: effectivePreviewWidth,
                    onSelectHeading: navigate(to:),
                    onCycleWidth: { previewWidthLevel = effectivePreviewWidth.next.rawValue },
                    tabStripWidth: WorkspaceTabStrip.width(
                        in: windowWidth,
                        showsWidthButton: workspace.viewMode == .previewOnly
                    )
                )
            }
    }

    private func navigate(to item: OutlineItem) {
        outlinePresented = false
        guard let document = workspace.selected else { return }
        let jump = OutlineJump(to: item, in: document.text, mode: workspace.viewMode)
        document.scrollSync = jump.scrollSync
        if let line = jump.caretLine {
            document.editorActions.placeCaret(atSourceLine: line)
        }
    }
}
