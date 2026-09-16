import SwiftUI

/// The editor and the preview side by side, with the draggable divider: the
/// part of a window that shows one piece of markdown. A document window owns
/// one of these; a folder window owns one per tab.
struct EditorPanes: View {
    @Binding var text: String
    /// Where the text came from, so relative images resolve.
    let fileURL: URL?
    let viewMode: ViewMode
    @Binding var splitFraction: Double
    @Binding var scrollSync: ScrollSync
    let editorActions: EditorActions
    let previewActions: PreviewActions
    let previewWidth: PreviewWidth
    /// False while a pane shows text it has no way to save yet.
    var isEditable: Bool = true

    private static let minPaneWidth: CGFloat = 280

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            HStack(spacing: 0) {
                if viewMode != .previewOnly {
                    MarkdownTextView(
                        text: $text,
                        scrollSync: $scrollSync,
                        actions: editorActions,
                        fileURL: fileURL,
                        isEditable: isEditable
                    )
                        .frame(width: viewMode == .split ? editorWidth(in: totalWidth) : totalWidth)
                }
                if viewMode == .split {
                    SplitDivider(
                        fraction: $splitFraction,
                        totalWidth: totalWidth,
                        minPaneWidth: Self.minPaneWidth
                    )
                }
                if viewMode != .editorOnly {
                    PreviewWebView(
                        markdown: text,
                        baseURL: fileURL?.deletingLastPathComponent(),
                        scrollSync: $scrollSync,
                        contentWidthRem: previewWidth.rem,
                        actions: previewActions
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .coordinateSpace(name: "split")
    }

    /// Display width of the editor pane: the stored fraction, clamped so both
    /// panes keep a usable width when the window shrinks (the stored value is
    /// untouched, so enlarging the window restores the user's position).
    private func editorWidth(in totalWidth: CGFloat) -> CGFloat {
        (totalWidth - SplitDivider.thickness)
            * SplitDivider.clamp(splitFraction, totalWidth: totalWidth, minPaneWidth: Self.minPaneWidth)
    }
}
