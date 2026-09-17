import AppKit
import SwiftUI

/// The bundled, localized welcome document
/// (`Resources/Welcome/<language>.lproj/Welcome.md`). It opens as an untitled
/// copy, so people can experiment freely and save it only if they want to.
enum WelcomeGuide {
    /// First launch without a file to open: show the guide. Returns whether
    /// it did, so the launch knows not to offer anything else.
    static func showOnFirstLaunch() -> Bool {
        let defaults = UserDefaults.standard
        guard !defaults[AppSettings.hasShownWelcomeGuide] else { return false }
        defaults[AppSettings.hasShownWelcomeGuide] = true
        return open()
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
            Log.documents.failure("Opening the welcome guide", error)
            NSApp.presentError(error)
            return false
        }
    }
}
