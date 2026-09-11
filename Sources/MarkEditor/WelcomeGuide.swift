import AppKit
import SwiftUI

/// The bundled, localized welcome document
/// (`Resources/Welcome/<language>.lproj/Welcome.md`). It opens as an untitled
/// copy, so people can experiment freely and save it only if they want to.
enum WelcomeGuide {
    static let shownKey = "hasShownWelcomeGuide"

    /// First launch without a file to open: show the guide. SwiftUI puts up
    /// its "Open" panel at launch by itself (it never asks the app
    /// delegate), so that panel is dismissed if it shows up meanwhile.
    static func showOnFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: shownKey) else { return }
        defaults.set(true, forKey: shownKey)
        guard open() else { return }
        dismissLaunchOpenPanel(until: Date().addingTimeInterval(3))
    }

    private static func dismissLaunchOpenPanel(until deadline: Date) {
        for panel in NSApp.windows.compactMap({ $0 as? NSOpenPanel }) where panel.isVisible {
            panel.cancel(nil)
        }
        guard Date() < deadline else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            dismissLaunchOpenPanel(until: deadline)
        }
    }

    /// Opens the guide; returns false when it isn't bundled or can't open.
    /// Built as a new untitled document holding the guide's text (the path
    /// "New" takes), rather than a duplicate, which would be titled "copy of".
    @discardableResult
    static func open() -> Bool {
        let controller = NSDocumentController.shared
        guard let url = Bundle.main.url(forResource: "Welcome", withExtension: "md"),
              let type = controller.defaultType else { return false }
        do {
            let document = try controller.makeUntitledDocument(ofType: type)
            try document.read(from: url, ofType: type)
            document.displayName = String(localized: "Welcome")
            controller.addDocument(document)
            document.makeWindowControllers()
            document.showWindows()
            return true
        } catch {
            NSApp.presentError(error)
            return false
        }
    }
}

struct HelpCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Welcome Guide") { WelcomeGuide.open() }
        }
    }
}
