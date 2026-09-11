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
    func findUpdate(_ query: String) -> (current: Int, total: Int) {
        coordinator?.findUpdate(query) ?? (0, 0)
    }
    func findStep(forward: Bool) -> (current: Int, total: Int) {
        coordinator?.findStep(forward: forward) ?? (0, 0)
    }
    func findClear() { coordinator?.findClear() }
}

/// Bridges the find bar to the focused window's preview coordinator.
final class PreviewActions {
    weak var coordinator: PreviewWebView.Coordinator?

    func find(_ query: String, forward: Bool, restart: Bool, completion: @escaping (Int, Int) -> Void) {
        if let coordinator {
            coordinator.find(query, forward: forward, restart: restart, completion: completion)
        } else {
            completion(0, 0)
        }
    }

    func clearFind() { coordinator?.clearFind() }
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

/// Export commands routed to the focused window's document.
struct ExportActions {
    var exportHTML: () -> Void
    var exportPDF: () -> Void
}

struct ExportActionsKey: FocusedValueKey {
    typealias Value = ExportActions
}

extension FocusedValues {
    var exportActions: ExportActions? {
        get { self[ExportActionsKey.self] }
        set { self[ExportActionsKey.self] = newValue }
    }
}

struct ExportCommands: Commands {
    @FocusedValue(\.exportActions) private var exportActions

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Exportar como PDF…") { exportActions?.exportPDF() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(exportActions == nil)
            Button("Exportar como HTML…") { exportActions?.exportHTML() }
                .keyboardShortcut("e", modifiers: [.command, .option, .shift])
                .disabled(exportActions == nil)
        }
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

/// Estimated reading time for the status bar (~200 words per minute).
enum ReadingTime {
    static let wordsPerMinute = 200

    static func label(forWordCount wordCount: Int) -> String? {
        guard wordCount > 0 else { return nil }
        let minutes = Int((Double(wordCount) / Double(wordsPerMinute)).rounded())
        return minutes < 1 ? "menos de 1 min de leitura" : "~\(minutes) min de leitura"
    }
}

/// Shared scroll position between the panes, anchored in the source text so
/// both show the same block even when images or tables make the preview much
/// taller than the text. `source` marks which pane the user scrolled, so the
/// other pane follows and echoes are ignored.
struct ScrollSync: Equatable {
    enum Source { case editor, preview }
    /// Fractional source line at the top of the pane; [-1, 0) is the padding
    /// above the first line. nil when the pane has no line map.
    var line: Double?
    /// Proportional position, the fallback when there's no line map.
    var fraction: CGFloat = 0
    /// Source line at the top of this pane when scrolled all the way down.
    var endLine: Double?
    /// Distance to the bottom in screens, capped at 1. Over that last screen
    /// the follower absorbs the gap between where `endLine` lands in it and
    /// its own end, so both panes reach the bottom together.
    var toEnd: Double = 1
    var source: Source = .editor

    func differs(from other: ScrollSync) -> Bool {
        abs(fraction - other.fraction) > 0.001
            || abs(toEnd - other.toEnd) > 0.005
            || abs((line ?? -2) - (other.line ?? -2)) > 0.005
    }
}

struct ContentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    /// Per-window mode; -1 means "not chosen yet" so a brand-new window
    /// inherits the last mode used anywhere (restored windows keep theirs).
    @SceneStorage("viewMode") private var storedViewMode: Int = -1
    @AppStorage(SettingsKeys.lastViewMode) private var lastViewMode = ViewMode.split.rawValue

    private var viewMode: ViewMode {
        ViewMode(rawValue: storedViewMode >= 0 ? storedViewMode : lastViewMode) ?? .split
    }

    private var viewModeBinding: Binding<ViewMode> {
        Binding(
            get: { viewMode },
            set: { newMode in
                storedViewMode = newMode.rawValue
                lastViewMode = newMode.rawValue
            }
        )
    }
    @SceneStorage("splitFraction") private var splitFraction: Double = 0.5
    @AppStorage(SettingsKeys.previewWidthLevel) private var previewWidthLevel = PreviewWidth.normal.rawValue
    @State private var scrollSync = ScrollSync()
    @State private var editorActions = EditorActions()
    @State private var previewActions = PreviewActions()
    @State private var lastSavedText: String?
    @State private var lastSaveDate: Date?
    @State private var findPresented = false
    @State private var findQuery = ""
    @State private var findCurrent = 0
    @State private var findTotal = 0

