import SwiftUI

/// The window's toolbar: the view mode picker, the outline and, in
/// preview-only mode, the text width button. With two or more documents
/// open, the tabs take the title's place and the controls line up on the
/// right; a single document keeps the picker in the middle, as always.
struct DocumentToolbar: ToolbarContent {
    let workspace: Workspace
    @Binding var viewMode: ViewMode
    @Binding var outlinePresented: Bool
    /// The document's text; headings are only read when the outline opens.
    let text: String
    let previewWidth: PreviewWidth
    let onSelectHeading: (OutlineItem) -> Void
    let onCycleWidth: () -> Void
    /// Room the title bar has for the tabs, which the window works out.
    let tabStripWidth: CGFloat

    var body: some ToolbarContent {
        if workspace.showsTabs {
            tabsItem
            // primaryAction is the trailing edge on macOS. Left automatic,
            // these pile up right after the tabs once nothing sits in the
            // middle to push them across.
            ToolbarItem(placement: .primaryAction) { viewModePicker }
            ToolbarItem(placement: .primaryAction) { outlineButton }
            ToolbarItem(placement: .primaryAction) { widthButton }
        } else {
            ToolbarItem(placement: .principal) { viewModePicker }
            ToolbarItem(placement: .automatic) { outlineButton }
            ToolbarItem(placement: .automatic) { widthButton }
        }
    }

    /// The strip spans the title bar but must not look like it: recent
    /// systems wrap every toolbar item in one glass capsule, and the tabs
    /// want a capsule each. Hiding the item's own background leaves theirs.
    @ToolbarContentBuilder
    private var tabsItem: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .navigation) {
                WorkspaceTabStrip(workspace: workspace, width: tabStripWidth)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) {
                WorkspaceTabStrip(workspace: workspace, width: tabStripWidth)
            }
        }
    }

    private var viewModePicker: some View {
        Picker("View Mode", selection: $viewMode) {
            Label("Editor Only", systemImage: "doc.plaintext")
                .tag(ViewMode.editorOnly)
            Label("Editor and Preview", systemImage: "rectangle.split.2x1")
                .tag(ViewMode.split)
            Label("Preview Only", systemImage: "doc.richtext")
                .tag(ViewMode.previewOnly)
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
    }

    private var outlineButton: some View {
        Button {
            outlinePresented.toggle()
        } label: {
            Label("Outline", systemImage: "list.bullet")
        }
        .help("Document outline")
        .popover(isPresented: $outlinePresented, arrowEdge: .bottom) {
            OutlinePopover(items: Outline.items(in: text), onSelect: onSelectHeading)
        }
    }

    @ViewBuilder
    private var widthButton: some View {
        if viewMode == .previewOnly {
            Button(action: onCycleWidth) {
                WidthLevelIcon(level: previewWidth)
            }
            .help("Text width: \(previewWidth.label). Next: \(previewWidth.next.label)")
            .accessibilityLabel("Text width: \(previewWidth.label)")
        }
    }
}
