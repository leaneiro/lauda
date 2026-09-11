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
        guard let window = notification.object as? NSWindow,
              let url = window.representedURL else { return }
        if RecentDocuments.contains(url) {
            RecentDocuments.note(url)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            RecentDocuments.resyncSystemList()
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
        AppSettings.registerDefaults()
        // Light-first by default; the user can pick Dark or Automatic in Settings.
        AppearanceMode.stored.apply()
    }
}
