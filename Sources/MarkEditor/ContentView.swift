import SwiftUI

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

struct ViewModeCommands: Commands {
    @FocusedBinding(\.viewMode) private var viewMode: ViewMode?

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Somente Editor") { viewMode = .editorOnly }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(viewMode == nil)
            Button("Editor e Visualização") { viewMode = .split }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(viewMode == nil)
            Button("Somente Visualização") { viewMode = .previewOnly }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(viewMode == nil)
            Divider()
        }
    }
}

struct ContentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    @SceneStorage("viewMode") private var viewMode: ViewMode = .split
    @SceneStorage("splitFraction") private var splitFraction: Double = 0.5
    @State private var editorScrollFraction: CGFloat = 0

    private static let minPaneWidth: CGFloat = 280

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            HStack(spacing: 0) {
                if viewMode != .previewOnly {
                    MarkdownTextView(text: $document.text, scrollFraction: $editorScrollFraction)
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
                        markdown: document.text,
                        baseURL: fileURL?.deletingLastPathComponent(),
                        scrollFraction: editorScrollFraction
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .coordinateSpace(name: "split")
        .frame(minWidth: 700, minHeight: 440)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            statusBar
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Modo de exibição", selection: $viewMode) {
                    Label("Somente editor", systemImage: "doc.plaintext")
                        .tag(ViewMode.editorOnly)
                    Label("Editor e visualização", systemImage: "rectangle.split.2x1")
                        .tag(ViewMode.split)
                    Label("Somente visualização", systemImage: "doc.richtext")
                        .tag(ViewMode.previewOnly)
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
            }
        }
        .focusedSceneValue(\.viewMode, $viewMode)
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            Text("\(wordCount) palavras")
            Text("\(document.text.count) caracteres")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var wordCount: Int {
        document.text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count
    }

    /// Display width of the editor pane: the stored fraction, clamped so both
    /// panes keep a usable width when the window shrinks (the stored value is
    /// untouched, so enlarging the window restores the user's position).
    private func editorWidth(in totalWidth: CGFloat) -> CGFloat {
        (totalWidth - SplitDivider.thickness)
            * SplitDivider.clamp(splitFraction, totalWidth: totalWidth, minPaneWidth: Self.minPaneWidth)
    }
}

/// Draggable pane divider. The stored fraction survives view-mode switches
/// (⌘1/⌘2/⌘3), so split view always comes back where the user left it.
struct SplitDivider: View {
    @Binding var fraction: Double
    let totalWidth: CGFloat
    let minPaneWidth: CGFloat

    static let thickness: CGFloat = 1
    private static let hitAreaWidth: CGFloat = 11

    static func clamp(_ fraction: Double, totalWidth: CGFloat, minPaneWidth: CGFloat) -> Double {
        guard totalWidth > minPaneWidth * 2 else { return 0.5 }
        let minFraction = minPaneWidth / totalWidth
        return min(max(fraction, minFraction), 1 - minFraction)
    }

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: Self.thickness)
            .frame(maxHeight: .infinity)
            .overlay {
                Color.clear
                    .frame(width: Self.hitAreaWidth)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("split"))
                            .onChanged { value in
                                fraction = Self.clamp(
                                    value.location.x / totalWidth,
                                    totalWidth: totalWidth,
                                    minPaneWidth: minPaneWidth
                                )
                            }
                    )
            }
    }
}
