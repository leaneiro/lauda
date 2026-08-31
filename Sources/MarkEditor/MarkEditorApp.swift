import SwiftUI

@main
struct MarkEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
                .preferredColorScheme(.light)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            ViewModeCommands()
        }

        Settings {
            SettingsView()
                .preferredColorScheme(.light)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // The app is designed light-first; keep chrome consistent regardless of system theme.
        NSApp.appearance = NSAppearance(named: .aqua)
    }
}
