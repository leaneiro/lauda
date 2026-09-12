import SwiftUI
import AppKit

struct ContentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    /// Per-window mode; -1 means "not chosen yet" so a brand-new window
    /// inherits the last mode used anywhere (restored windows keep theirs).
    @SceneStorage("viewMode") private var storedViewMode: Int = -1
    @AppStorage(AppSettings.lastViewMode) private var lastViewMode: Int

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
    @AppStorage(AppSettings.previewWidthLevel) private var previewWidthLevel: Int
    @State private var scrollSync = ScrollSync()
    @State private var editorActions = EditorActions()
    @State private var previewActions = PreviewActions()
    @State private var lastSavedText: String?
    @State private var lastSaveDate: Date?
    @State private var findPresented = false
    @State private var findQuery = ""
    @State private var findCurrent = 0
    @State private var findTotal = 0
    @State private var outlinePresented = false
    /// The window this view lives in, for sheets such as the export panel.
    @State private var hostWindow = WindowReference()

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
        .background(WindowReader(reference: hostWindow))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View Mode", selection: viewModeBinding) {
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
                    OutlinePopover(items: Outline.items(in: document.text), onSelect: navigate(to:))
                }
            }
            ToolbarItem(placement: .automatic) {
                if viewMode == .previewOnly {
                    Button {
                        previewWidthLevel = effectivePreviewWidth.next.rawValue
                    } label: {
                        WidthLevelIcon(level: effectivePreviewWidth)
                    }
                    .help("Text width: \(effectivePreviewWidth.label). Next: \(effectivePreviewWidth.next.label)")
                    .accessibilityLabel("Text width: \(effectivePreviewWidth.label)")
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
            // Only this document's saves count: another window can hold
            // exactly the same text.
            guard let save = notification.object as? DocumentSave,
                  save.documentID == document.id else { return }
            lastSavedText = save.text
            lastSaveDate = Date()
        }
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            if let wordCount {
                Text("\(wordCount) words")
            }
            Text("\(document.text.count) characters")
            if let readingTime = wordCount.flatMap(ReadingTime.label(forWordCount:)) {
                Text(readingTime)
            }
            Spacer()
            saveStatusView
        }
        .task(id: document.text) { await updateWordCount() }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // MARK: - Outline

    private func navigate(to item: OutlineItem) {
        outlinePresented = false
        let lineCount = max(SourceLines.count(in: document.text), 1)
        scrollSync = ScrollSync(
            line: Double(item.line),
            fraction: CGFloat(item.line) / CGFloat(lineCount),
            source: .navigation
        )
        if viewMode != .previewOnly {
            editorActions.placeCaret(atSourceLine: item.line)
        }
    }

    // MARK: - Export

    private var exportTitle: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? String(localized: "Untitled")
    }

    private func exportHTML() {
        DocumentExporter.promptAndExportHTML(
            markdown: document.text,
            title: exportTitle,
            baseDirectory: fileURL?.deletingLastPathComponent(),
            window: hostWindow.window
        )
    }

    private func exportPDF() {
        DocumentExporter.promptAndExportPDF(
            markdown: document.text,
            title: exportTitle,
            baseDirectory: fileURL?.deletingLastPathComponent(),
            window: hostWindow.window
        )
    }

    // MARK: - Find routing (unified bar, all modes)

    private func startFind() {
        findPresented = true
        editorActions.coordinator?.find.countsChanged = { current, total in
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

    /// Words in the document; nil until the first count finishes.
    @State private var wordCount: Int?

    /// Counting walks the whole text (slow for long Japanese or Chinese
    /// documents), so while typing it waits for a pause and runs off the
    /// main thread. The first count, when the window opens, runs right away.
    private func updateWordCount() async {
        if wordCount != nil {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
        }
        let text = document.text
        let count = await Task.detached(priority: .userInitiated) { WordCount.count(in: text) }.value
        if !Task.isCancelled {
            wordCount = count
        }
    }

    private var saveStatusView: some View {
        let status = saveStatus
        return HStack(spacing: 5) {
            Image(systemName: status.icon)
                .foregroundStyle(status.color)
            Text(status.label)
        }
        .help("macOS saves automatically; ⌘S saves right away.")
    }

    private var saveStatus: (icon: String, label: String, color: Color) {
        if fileURL == nil && lastSavedText == nil {
            return ("circle.dotted", String(localized: "Not saved yet"), .secondary)
        }
        if document.text == lastSavedText {
            if let date = lastSaveDate {
                let time = date.formatted(date: .omitted, time: .shortened)
                return ("checkmark.circle.fill", String(localized: "Saved · \(time)"), .green)
            }
            return ("checkmark.circle.fill", String(localized: "Saved"), .green)
        }
        return ("ellipsis.circle.fill", String(localized: "Editing…"), .orange)
    }

    /// Display width of the editor pane: the stored fraction, clamped so both
    /// panes keep a usable width when the window shrinks (the stored value is
    /// untouched, so enlarging the window restores the user's position).
    private func editorWidth(in totalWidth: CGFloat) -> CGFloat {
        (totalWidth - SplitDivider.thickness)
            * SplitDivider.clamp(splitFraction, totalWidth: totalWidth, minPaneWidth: Self.minPaneWidth)
    }
}
