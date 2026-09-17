import AppKit
import Observation
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

/// A Markdown file as macOS's document machinery knows it: autosave in
/// place, Versions, Finder, Rename and Move all come from NSDocument. What it
/// doesn't have is a window of its own: every open document is a tab of the
/// one workspace window, with panes of its own in it.
@objc(MarkdownDocument)
@Observable
final class MarkdownDocument: NSDocument {
    static let readableContentTypes: [UTType] = [.markdown, .plainText]

    var text: String = ""
    /// The text the file held when it was last read or written, and when
    /// that was. What the status bar reads to say "Saved".
    private(set) var savedText: String?
    private(set) var savedDate: Date?
    /// NSDocument's own edited flag and name aren't observable; the tab
    /// strip reads these.
    private(set) var isEdited = false
    private(set) var title = ""

    var scrollSync = ScrollSync()
    /// Bridges to this document's panes, and the find bar over them.
    @ObservationIgnored let editorActions: EditorActions
    @ObservationIgnored let previewActions: PreviewActions
    @ObservationIgnored let findSession: FindSession

    override init() {
        let editor = EditorActions()
        let preview = PreviewActions()
        editorActions = editor
        previewActions = preview
        findSession = FindSession(editor: editor, preview: preview)
        super.init()
        // The editor keeps its own undo stack for typing; a second one here
        // would only interleave with it.
        hasUndoManager = false
        title = displayName
    }

    override class var autosavesInPlace: Bool { true }

    /// Gives the keyboard to the pane that types or scrolls in `mode`;
    /// false while that pane doesn't exist yet.
    func takeKeyboard(in mode: ViewMode) -> Bool {
        mode == .previewOnly ? previewActions.focus() : editorActions.focus()
    }

    // MARK: - Reading and writing

    /// Strict UTF-8 with Latin-1 fallback — never lossy, so a save can't
    /// silently corrupt a file that came in another encoding.
    static func decode(_ data: Data) throws -> String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let latin1 = String(data: data, encoding: .isoLatin1) {
            Log.documents.notice("Opened a file that isn't valid UTF-8 as Latin-1")
            return latin1
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let decoded = try Self.decode(data)
        text = decoded
        savedText = decoded
    }

    override func data(ofType typeName: String) throws -> Data {
        Data(text.utf8)
    }

    /// What typing does: the text changes and the document knows it did,
    /// which marks it edited and schedules the autosave.
    func edit(_ newText: String) {
        guard newText != text else { return }
        text = newText
        updateChangeCount(.changeDone)
    }

    override func save(
        to url: URL,
        ofType typeName: String,
        for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping (Error?) -> Void
    ) {
        // Taken once, so an edit arriving mid-write isn't recorded as saved.
        let written = text
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            // An untitled document autosaved elsewhere isn't saved as far as
            // the reader is concerned; every other write put it in its file.
            if error == nil, saveOperation != .autosaveElsewhereOperation {
                self?.noteSaved(written, at: url)
            }
            completionHandler(error)
        }
    }

    private func noteSaved(_ written: String, at url: URL) {
        savedText = written
        savedDate = Date()
        isEdited = isDocumentEdited
        RecentDocuments.note(url)
        MainActor.assumeIsolated { Workspace.shared.documentDidSave() }
    }

    // MARK: - What the tab strip shows

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        isEdited = isDocumentEdited
    }

    // Inherited storage, not this class's to track: only the name that
    // follows from it is observed.
    @ObservationIgnored
    override var fileURL: URL? {
        didSet { title = displayName }
    }

    override var displayName: String! {
        get { super.displayName }
        set {
            super.displayName = newValue
            title = super.displayName
        }
    }

    // MARK: - Tabs instead of windows

    /// No window of its own: the document joins the workspace as a tab.
    override func makeWindowControllers() {
        if let fileURL {
            RecentDocuments.note(fileURL)
        }
        MainActor.assumeIsolated { Workspace.shared.add(self) }
    }

    /// Opening a file that is already open asks its document to show
    /// itself, which here means its tab.
    override func showWindows() {
        MainActor.assumeIsolated { Workspace.shared.select(self) }
    }

    /// Whether to keep unsaved text is asked in a sheet, and a sheet needs the
    /// window to be showing the document it asks about. Every way of closing
    /// comes through here, so the tab comes forward for all of them.
    override func canClose(
        withDelegate delegate: Any,
        shouldClose shouldCloseSelector: Selector?,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        if isDocumentEdited, fileURL == nil {
            MainActor.assumeIsolated { Workspace.shared.select(self) }
        }
        super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
    }

    /// Every way of closing ends here (the tab's button, the window, Quit),
    /// so this is where the workspace hears of it. It has to hear first:
    /// a document closes the windows it holds, and the shared window must
    /// be with a document that stays.
    override func close() {
        MainActor.assumeIsolated { Workspace.shared.willClose(self) }
        super.close()
    }
}
