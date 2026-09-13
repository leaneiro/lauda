import AppKit
import Testing
@testable import Lauda

@MainActor
struct WindowConfiguratorTests {
    /// Settings rely on this to float: the adjustment must reach the window
    /// as soon as the view is placed in it.
    @Test func configuresTheWindowItLandsIn() {
        var configured: NSWindow?
        let view = WindowConfigurator.ConfiguratorView { configured = $0 }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled], backing: .buffered, defer: true)
        #expect(configured == nil)

        window.contentView?.addSubview(view)
        #expect(configured === window)
    }
}
