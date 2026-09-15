import SwiftUI

/// A document window's toolbar: the view mode picker, the outline and, in
/// preview-only mode, the text width button.
struct DocumentToolbar: ToolbarContent {
    @Binding var viewMode: ViewMode
    @Binding var outlinePresented: Bool
    /// The document's text; headings are only read when the outline opens.
    let text: String
    let previewWidth: PreviewWidth
    let onSelectHeading: (OutlineItem) -> Void
    let onCycleWidth: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
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
        ToolbarItem(placement: .automatic) {
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
        ToolbarItem(placement: .automatic) {
            if viewMode == .previewOnly {
                Button(action: onCycleWidth) {
                    WidthLevelIcon(level: previewWidth)
                }
                .help("Text width: \(previewWidth.label). Next: \(previewWidth.next.label)")
                .accessibilityLabel("Text width: \(previewWidth.label)")
            }
        }
    }
}
