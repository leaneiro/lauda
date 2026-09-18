import SwiftUI

/// The editor and the preview side by side, with the draggable divider: the
/// part of the window that shows one document's markdown. Every open
/// document has its own.
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
    /// False for a document behind another tab: nobody sees its panes
    /// change, so they change at once.
    var animatesModeChanges = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The mode the panes are in now, which the mode they are asked for is
    /// compared with to know what kind of change is coming.
    @State private var shownMode: ViewMode?

    private static let minPaneWidth: CGFloat = 280

    /// A change of view mode: the pane that stays takes its new width over
    /// a moment, and the one that comes or goes slides with it from its own
    /// side, the way a split view's pane does. Quick on purpose; it only
    /// takes the edge off the jump.
    private var modeChange: Animation? {
        guard animatesModeChanges, !reduceMotion,
              ModeChange.isSmooth(from: shownMode, to: viewMode, textBytes: text.utf8.count)
        else { return nil }
        return .easeInOut(duration: 0.2)
    }

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            HStack(spacing: 0) {
                if viewMode != .previewOnly {
                    MarkdownTextView(
                        text: $text,
                        scrollSync: $scrollSync,
                        actions: editorActions,
                        fileURL: fileURL
                    )
                        .frame(width: viewMode == .split ? editorWidth(in: totalWidth) : totalWidth)
                        .transition(.move(edge: .leading))
                }
                if viewMode == .split {
                    SplitDivider(
                        fraction: $splitFraction,
                        totalWidth: totalWidth,
                        minPaneWidth: Self.minPaneWidth
                    )
                    .transition(.opacity)
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
                    .transition(.move(edge: .trailing))
                }
            }
            .animation(modeChange, value: viewMode)
        }
        .onChange(of: viewMode, initial: true) {
            shownMode = viewMode
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

/// Which changes of view mode can animate without stuttering.
enum ModeChange {
    /// Between editor only and both panes the editor changes width, and its
    /// text wraps anew on every frame of the way. Measured: smooth up to
    /// some 40 KB, a handful of frames from 60 KB on. The preview lays out
    /// off the main thread and keeps up whatever the size, and a pane that
    /// only comes or goes doesn't wrap again at all.
    static let longestTextRewrappedSmoothly = 50_000

    static func isSmooth(from shown: ViewMode?, to asked: ViewMode, textBytes: Int) -> Bool {
        guard let shown, textBytes > longestTextRewrappedSmoothly else { return true }
        return Set([shown, asked]) != [.editorOnly, .split]
    }
}
