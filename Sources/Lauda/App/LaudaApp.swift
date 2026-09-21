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
