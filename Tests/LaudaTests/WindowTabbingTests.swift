import AppKit
import Testing
@testable import Lauda

/// Window tabbing is off for the whole app, which is also what keeps
/// "Show Tab Bar" and "Show All Tabs" out of the menus.
@MainActor
@Suite(.serialized)
struct WindowTabbingTests {
    @Test func launchingTurnsWindowTabbingOff() {
        // Launching also applies the stored appearance, which needs a real
        // NSApp: a test process has none until it asks for one.
        _ = NSApplication.shared
        NSWindow.allowsAutomaticWindowTabbing = true
        let delegate = AppDelegate()

        delegate.applicationWillFinishLaunching(
            Notification(name: NSApplication.willFinishLaunchingNotification))

        #expect(NSWindow.allowsAutomaticWindowTabbing == false)
    }
}
