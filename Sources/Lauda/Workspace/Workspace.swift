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
final class Workspace: NSObject, DocumentHost {
    static let shared = Workspace()

    private var tabs = TabList<MarkdownDocument>()

    /// Where the settings and the session are kept. Injected, as everywhere
    /// else in the app, so a test drives its own tabs without writing to the
    /// reader's preferences.
    @ObservationIgnored private let defaults: UserDefaults

    /// Which panes the window shows; a new session starts in the last one used.
    var viewMode: ViewMode = .split {
        didSet { defaults[AppSettings.lastViewMode] = viewMode.rawValue }
    }
    /// Where the divider between editor and preview sits.
    var splitFraction: Double = 0.5 {
        didSet { defaults[AppSettings.splitFraction] = splitFraction }
    }

    /// The window, for sheets such as the export panel.
    @ObservationIgnored let windowReference = WindowReference()
    @ObservationIgnored private var windowController: NSWindowController?
    /// Off while the app quits: documents closing then are not the reader
    /// closing tabs, and the next launch should bring them back.
    @ObservationIgnored var remembersSession = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        viewMode = ViewMode(rawValue: defaults[AppSettings.lastViewMode]) ?? .split
        splitFraction = defaults[AppSettings.splitFraction]
    }

    var documents: [MarkdownDocument] { tabs.items }
    var selected: MarkdownDocument? { tabs.selected }
    var selectedIndex: Int? { tabs.selectedIndex }
    var window: NSWindow? { windowController?.window }

    /// Whether the title bar is laid out for tabs: two or more documents,
    /// and the title gives way to them. Going back to one document, the
    /// layout waits for the tabs to fade out before it changes.
    private(set) var showsTabs = false
    /// Whether the tabs have come into view. With the second document the
    /// title bar is laid out for tabs at once, and they fade in a moment
    /// later, once the strip has been on screen: what is already there when
    /// the strip is first drawn is simply there.
    private(set) var tabsAreIn = false

    /// Every open document's panes. The workspace keeps it current itself,
    /// as the tabs change, rather than leaving it to a SwiftUI update: what
    /// is on screen and has the keyboard must never be a closed document's,
    /// and an update can come late (measured: with the tabs changing inside
    /// an animation, about one close in three left the closed document's
    /// panes up, and typing went to them).
    @ObservationIgnored let stack = DocumentStackView()

    /// How long a tab takes to come or go, which the title bar waits for:
    /// the same as a change of layout, since the two often run together.
    static let tabAnimation: TimeInterval = ModeChange.duration
    /// How long the title bar takes to change its layout and show it.
    private static let titleBarSettling: TimeInterval = 0.12

    // MARK: - Tabs

    func add(_ document: MarkdownDocument) {
        tabs.add(document)
        tabsChanged()
        show(document)
        tabsChangedInWindow()
    }

    func select(_ document: MarkdownDocument) {
        select(document, keyboard: .follows)
    }

    func select(_ document: MarkdownDocument, keyboard: KeyboardAfterChoice) {
        guard tabs.contains(document) else { return }
        tabs.select(document)
        tabsChanged(keyboard: keyboard)
        show(document)
        tabsChangedInWindow()
    }

    /// The panes follow the tabs at once. The title bar's layout follows
    /// their number, late on the way back to one document: the strip drops
    /// its tabs as soon as one is left, and the layout changes once they
    /// have faded out.
    private func tabsChanged(keyboard: KeyboardAfterChoice = .follows) {
        stack.show(documents, selected: selected, in: self, keyboard: keyboard)
        let wantsTabs = documents.count >= 2
        guard wantsTabs != showsTabs else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            showsTabs = wantsTabs
            tabsAreIn = wantsTabs
        } else if wantsTabs {
            showsTabs = true
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.titleBarSettling) { [weak self] in
                guard let self, self.showsTabs else { return }
                self.tabsAreIn = true
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.tabAnimation) { [weak self] in
                guard let self, self.documents.count < 2 else { return }
                self.showsTabs = false
                self.tabsAreIn = false
                self.tabsChangedInWindow()
            }
        }
    }

    /// The tab of an open file, when there is one; what the last session's
    /// front tab comes back as.
    func select(fileAt url: URL) {
        let path = url.canonicalPath
        if let document = documents.first(where: {
            $0.fileURL?.canonicalPath == path
        }) {
            select(document)
        }
    }

    func selectNext() {
        selectTab(.next)
    }

    func selectPrevious() {
        selectTab(.previous)
    }

    /// The tab a key leads to from the one showing (KeyboardRow): the menu's
    /// Show Next and Show Previous Tab, and the strip walked from the
    /// keyboard.
    func selectTab(_ key: KeyboardRow.Key, keyboard: KeyboardAfterChoice = .follows) {
        guard documents.count > 1,
            let index = KeyboardRow.target(key, current: selectedIndex, count: documents.count)
        else { return }
        select(documents[index], keyboard: keyboard)
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
        tabs.remove(document)
        tabsChanged()
        if let next = tabs.selected {
            if (windowController?.document as AnyObject?) !== next {
                show(next)
            }
        } else {
            windowController = nil
            windowReference.window = nil
        }
        tabsChangedInWindow()
    }

    /// Save As, Rename and Move change where a document lives.
    func documentDidSave() {
        tabsChangedInWindow()
    }

    func clearRecents() {
        RecentDocuments.clear(defaults: defaults)
        NSDocumentController.shared.clearRecentDocuments(nil)
    }

    /// After a change to the tabs: the title bar shows a title or the tabs,
    /// never both, and the session is written so the next launch opens what
    /// is open now.
    private func tabsChangedInWindow() {
        updateTitleVisibility()
        storeSession()
    }

    private func updateTitleVisibility() {
        window?.titleVisibility = showsTabs ? .hidden : .visible
    }

    private func storeSession() {
        guard remembersSession else { return }
        OpenSession.store(.init(urls: documents.compactMap(\.fileURL), selected: selected?.fileURL), defaults: defaults)
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
        let window = NSWindow(
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
