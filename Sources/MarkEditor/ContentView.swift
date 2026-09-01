import SwiftUI
import AppKit

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
    func performFind(_ action: NSTextFinder.Action) { coordinator?.performFindAction(action) }
}

/// Bridges the preview find bar to the focused window's preview coordinator.
final class PreviewActions {
    weak var coordinator: PreviewWebView.Coordinator?

    func find(_ query: String, forward: Bool) { coordinator?.find(query, forward: forward) }
    func clearFindSelection() { coordinator?.clearFindSelection() }
}

/// Find commands routed per view mode: editor find bar when the editor is
/// visible; a floating find bar over the preview in preview-only mode.
struct FindActions {
    var find: () -> Void
    var findNext: () -> Void
    var findPrevious: () -> Void
    var replace: () -> Void
}

struct FindActionsKey: FocusedValueKey {
    typealias Value = FindActions
}

extension FocusedValues {
    var findActions: FindActions? {
        get { self[FindActionsKey.self] }
        set { self[FindActionsKey.self] = newValue }
    }
}

struct FindCommands: Commands {
    @FocusedValue(\.findActions) private var findActions

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Localizar…") { findActions?.find() }
                .keyboardShortcut("f")
                .disabled(findActions == nil)
            Button("Localizar Seguinte") { findActions?.findNext() }
                .keyboardShortcut("g")
                .disabled(findActions == nil)
            Button("Localizar Anterior") { findActions?.findPrevious() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(findActions == nil)
            Button("Localizar e Substituir…") { findActions?.replace() }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(findActions == nil)
        }
    }
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
    @AppStorage(SettingsKeys.previewWidthLevel) private var previewWidthLevel = PreviewWidth.normal.rawValue
    @State private var scrollSync = ScrollSync()
    @State private var editorActions = EditorActions()
    @State private var previewActions = PreviewActions()
    @State private var lastSavedText: String?
    @State private var lastSaveDate: Date?
    @State private var previewFindPresented = false
    @State private var previewFindQuery = ""

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
                    ZStack(alignment: .topTrailing) {
                        PreviewWebView(
                            markdown: document.text,
                            baseURL: fileURL?.deletingLastPathComponent(),
                            scrollSync: $scrollSync,
                            contentWidthRem: effectivePreviewWidth.rem,
                            actions: previewActions
                        )
                        if previewFindPresented && viewMode == .previewOnly {
                            PreviewFindBar(
                                query: $previewFindQuery,
                                onNext: { previewFind(forward: true) },
                                onPrevious: { previewFind(forward: false) },
                                onClose: closePreviewFind
                            )
                        }
                    }
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
            ToolbarItem(placement: .automatic) {
                if viewMode == .previewOnly {
                    Button {
                        previewWidthLevel = effectivePreviewWidth.next.rawValue
                    } label: {
                        Label("Largura do conteúdo", systemImage: effectivePreviewWidth.symbol)
                    }
                    .help("Largura: \(effectivePreviewWidth.label) — clique para alternar")
                }
            }
        }
        .focusedSceneValue(\.viewMode, $viewMode)
        .focusedSceneValue(\.editorActions, editorActions)
        .focusedSceneValue(\.findActions, FindActions(
            find: startFind,
            findNext: { findStep(forward: true) },
            findPrevious: { findStep(forward: false) },
            replace: startReplace
        ))
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

    // MARK: - Find routing

    private func startFind() {
        if viewMode == .previewOnly {
            previewFindPresented = true
        } else {
            editorActions.performFind(.showFindInterface)
        }
    }

    private func findStep(forward: Bool) {
        if viewMode == .previewOnly {
            if previewFindPresented {
                previewFind(forward: forward)
            } else {
                previewFindPresented = true
            }
        } else {
            editorActions.performFind(forward ? .nextMatch : .previousMatch)
        }
    }

    private func startReplace() {
        if viewMode == .previewOnly {
            previewFindPresented = true
        } else {
            editorActions.performFind(.showReplaceInterface)
        }
    }

    private func previewFind(forward: Bool) {
        guard !previewFindQuery.isEmpty else { return }
        previewActions.find(previewFindQuery, forward: forward)
    }

    private func closePreviewFind() {
        previewFindPresented = false
        previewActions.clearFindSelection()
    }

    /// Width level applies only in full-preview mode; other modes stay normal.
    private var effectivePreviewWidth: PreviewWidth {
        guard viewMode == .previewOnly else { return .normal }
        return PreviewWidth(rawValue: previewWidthLevel) ?? .normal
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

/// Floating find bar over the preview (⌘3 mode), backed by WKWebView.find.
struct PreviewFindBar: View {
    @Binding var query: String
    var onNext: () -> Void
    var onPrevious: () -> Void
    var onClose: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Localizar", text: $query)
                .textFieldStyle(.plain)
                .frame(width: 180)
                .focused($isFocused)
                .onSubmit(onNext)
                .onExitCommand(perform: onClose)
                .onChange(of: query) {
                    if !query.isEmpty { onNext() }
                }
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help("Anterior (⇧⌘G)")
            Button(action: onNext) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .help("Seguinte (⌘G)")
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Fechar (Esc)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .padding(12)
        .onAppear { isFocused = true }
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
