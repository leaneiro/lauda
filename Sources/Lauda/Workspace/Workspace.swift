import AppKit
import SwiftUI

// SPIKE: one AppKit-owned window for every open document. The panes stay the
// same views; selecting a tab changes what they show.
@MainActor
@Observable
final class Workspace {
    static let shared = Workspace()

    private var tabs = TabList<MarkdownNSDocument>()
    var viewMode: ViewMode = .split

    @ObservationIgnored private var windowController: NSWindowController?

    var documents: [MarkdownNSDocument] { tabs.items }
    var selected: MarkdownNSDocument? { tabs.selected }
    var selectedIndex: Int? { tabs.selectedIndex }
    var window: NSWindow? { windowController?.window }

    func add(_ document: MarkdownNSDocument) {
        withAnimation(.easeOut(duration: 0.2)) {
            tabs.add(document)
        }
        show(document)
    }

    func select(_ document: MarkdownNSDocument) {
        guard tabs.contains(document) else { return }
        tabs.select(document)
        show(document)
    }

    func select(_ index: Int) {
        guard documents.indices.contains(index) else { return }
        select(documents[index])
    }

    func close(_ index: Int) {
        guard documents.indices.contains(index) else { return }
        close(documents[index])
    }

    /// Closes a tab. The shared window controller has to be with a document
    /// that stays before this one closes: a document closes the windows it
    /// holds. The last document does take the window with it.
    func close(_ document: MarkdownNSDocument) {
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
        }
        document.close()
    }

    private func show(_ document: MarkdownNSDocument) {
        // A jump both panes follow, the way the outline's is: the tab comes
        // back where it was left.
        document.scrollSync.source = .navigation
        let controller = ensureWindow()
        // The controller goes to the selected document, which is what makes
        // the title, the proxy icon, Save and the sheets target it.
        document.addWindowController(controller)
        controller.showWindow(nil)
    }

    private func ensureWindow() -> NSWindowController {
        if let windowController { return windowController }
        let hosting = NSHostingController(rootView: WorkspaceView(workspace: self))
        // Measured: SwiftUI's toolbar and title reach a window SwiftUI
        // doesn't own, at the positions a DocumentGroup window gives.
        hosting.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 1200, height: 800))
        window.center()
        window.isReleasedWhenClosed = false
        let controller = NSWindowController(window: window)
        windowController = controller
        return controller
    }
}

struct WorkspaceView: View {
    let workspace: Workspace
    @State private var outlinePresented = false
    @State private var windowWidth: CGFloat = 1200

    private var showsTabs: Bool { workspace.documents.count >= 2 }

    /// The measured title bar arithmetic from the document-tabs branch. The
    /// strip keeps this width even though its tabs no longer fill it: a
    /// toolbar packs items one after another, so it is this width that
    /// carries the controls to the trailing edge.
    private var stripWidth: CGFloat {
        max(windowWidth - 96 - (8 + 115 + 8 + 36 + 8) - 6, 240)
    }

    private var viewMode: Binding<ViewMode> {
        Binding(get: { workspace.viewMode }, set: { workspace.viewMode = $0 })
    }

    var body: some View {
        Group {
            if let document = workspace.selected {
                WorkspacePanes(document: document, viewMode: workspace.viewMode)
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 700, minHeight: 440)
        .background(GeometryReader { proxy in
            Color.clear.onChange(of: proxy.size.width, initial: true) { _, width in
                windowWidth = width
            }
        })
        .toolbar {
            if showsTabs {
                tabsItem
                ToolbarItem(placement: .primaryAction) { picker }
                ToolbarItem(placement: .primaryAction) { outlineButton }
            } else {
                ToolbarItem(placement: .principal) { picker }
                ToolbarItem(placement: .automatic) { outlineButton }
            }
        }
        // With tabs, the title would only repeat the selected one.
        .onChange(of: showsTabs, initial: true) { _, tabs in
            workspace.window?.titleVisibility = tabs ? .hidden : .visible
        }
    }

    /// The strip spans the title bar but must not look like it: recent
    /// systems wrap every toolbar item in one glass capsule, and the tabs
    /// want a capsule each. Hiding the item's own background leaves only
    /// theirs.
    @ToolbarContentBuilder
    private var tabsItem: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .navigation) {
                WorkspaceTabStrip(workspace: workspace, width: stripWidth)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) {
                WorkspaceTabStrip(workspace: workspace, width: stripWidth)
            }
        }
    }

    private var picker: some View {
        Picker("View Mode", selection: viewMode) {
            Label("Editor Only", systemImage: "doc.plaintext").tag(ViewMode.editorOnly)
            Label("Editor and Preview", systemImage: "rectangle.split.2x1").tag(ViewMode.split)
            Label("Preview Only", systemImage: "doc.richtext").tag(ViewMode.previewOnly)
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
    }

    private var outlineButton: some View {
        Button {
            outlinePresented.toggle()
        } label: {
            Label("Outline", systemImage: "list.bullet")
        }
        .popover(isPresented: $outlinePresented, arrowEdge: .bottom) {
            OutlinePopover(items: Outline.items(in: workspace.selected?.text ?? ""), onSelect: { _ in })
        }
    }
}

private struct WorkspacePanes: View {
    @Bindable var document: MarkdownNSDocument
    let viewMode: ViewMode

    var body: some View {
        EditorPanes(
            text: Binding(get: { document.text }, set: { document.edit($0) }),
            fileURL: document.fileURL,
            viewMode: viewMode,
            splitFraction: $document.splitFraction,
            scrollSync: $document.scrollSync,
            editorActions: document.editorActions,
            previewActions: document.previewActions,
            previewWidth: .normal
        )
    }
}
