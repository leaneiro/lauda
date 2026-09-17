import SwiftUI

@main
struct LaudaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Documents live in one AppKit-owned window (see Workspace): a
        // SwiftUI document scene is one window per document, and tabs need
        // one window for all of them. Settings is the only scene left, and
        // the menus still come from here.
        Settings {
            SettingsView()
        }
        .commands {
            FileCommands()
            TabCommands()
            ExportCommands()
            FormatCommands()
            FindCommands()
            ViewModeCommands()
            HelpCommands()
        }
    }
}

/// File > Open. App-modal on purpose: a panel that isn't modal slips behind
/// the window at the first click and is then hard to find again.
enum DocumentOpenPanel {
    @MainActor
    static func run() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = MarkdownDocument.readableContentTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        open(panel.urls)
    }

    /// Opens the files one after another, so their tabs keep this order
    /// whatever each one takes to read.
    @MainActor
    static func open(_ urls: [URL], then completion: @escaping @MainActor () -> Void = {}) {
        guard let url = urls.first else {
            completion()
            return
        }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error {
                Log.documents.failure("Opening a document", error)
                NSApp.presentError(error)
            }
            open(Array(urls.dropFirst()), then: completion)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // No window tabbing: the app draws its own tabs, in the title bar.
        // Set before the menus are built, so AppKit leaves out "Show Tab
        // Bar", "Show All Tabs" and "Merge All Windows".
        NSWindow.allowsAutomaticWindowTabbing = false
        AppSettings.registerDefaults()
        // Follows the system appearance by default; Settings can pin Light or Dark.
        AppearanceMode.stored.apply()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        RecentDocuments.resyncSystemList()
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: nil)

        // Launched to open files (e.g. from Finder)? Then those are the session.
        let isDefaultLaunch = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        guard isDefaultLaunch else { return }
        if WelcomeGuide.showOnFirstLaunch() { return }
        let lastSession = OpenSession.stored()
        if lastSession.urls.isEmpty {
            // Nothing to come back to: offer to open something, as a
            // document app does when it starts empty.
            DispatchQueue.main.async { DocumentOpenPanel.run() }
        } else {
            DocumentOpenPanel.open(lastSession.urls) {
                if let selected = lastSession.selected {
                    Workspace.shared.select(fileAt: selected)
                }
            }
        }
    }

    /// An empty untitled document at every launch would be noise; the launch
    /// above decides what to show.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon with nothing open offers to open something.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            DocumentOpenPanel.run()
        }
        return false
    }

    /// Quitting closes documents without the reader having closed any tab,
    /// so the session stops being rewritten from here on. Measured: the
    /// question about unsaved text comes before this, so a cancelled quit
    /// never gets here, and the documents close after it.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Workspace.shared.remembersSession = false
        return .terminateNow
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Workspace.shared.remembersSession = true
    }

    /// The responder-chain form of File > Open, for whatever still sends it.
    @objc func openDocument(_ sender: Any?) {
        DocumentOpenPanel.run()
    }

    /// Closing the last document would leave floating Settings hovering over
    /// nothing, so they close with it.
    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if SettingsWindow.shouldClose(whenClosing: window, among: NSApp.windows) {
            DispatchQueue.main.async { SettingsWindow.current?.close() }
        }
        // AppKit re-adds a document to the recents when its window closes,
        // even right after "Clear Menu"; our store is the truth, so the
        // system list is brought back in line shortly after.
        guard window.representedURL != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            RecentDocuments.resyncSystemList()
        }
    }
}
