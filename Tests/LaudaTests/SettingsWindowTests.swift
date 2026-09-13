import AppKit
import Testing
@testable import Lauda

@MainActor
struct SettingsWindowTests {
    private func makeWindow(for document: NSDocument? = nil) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled], backing: .buffered, defer: true)
        if let document {
            document.addWindowController(NSWindowController(window: window))
        }
        return window
    }

    @Test func closeWithTheLastDocumentWindow() {
        let document = NSDocument()
        let last = makeWindow(for: document)
        let settings = makeWindow()
        #expect(SettingsWindow.shouldClose(whenClosing: last, among: [last, settings], isOpen: { _ in true }))
    }

    @Test func stayWhileAnotherDocumentIsOpen() {
        let first = NSDocument(), second = NSDocument()
        let closing = makeWindow(for: first)
        let other = makeWindow(for: second)
        #expect(!SettingsWindow.shouldClose(whenClosing: closing, among: [closing, other], isOpen: { _ in true }))
    }

    @Test func closingSomethingOtherThanADocumentChangesNothing() {
        let document = NSDocument()
        let panel = makeWindow()
        let open = makeWindow(for: document)
        #expect(!SettingsWindow.shouldClose(whenClosing: panel, among: [panel, open], isOpen: { _ in false }))
    }
}
