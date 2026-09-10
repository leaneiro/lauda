import SwiftUI

@main
struct MarkEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            FileCommands()
            ExportCommands()
            FormatCommands()
            FindCommands()
            ViewModeCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        RecentDocuments.resyncSystemList()
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: nil)
        // FileCommands owns Novo/Abrir/Abrir Recente; DocumentGroup still
        // injects its own Abrir/Abrir Recente in a group SwiftUI doesn't let
        // us replace — hide them, re-applying whenever the menu bar is used
        // (SwiftUI can rebuild it and undo the hiding).
        NotificationCenter.default.addObserver(
            self, selector: #selector(menuDidBeginTracking(_:)),
            name: NSMenu.didBeginTrackingNotification, object: nil)
        // Any menu rebuild re-adds the native items; catch it at the source.
        NotificationCenter.default.addObserver(
            self, selector: #selector(menuDidAddItem(_:)),
            name: NSMenu.didAddItemNotification, object: nil)
        // Key-window changes (e.g. the Open panel) make SwiftUI swap in a
        // rebuilt menu bar — another moment the natives can resurface.
        NotificationCenter.default.addObserver(
            self, selector: #selector(scheduleHidePass),
            name: NSWindow.didBecomeKeyNotification, object: nil)
        mainMenuObservation = NSApp.observe(\.mainMenu) { [weak self] _, _ in
            self?.scheduleHidePass()
        }
        DispatchQueue.main.async { self.hideNativeOpenItems() }
    }

    @objc private func menuDidBeginTracking(_ notification: Notification) {
        guard (notification.object as? NSMenu) === NSApp.mainMenu else { return }
        hideNativeOpenItems()
    }

    private var hidePassScheduled = false
    private var mainMenuObservation: NSKeyValueObservation?


    @objc private func menuDidAddItem(_ notification: Notification) {
        scheduleHidePass()
    }

    /// Coalesced double pass: one right after the current build settles
    /// (items get configured post-insertion) and a late one to win any race
    /// with SwiftUI installing a freshly rebuilt menu bar.
    @objc private func scheduleHidePass() {
        guard !hidePassScheduled else { return }
        hidePassScheduled = true
        DispatchQueue.main.async {
            self.hidePassScheduled = false
            self.hideNativeOpenItems()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.hideNativeOpenItems()
        }
    }

    private func hideNativeOpenItems() {
        guard let fileMenu = NSApp.mainMenu?.items
            .first(where: { $0.title.contains("Arquivo") || $0.title.contains("File") })?.submenu
        else { return }
        for (index, item) in fileMenu.items.enumerated() {
            let isNativeOpen = item.action == #selector(NSDocumentController.openDocument(_:))
                && item.target == nil
            let isNativeRecents = (item.submenu?.delegate)
                .map { String(describing: type(of: $0)).contains("NSDocumentController") } ?? false
            guard isNativeOpen || isNativeRecents else { continue }
            item.isHidden = true
            if index > 0, fileMenu.items[index - 1].isSeparatorItem {
                fileMenu.items[index - 1].isHidden = true
            }
        }
    }

    /// AppKit re-adds a document to the recents when its window closes —
    /// even right after "Limpar Menu". Closing a doc that's still in our
    /// store legitimately bumps it to the top; one that was cleared must
    /// stay forgotten, so shortly after the close we resync the system
    /// list from our store.
    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let url = window.representedURL else { return }
        if RecentDocuments.contains(url) {
            RecentDocuments.note(url)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            RecentDocuments.resyncSystemList()
        }
    }

    /// "Limpar Menu" targets the responder chain; the app delegate comes
    /// before NSDocumentController, so we clear our persisted copy too —
    /// otherwise the cleared list would resurrect on the next launch.
    @objc func clearRecentDocuments(_ sender: Any?) {
        RecentDocuments.clear()
        NSDocumentController.shared.clearRecentDocuments(sender)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Light-first by default; the user can pick Escuro/Automático in Ajustes.
        AppearanceMode.stored.apply()
    }
}
