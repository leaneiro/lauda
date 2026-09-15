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
    @State private var editorActions: EditorActions
    @State private var previewActions: PreviewActions
    @State private var findSession: FindSession
    @State private var lastSavedText: String?
    @State private var lastSaveDate: Date?
    @State private var outlinePresented = false
    /// The window this view lives in, for sheets such as the export panel.
    @State private var hostWindow = WindowReference()

    private static let minPaneWidth: CGFloat = 280

    init(document: Binding<MarkdownDocument>, fileURL: URL?) {
        _document = document
        self.fileURL = fileURL
        // The find session talks to the same pane bridges the window keeps.
        let editor = EditorActions()
        let preview = PreviewActions()
        _editorActions = State(initialValue: editor)
        _previewActions = State(initialValue: preview)
        _findSession = State(initialValue: FindSession(editor: editor, preview: preview))
    }

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
            if findSession.isPresented {
                FindBar(
                    query: $findSession.query,
                    current: findSession.current,
                    total: findSession.total,
                    onQueryChanged: { findSession.search(in: viewMode) },
                    onNext: { findSession.step(forward: true, in: viewMode) },
                    onPrevious: { findSession.step(forward: false, in: viewMode) },
                    onClose: findSession.close
                )
            }
        }
        .frame(minWidth: 700, minHeight: 440)
        .onChange(of: viewMode) {
            findSession.modeChanged(to: viewMode)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusBar(
                text: document.text,
                fileURL: fileURL,
                lastSavedText: lastSavedText,
                lastSaveDate: lastSaveDate
            )
        }
        .background(WindowReader(reference: hostWindow))
        .toolbar {
            DocumentToolbar(
                viewMode: viewModeBinding,
                outlinePresented: $outlinePresented,
                text: document.text,
                previewWidth: effectivePreviewWidth,
                onSelectHeading: navigate(to:),
                onCycleWidth: { previewWidthLevel = effectivePreviewWidth.next.rawValue }
            )
        }
        .focusedSceneValue(\.viewMode, viewModeBinding)
        .focusedSceneValue(\.editorActions, editorActions)
        .focusedSceneValue(\.exportActions, WindowExporter(
            markdown: { document.text },
            fileURL: fileURL,
            window: hostWindow
        ).actions)
        .focusedSceneValue(\.findActions, FindActions(
            find: { findSession.open(in: viewMode) },
            findNext: { findSession.step(forward: true, in: viewMode) },
            findPrevious: { findSession.step(forward: false, in: viewMode) },
            replace: { findSession.replace(in: viewMode) }
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

    // MARK: - Outline

    private func navigate(to item: OutlineItem) {
        outlinePresented = false
        let jump = OutlineJump(to: item, in: document.text, mode: viewMode)
        scrollSync = jump.scrollSync
        if let line = jump.caretLine {
            editorActions.placeCaret(atSourceLine: line)
        }
    }

    /// Width level applies only in full-preview mode; other modes stay normal.
    private var effectivePreviewWidth: PreviewWidth {
        guard viewMode == .previewOnly else { return .normal }
        return PreviewWidth(rawValue: previewWidthLevel) ?? .normal
    }

    /// Display width of the editor pane: the stored fraction, clamped so both
    /// panes keep a usable width when the window shrinks (the stored value is
    /// untouched, so enlarging the window restores the user's position).
    private func editorWidth(in totalWidth: CGFloat) -> CGFloat {
        (totalWidth - SplitDivider.thickness)
            * SplitDivider.clamp(splitFraction, totalWidth: totalWidth, minPaneWidth: Self.minPaneWidth)
    }
}