    private static let minPaneWidth: CGFloat = 280

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            HStack(spacing: 0) {
                if viewMode != .previewOnly {
                    MarkdownTextView(
                        text: $document.text,
                        scrollSync: $scrollSync,
                        actions: editorActions,
                        fileURL: fileURL
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
                        markdown: document.text,
                        baseURL: fileURL?.deletingLastPathComponent(),
                        scrollSync: $scrollSync,
                        contentWidthRem: effectivePreviewWidth.rem,
                        actions: previewActions
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .coordinateSpace(name: "split")
        .overlay(alignment: .topTrailing) {
            if findPresented {
                FindBar(
                    query: $findQuery,
                    current: findCurrent,
                    total: findTotal,
                    onQueryChanged: { runFind() },
                    onNext: { stepFind(forward: true) },
                    onPrevious: { stepFind(forward: false) },
                    onClose: closeFind
                )
            }
        }
        .frame(minWidth: 700, minHeight: 440)
        .onChange(of: viewMode) {
            guard findPresented else { return }
            // The panes are recreated on mode switches — re-target the search.
            editorActions.findClear()
            previewActions.clearFind()
            DispatchQueue.main.async { runFind() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            statusBar
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Modo de exibição", selection: viewModeBinding) {
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
                        WidthLevelIcon(level: effectivePreviewWidth)
                    }
                    .help("Largura do texto: \(effectivePreviewWidth.label). Próxima: \(effectivePreviewWidth.next.label)")
                    .accessibilityLabel("Largura do texto: \(effectivePreviewWidth.label)")
                }
            }
        }
        .focusedSceneValue(\.viewMode, viewModeBinding)
        .focusedSceneValue(\.editorActions, editorActions)
        .focusedSceneValue(\.exportActions, ExportActions(
            exportHTML: exportHTML,
            exportPDF: exportPDF
        ))
        .focusedSceneValue(\.findActions, FindActions(
            find: startFind,
            findNext: { stepFind(forward: true) },
            findPrevious: { stepFind(forward: false) },
            replace: startReplace
        ))
        .onAppear {
            if let fileURL {
                lastSavedText = document.text
                RecentDocuments.note(fileURL)
            }
            // Materialize the inherited mode so this window stops following
            // the global once it's on screen.
            if storedViewMode < 0 {
                storedViewMode = lastViewMode
            }
        }
        .onChange(of: fileURL) {
            // First save of a new document (Save As) lands here.
            if let fileURL {
                RecentDocuments.note(fileURL)
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
            if let readingTime = ReadingTime.label(forWordCount: wordCount) {
                Text(readingTime)
            }
            Spacer()
            saveStatusView
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // MARK: - Export

    private var exportTitle: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "Documento"
    }

    private func exportHTML() {
        DocumentExporter.promptAndExportHTML(
            markdown: document.text,
            title: exportTitle,
            baseDirectory: fileURL?.deletingLastPathComponent()
        )
    }

    private func exportPDF() {
        DocumentExporter.promptAndExportPDF(
            markdown: document.text,
            title: exportTitle,
            baseDirectory: fileURL?.deletingLastPathComponent(),
            window: NSApp.keyWindow ?? NSApp.mainWindow
        )
    }

    // MARK: - Find routing (unified bar, all modes)

    private func startFind() {
        findPresented = true
        editorActions.coordinator?.findCountsChanged = { current, total in
            DispatchQueue.main.async {
                findCurrent = current
                findTotal = total
            }
        }
        if !findQuery.isEmpty {
            runFind()
        }
    }

    private func runFind() {
        guard findPresented else { return }
        guard !findQuery.isEmpty else {
            findCurrent = 0
            findTotal = 0
            editorActions.findClear()
            previewActions.clearFind()
            return
        }
        if viewMode == .previewOnly {
            previewActions.find(findQuery, forward: true, restart: true) { current, total in
                findCurrent = current
                findTotal = total
            }
        } else {
            let counts = editorActions.findUpdate(findQuery)
            findCurrent = counts.current
            findTotal = counts.total
        }
    }

    private func stepFind(forward: Bool) {
        guard findPresented, !findQuery.isEmpty else {
            startFind()
            return
        }
        if viewMode == .previewOnly {
            previewActions.find(findQuery, forward: forward, restart: false) { current, total in
                findCurrent = current
                findTotal = total
            }
        } else {
            let counts = editorActions.findStep(forward: forward)
            findCurrent = counts.current
            findTotal = counts.total
        }
    }

    private func startReplace() {
        if viewMode == .previewOnly {
            startFind()
        } else {
            closeFind()
            editorActions.performFind(.showReplaceInterface)
        }
    }

    private func closeFind() {
        findPresented = false
        findCurrent = 0
        findTotal = 0
        editorActions.findClear()
        previewActions.clearFind()
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

/// Toolbar glyph for the preview width level: a page outline whose inner
/// "text column" grows with the level, animating between states so the
/// cycle is visible at a glance.
struct WidthLevelIcon: View {
    let level: PreviewWidth

    private var columnWidth: CGFloat {
        switch level {
        case .normal: return 6
        case .medium: return 10
        case .wide: return 14
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3.5)
                .strokeBorder(.secondary, lineWidth: 1.2)
                .frame(width: 19, height: 14)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(.secondary)
                .frame(width: columnWidth, height: 8)
        }
        .frame(width: 22, height: 16)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: level)
        .contentShape(Rectangle())
    }
}

/// Unified floating find bar — same look and position in every view mode.
struct FindBar: View {
    @Binding var query: String
    let current: Int
    let total: Int
    var onQueryChanged: () -> Void
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
                .frame(width: 170)
                .focused($isFocused)
                .onSubmit(onNext)
                .onExitCommand(perform: onClose)
                .onChange(of: query) {
                    onQueryChanged()
                }
            if !query.isEmpty {
                Text(total > 0 ? "\(current)/\(total)" : "0")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(total > 0 ? Color.secondary : Color.red)
                    .frame(minWidth: 34)
            }
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(total == 0)
            .help("Anterior (⇧⌘G)")
            Button(action: onNext) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(total == 0)
            .help("Seguinte (⌘G)")
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Fechar (Esc)")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 10, y: 3)
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
