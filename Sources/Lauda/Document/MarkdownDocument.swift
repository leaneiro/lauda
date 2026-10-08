import AppKit
import Observation
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

/// What a document needs from the window it lives in: it has no window of
/// its own, so opening, showing and closing it are things the workspace
/// does with its tabs. Named here, where the document is, so the dependency
/// points this way and a test can stand in for the window.
@MainActor
protocol DocumentHost: AnyObject {
    func add(_ document: MarkdownDocument)
    func select(_ document: MarkdownDocument)
    func willClose(_ document: MarkdownDocument)
    func documentDidSave()
    /// The window's close button was clicked: every tab closes.
    func closeEveryTab()
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
    /// What Revert to Saved brings back: the text as the file was opened, or
    /// as it was last saved with Save, as in the Electron edition.
    @ObservationIgnored private var revertText: String?

    var scrollSync = ScrollSync()
    /// Whether this document's panes scroll together. The chain on the
    /// divider parts them, to read one place while writing in another, and
    /// joins them again; a document opens with them joined.
    var scrollsLinked = true {
        didSet {
            // Joined again, the editor comes to the preview: the two may have
            // drifted far apart, and the reader was reading there. Shared in
            // the same turn as the joining, so that the position the editor
            // shared while apart never reaches the preview.
            if scrollsLinked, !oldValue, let here = previewActions.position() {
                scrollSync = here
            }
        }
    }
    /// Whether each pane has more than fits in it. The chain shows only
    /// while both have: joined or apart makes no difference to a pane with
    /// nowhere to scroll, as a scroll bar makes none.
    var editorScrollable = false
    var previewScrollable = false
    var panesScroll: Bool { editorScrollable && previewScrollable }
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
        // The first read is the opening; later ones bring in another app's
        // changes, which a revert takes back as well.
        if revertText == nil {
            revertText = decoded
        }
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
                self?.noteSaved(written, at: url, byTheReader: saveOperation == .saveOperation || saveOperation == .saveAsOperation)
            }
            completionHandler(error)
        }
    }

    /// AppKit calls these overrides on the main thread: this document is
    /// opened and closed by the app itself, never read concurrently nor
    /// saved on a background queue (NSDocument's two switches for that are
    /// off by default and stay off), so the hop is an assertion, not a wish.
    private func inWindow(_ work: @MainActor (any DocumentHost) -> Void) {
        MainActor.assumeIsolated { work(Self.host ?? Workspace.shared) }
    }

    /// The window documents join. Settable so a test can put its own there.
    @MainActor static var host: (any DocumentHost)?

    /// A save the reader asked for (Save, Save As) is also what Revert to
    /// Saved goes back to, and puts the file in Open Recent. An autosave does
    /// neither: it would bring every open file back into the menu moments
    /// after Clear Menu emptied it.
    private func noteSaved(_ written: String, at url: URL, byTheReader: Bool) {
        savedText = written
        savedDate = Date()
        isEdited = isDocumentEdited
        if byTheReader {
            revertText = written
            RecentDocuments.note(url)
        }
        inWindow { $0.documentDidSave() }
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

    /// No window of its own: the document joins the workspace as a tab. An
    /// old version the system's Versions browser opens is no file of the
    /// reader's: it gets no tab and no place in Open Recent.
    override func makeWindowControllers() {
        guard !isInViewingMode else { return }
        if let fileURL {
            RecentDocuments.note(fileURL)
        }
        inWindow { $0.add(self) }
    }

    /// Opening a file that is already open asks its document to show
    /// itself, which here means its tab.
    override func showWindows() {
        inWindow { $0.select(self) }
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
            inWindow { $0.select(self) }
        }
        super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
    }

    /// Every way of closing ends here (the tab's button, the window, Quit),
    /// so this is where the workspace hears of it. It has to hear first:
    /// a document closes the windows it holds, and the shared window must
    /// be with a document that stays.
    override func close() {
        inWindow { $0.willClose(self) }
        super.close()
    }

    /// The window's close button means every tab. AppKit asks only the
    /// document the window is with, here (measured on macOS 27: the button
    /// sends a private action of the window, never `performClose`), and
    /// closing every document from inside that question waits forever on the
    /// one being asked. So AppKit hears no, and the workspace closes every
    /// tab once the question is over; the last one takes the window.
    override func shouldCloseWindowController(
        _ windowController: NSWindowController,
        delegate: Any?,
        shouldClose shouldCloseSelector: Selector?,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        reply(to: delegate, selector: shouldCloseSelector, shouldClose: false, contextInfo: contextInfo)
        DispatchQueue.main.async { [weak self] in
            self?.inWindow { $0.closeEveryTab() }
        }
    }

    /// Answers one of AppKit's questions about closing, which it asks with a
    /// delegate and a selector shaped `document:shouldClose:contextInfo:`.
    private func reply(
        to delegate: Any?, selector: Selector?, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?
    ) {
        guard let delegate = delegate as? NSObject, let selector,
            let method = class_getInstanceMethod(type(of: delegate), selector)
        else { return }
        typealias Reply = @convention(c) (NSObject, Selector, NSDocument, Bool, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(method_getImplementation(method), to: Reply.self)(delegate, selector, self, shouldClose, contextInfo)
    }

    // MARK: - Revert, Rename and Move

    /// File > Revert to Saved, asked in a sheet. AppKit's own revert goes
    /// through the system's Versions browser, which a document without a
    /// window of its own can't enter: it found no window to show, and the
    /// old versions it opened came up as tabs.
    override func revertToSaved(_ sender: Any?) {
        guard fileURL != nil, let revertText, revertText != text, let window = windowForSheet else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Revert to the last saved version of “\(title)”?")
        alert.informativeText = String(localized: "Your current changes will be lost.")
        alert.addButton(withTitle: String(localized: "Revert"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.edit(revertText)
        }
    }

    /// File > Rename…: the name, in a sheet over the window. AppKit's own
    /// rename edits the title in the title bar, which is hidden while the
    /// tabs are there, so it did nothing.
    override func rename(_ sender: Any?) {
        guard let fileURL, let window = windowForSheet else { return }
        let field = NSTextField(string: fileURL.lastPathComponent)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        let alert = NSAlert()
        alert.messageText = String(localized: "Rename")
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Rename"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            var name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !name.contains("/") else { return }
            // A name typed without an extension keeps the file's.
            if (name as NSString).pathExtension.isEmpty, !fileURL.pathExtension.isEmpty {
                name += "." + fileURL.pathExtension
            }
            self.relocate(to: fileURL.deletingLastPathComponent().appendingPathComponent(name), in: window)
        }
        // The field has the keyboard, with the name selected without its
        // extension, as the Finder does.
        let base = (fileURL.deletingPathExtension().lastPathComponent as NSString).length
        DispatchQueue.main.async {
            alert.window.makeFirstResponder(field)
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: base)
        }
    }

    /// File > Move To…: a folder, chosen in a panel over the window. AppKit's
    /// own Move To opens from the title bar as well, and failed to start
    /// while the tabs hid the title.
    override func move(_ sender: Any?) {
        guard let fileURL, let window = windowForSheet else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = fileURL.deletingLastPathComponent()
        panel.prompt = String(localized: "Move")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let folder = panel.url else { return }
            self?.relocate(to: folder.appendingPathComponent(fileURL.lastPathComponent), in: window)
        }
    }

    /// Moves the file AppKit's way, coordinated and with the document
    /// following it, and says in a sheet what went wrong, such as a file of
    /// that name already there.
    private func relocate(to destination: URL, in window: NSWindow) {
        guard let fileURL, destination.standardizedFileURL != fileURL.standardizedFileURL else { return }
        move(to: destination) { [weak self] error in
            guard let self else { return }
            if let error {
                self.presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
                return
            }
            RecentDocuments.note(destination)
            self.inWindow { $0.documentDidSave() }
        }
    }
}
