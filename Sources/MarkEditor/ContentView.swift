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

/// Bridges menu commands to the focused window's editor coordinator.
final class EditorActions {
    weak var coordinator: MarkdownTextView.Coordinator?

    func toggleBold() { coordinator?.toggleInlineMarker("**") }
    func toggleItalic() { coordinator?.toggleInlineMarker("*") }
    func insertLink() { coordinator?.insertLink() }
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

struct FormatCommands: Commands {
    @FocusedValue(\.editorActions) private var editorActions

    var body: some Commands {
        CommandMenu("Formatar") {
            Button("Negrito") { editorActions?.toggleBold() }
                .keyboardShortcut("b")
                .disabled(editorActions == nil)
            Button("Itálico") { editorActions?.toggleItalic() }
                .keyboardShortcut("i")
                .disabled(editorActions == nil)
            Divider()
            Button("Adicionar Link") { editorActions?.insertLink() }
                .keyboardShortcut("k")
                .disabled(editorActions == nil)
        }
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

/// Shared scroll position between the panes. `source` marks which pane the
/// user scrolled, so the other pane follows and echoes are ignored.
struct ScrollSync: Equatable {
    enum Source { case editor, preview }
    var fraction: CGFloat = 0
    var source: Source = .editor
}

struct ContentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    @SceneStorage("viewMode") private var viewMode: ViewMode = .split
    @SceneStorage("splitFraction") private var splitFraction: Double = 0.5
    @State private var scrollSync = ScrollSync()
    @State private var editorActions = EditorActions()
    @State private var lastSavedText: String?
    @State private var lastSaveDate: Date?

    private static let minPaneWidth: CGFloat = 280

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            HStack(spacing: 0) {
                if viewMode != .previewOnly {
                    MarkdownTextView(text: $document.text, scrollSync: $scrollSync, actions: editorActions)
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
                        scrollSync: $scrollSync
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
        .focusedSceneValue(\.editorActions, editorActions)
        .onAppear {
            if fileURL != nil {
                lastSavedText = document.text
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .markdownDocumentDidSave)
                .receive(on: RunLoop.main)
        ) { notification in
            guard let savedText = notification.userInfo?["text"] as? String,
                  savedText == document.text else { return }
            lastSavedText = savedText
            lastSaveDate = Date()
        }
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            Text("\(wordCount) palavras")
            Text("\(document.text.count) caracteres")
            Spacer()
            saveStatusView
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

    private var saveStatusView: some View {
        let status = saveStatus
        return HStack(spacing: 5) {
            Image(systemName: status.icon)
                .foregroundStyle(status.color)
            Text(status.label)
        }
        .help("O macOS salva automaticamente; ⌘S salva na hora.")
    }

    private var saveStatus: (icon: String, label: String, color: Color) {
        if fileURL == nil && lastSavedText == nil {
            return ("circle.dotted", "Não salvo ainda", .secondary)
        }
        if document.text == lastSavedText {
            if let date = lastSaveDate {
                let time = date.formatted(date: .omitted, time: .shortened)
                return ("checkmark.circle.fill", "Salvo · \(time)", .green)
            }
            return ("checkmark.circle.fill", "Salvo", .green)
        }
        return ("ellipsis.circle.fill", "Editando…", .orange)
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
