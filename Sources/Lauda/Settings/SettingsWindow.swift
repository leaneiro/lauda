import AppKit

/// The Settings window, which floats above the documents (see
/// SettingsView), and when it should close along with them.
enum SettingsWindow {
    /// Set once SwiftUI has put Settings in a window; weak, so a closed
    /// window isn't kept around.
    static weak var current: NSWindow?

    /// Closing the last document window would leave floating Settings
    /// hovering over nothing, so they close with it. A minimized document
    /// still counts as open.
    static func shouldClose(
        whenClosing closing: NSWindow,
        among windows: [NSWindow],
        isOpen: (NSWindow) -> Bool = { $0.isVisible || $0.isMiniaturized }
    ) -> Bool {
        guard isDocumentWindow(closing) else { return false }
        return !windows.contains { $0 !== closing && isDocumentWindow($0) && isOpen($0) }
    }

    static func isDocumentWindow(_ window: NSWindow) -> Bool {
        !window.isSheet && window.windowController?.document != nil
    }
}
