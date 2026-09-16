import SwiftUI

@main
struct LaudaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            ExportCommands()
            FormatCommands()
            FindCommands()
            ViewModeCommands()
            HelpCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        RecentDocuments.resyncSystemList()
        // Launched to open files (e.g. from Finder)? Then no welcome guide.
        let isDefaultLaunch = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        if isDefaultLaunch {
            WelcomeGuide.showOnFirstLaunch()
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: nil)
    }

    /// AppKit re-adds a document to the recents when its window closes —
    /// even right after "Clear Menu". Closing a doc that's still in our
    /// store legitimately bumps it to the top; one that was cleared must
    /// stay forgotten, so shortly after the close we resync the system
    /// list from our store.
    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if SettingsWindow.shouldClose(whenClosing: window, among: NSApp.windows) {
            DispatchQueue.main.async { SettingsWindow.current?.close() }
        }
        guard let url = window.representedURL else { return }
        if RecentDocuments.contains(url) {
            RecentDocuments.note(url)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            RecentDocuments.resyncSystemList()
        }
    }

    /// File > Open. The document controller's own panel isn't modal, so a
    /// click on a document window sends it behind that window, where it's
    /// easy to lose. Handled here, ahead of the controller in the responder
    /// chain, the panel runs app-modal and stays in front until dismissed.
    /// The menu item stays native: replacing it made SwiftUI bring the
    /// original back whenever it rebuilt the menu bar.
    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = MarkdownDocument.readableContentTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error {
                    Log.documents.failure("Opening a document", error)
                    NSApp.presentError(error)
                }
            }
        }
    }

    /// "Clear Menu" targets the responder chain; the app delegate comes
    /// before NSDocumentController, so we clear our persisted copy too —
    /// otherwise the cleared list would resurrect on the next launch.
    @objc func clearRecentDocuments(_ sender: Any?) {
        RecentDocuments.clear()
        NSDocumentController.shared.clearRecentDocuments(sender)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // No window tabbing: a document window holds one file, and merging
        // windows into tabs only muddles that. Set before the menus are
        // built, so AppKit leaves out "Show Tab Bar", "Show All Tabs" and
        // "Merge All Windows" instead of us fighting them later.
        NSWindow.allowsAutomaticWindowTabbing = false
        AppSettings.registerDefaults()
        // Follows the system appearance by default; Settings can pin Light or Dark.
        AppearanceMode.stored.apply()
    }
}
