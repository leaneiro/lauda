import AppKit
import SwiftUI

/// The one window every open document lives in, and the tabs it shows. Each
/// document keeps its own panes in it (see DocumentStack); selecting a tab
/// brings that document's forward, which is why switching is instant and a
/// tab can animate in or out.
///
/// The window belongs to AppKit rather than to a SwiftUI document scene,
/// because such a scene is one window per document. SwiftUI still draws
/// everything in it, toolbar and title included.
@MainActor
@Observable
final class Workspace: NSObject {
    static let shared = Workspace()

    private var tabs = TabList<MarkdownDocument>()

    /// Which panes the window shows; a new session starts in the last one used.
    var viewMode: ViewMode = .split {
        didSet { UserDefaults.standard[AppSettings.lastViewMode] = viewMode.rawValue }
    }
    /// Where the divider between editor and preview sits.
    var splitFraction: Double = 0.5 {
        didSet { UserDefaults.standard[AppSettings.splitFraction] = splitFraction }
    }

    /// The window, for sheets such as the export panel.
    @ObservationIgnored let windowReference = WindowReference()
    @ObservationIgnored private var windowController: NSWindowController?
    /// Off while the app quits: documents closing then are not the reader
    /// closing tabs, and the next launch should bring them back.
    @ObservationIgnored var remembersSession = true

    override init() {
        super.init()
        viewMode = ViewMode(rawValue: UserDefaults.standard[AppSettings.lastViewMode]) ?? .split
        splitFraction = UserDefaults.standard[AppSettings.splitFraction]
    }

    var documents: [MarkdownDocument] { tabs.items }
    var selected: MarkdownDocument? { tabs.selected }
    var selectedIndex: Int? { tabs.selectedIndex }
    var window: NSWindow? { windowController?.window }

    /// Two or more documents: the title gives way to the tabs.
    var showsTabs: Bool { tabs.items.count >= 2 }

    // MARK: - Tabs

    func add(_ document: MarkdownDocument) {
        withAnimation(.easeOut(duration: 0.2)) {
            tabs.add(document)
        }
        show(document)
        refresh()
    }

    func select(_ document: MarkdownDocument) {
        guard tabs.contains(document) else { return }
        tabs.select(document)
        show(document)
        refresh()
    }

    /// The tab of an open file, when there is one; what the last session's
    /// front tab comes back as.
    func select(fileAt url: URL) {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if let document = documents.first(where: {
            $0.fileURL?.standardizedFileURL.resolvingSymlinksInPath().path == path
        }) {
            select(document)
        }
    }

    func selectNext() {
        step(by: 1)
    }

    func selectPrevious() {
        step(by: -1)
    }

    private func step(by offset: Int) {
        guard let index = selectedIndex, documents.count > 1 else { return }
        let count = documents.count
        select(documents[(index + offset + count) % count])
    }

    func closeSelected() {
        if let selected {
            close(selected)
        }
    }

    /// Closes a tab, letting the document have its say first: an untitled
    /// one with text in it asks whether to keep it.
    func close(_ document: MarkdownDocument) {
        guard tabs.contains(document) else { return }
        document.canClose(
            withDelegate: self,
            shouldClose: #selector(document(_:shouldClose:contextInfo:)),
            contextInfo: nil
        )
    }

    @objc private func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        if shouldClose {
            document.close()
        }
    }

    /// A document is about to close, however that came about. The shared
    /// window controller has to be with a document that stays before this
    /// one goes: a document closes the windows it holds. The last document
    /// does take the window with it.
    func willClose(_ document: MarkdownDocument) {
        guard tabs.contains(document) else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            tabs.remove(document)
        }
        if let next = tabs.selected {
            if (windowController?.document as AnyObject?) !== next {
                show(next)
            }
        } else {
            windowController = nil
            windowReference.window = nil
        }
        refresh()
    }

    /// Save As, Rename and Move change where a document lives.
    func documentDidSave() {
        refresh()
    }

    func clearRecents() {
        RecentDocuments.clear()
        NSDocumentController.shared.clearRecentDocuments(nil)
    }

    private func refresh() {
        window?.titleVisibility = showsTabs ? .hidden : .visible
        if remembersSession {
            OpenSession.store(.init(urls: documents.compactMap(\.fileURL), selected: selected?.fileURL))
        }
    }

    // MARK: - The window

    private func show(_ document: MarkdownDocument) {
        let controller = ensureWindow()
        // The controller goes to the selected document, which is what makes
        // the title, the proxy icon, Save and the sheets target it.
        document.addWindowController(controller)
        controller.showWindow(nil)
    }

    private func ensureWindow() -> NSWindowController {
        if let windowController { return windowController }
        let hosting = NSHostingController(rootView: WorkspaceView(workspace: self))
        // SwiftUI's toolbar and title reach a window it doesn't own; measured
        // to land where a document scene's window puts them.
        hosting.sceneBridgingOptions = [.toolbars, .title]
        let window = WorkspaceWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 1200, height: 800))
        if !window.setFrameUsingName(Self.frameName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameName)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        // The session brings the tabs back (see OpenSession); the system's
        // window restoration has nothing of ours to restore.
        window.isRestorable = false
        windowReference.window = window
        let controller = NSWindowController(window: window)
        windowController = controller
        return controller
    }

    private static let frameName = "workspace"

    /// The tab strip is as wide as the window leaves it, so it changes width
    /// after the window does, once the toolbar has already laid itself out
    /// for the new width with the strip's old one. Measured: shrinking the
    /// window comes out right, growing it leaves the strip in its old slot
    /// and the controls behind it in the middle of the bar, and telling the
    /// toolbar that its items' sizes are no longer good is what makes it lay
    /// out anew.
    func layOutToolbarAgain() {
        DispatchQueue.main.async { [weak self] in
            guard let toolbar = self?.window?.toolbar else { return }
            for item in toolbar.items {
                item.view?.invalidateIntrinsicContentSize()
            }
        }
    }
}

private final class WorkspaceWindow: NSWindow {
    /// The close button means every tab: the document controller asks each
    /// document in turn and closes it, and the last one takes the window
    /// with it.
    ///
    /// Left to AppKit, the button is about one document, the one the window
    /// is with: it asks that document whether it can close and, from inside
    /// that question, the window's delegate. Closing every document from
    /// there waits forever on the one already being asked, so the button
    /// never gets that far.
    override func performClose(_ sender: Any?) {
        NSDocumentController.shared.closeAllDocuments(
            withDelegate: nil, didCloseAllSelector: nil, contextInfo: nil)
    }
}
