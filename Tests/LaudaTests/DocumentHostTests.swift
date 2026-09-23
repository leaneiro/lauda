import AppKit
import Testing
@testable import Lauda

/// A document has no window of its own: opening, showing and closing it are
/// things the window does with its tabs. With a stand-in for the window,
/// those paths can be exercised without the real one.
///
/// Closing an edited document is left out: AppKit answers `canClose` with a
/// sheet and waits for it, which in a test with no window never returns.
@MainActor
@Suite(.serialized)
final class DocumentHostTests {
    private final class HostSpy: DocumentHost {
        var added: [MarkdownDocument] = []
        var selected: [MarkdownDocument] = []
        var closing: [MarkdownDocument] = []
        var saves = 0

        func add(_ document: MarkdownDocument) { added.append(document) }
        func select(_ document: MarkdownDocument) { selected.append(document) }
        func willClose(_ document: MarkdownDocument) { closing.append(document) }
        func documentDidSave() { saves += 1 }
    }

    /// The stand-in is in place only while the test runs: a deinit would run
    /// wherever the suite is released, and the window is main-actor bound.
    private func withHost(_ body: (HostSpy) -> Void) {
        let host = HostSpy()
        MarkdownDocument.host = host
        defer { MarkdownDocument.host = nil }
        body(host)
    }

    @Test func openingADocumentAsksForATab() {
        withHost { host in
            let document = MarkdownDocument()
            document.makeWindowControllers()
            #expect(host.added.count == 1)
            #expect(host.added.first === document)
            #expect(host.selected.isEmpty)
        }
    }

    /// Opening a file that is already open asks its document to show itself,
    /// which here means bringing its tab forward.
    @Test func showingADocumentBringsItsTabForward() {
        withHost { host in
            let document = MarkdownDocument()
            document.showWindows()
            #expect(host.selected.count == 1)
            #expect(host.selected.first === document)
        }
    }

    /// The window has to hear of a close before AppKit acts on it: a document
    /// closes the windows it holds, and the one window must be left with a
    /// document that stays.
    @Test func closingTellsTheWindowFirst() {
        withHost { host in
            let document = MarkdownDocument()
            document.close()
            #expect(host.closing.count == 1)
            #expect(host.closing.first === document)
        }
    }

    /// The window's close button closes every tab, not only the one the
    /// window is with. The real button is clicked: on macOS 27 it sends a
    /// private action of the window, not `performClose`, so overriding that
    /// did nothing.
    @Test func theCloseButtonClosesEveryDocument() async throws {
        let host = HostSpy()
        MarkdownDocument.host = host
        defer { MarkdownDocument.host = nil }
        _ = NSApplication.shared
        let first = MarkdownDocument()
        let second = MarkdownDocument()
        NSDocumentController.shared.addDocument(first)
        NSDocumentController.shared.addDocument(second)
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 400, height: 300),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        // Held here as the workspace holds it, not only by the document.
        let windowController = NSWindowController(window: window)
        first.addWindowController(windowController)

        window.standardWindowButton(.closeButton)?.performClick(nil)
        for _ in 0..<50 where host.closing.count < 2 {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(host.closing.contains { $0 === first })
        #expect(host.closing.contains { $0 === second })
        #expect(NSDocumentController.shared.documents.isEmpty)
        withExtendedLifetime(windowController) {}
    }

    // MARK: - Rename and Revert to Saved

    // They ask in sheets of their own, which work with the title hidden
    // behind the tabs. The sheets are real: the test reads the one attached
    // to the window, answers it, and looks at the file. Here rather than in
    // a suite of their own, since the stand-in for the window is shared by
    // every test that closes, renames or reverts, and these ones wait.

    /// A document opened from a file in a folder of its own, in a window of
    /// its own off screen.
    private func open(_ text: String, named name: String) throws -> (MarkdownDocument, NSWindow, NSWindowController, URL) {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lauda-commands-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        let document = try MarkdownDocument(contentsOf: url, ofType: "net.daringfireball.markdown")
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 600, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let controller = NSWindowController(window: window)
        document.addWindowController(controller)
        return (document, window, controller, folder)
    }

    private func sheet(of window: NSWindow) async throws -> NSWindow {
        for _ in 0..<50 where window.attachedSheet == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        // Long enough for the sheet to hand its field the keyboard.
        try await Task.sleep(for: .milliseconds(50))
        return try #require(window.attachedSheet)
    }

    @Test func renameAsksForTheNameAndKeepsTheExtension() async throws {
        MarkdownDocument.host = HostSpy()
        defer { MarkdownDocument.host = nil }
        let (document, window, controller, folder) = try open("# Notes", named: "notes.md")
        defer { try? FileManager.default.removeItem(at: folder) }

        document.rename(nil)
        let sheet = try await sheet(of: window)
        let textView = try #require(sheet.firstResponder as? NSTextView)
        #expect(textView.string == "notes.md")
        // The name is selected without its extension, as the Finder does.
        #expect(textView.selectedRange() == NSRange(location: 0, length: 5))
        textView.insertText("ideas", replacementRange: textView.selectedRange())
        window.endSheet(sheet, returnCode: .alertFirstButtonReturn)
        for _ in 0..<50 where document.fileURL?.lastPathComponent != "ideas.md" {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(document.fileURL?.lastPathComponent == "ideas.md")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("ideas.md").path))
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("notes.md").path))
        withExtendedLifetime(controller) {}
    }

    /// Revert to Saved brings back the text as the file was opened, after
    /// asking; the Versions browser AppKit would use can't find a window.
    @Test func revertToSavedBringsBackTheTextAsOpened() async throws {
        MarkdownDocument.host = HostSpy()
        defer { MarkdownDocument.host = nil }
        let (document, window, controller, folder) = try open("as opened", named: "revert.md")
        defer { try? FileManager.default.removeItem(at: folder) }
        document.edit("changed since")

        document.revertToSaved(nil)
        let sheet = try await sheet(of: window)
        window.endSheet(sheet, returnCode: .alertFirstButtonReturn)
        for _ in 0..<50 where document.text != "as opened" {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(document.text == "as opened")
        withExtendedLifetime(controller) {}
    }

    /// Nothing to go back to: no question is asked.
    @Test func revertToSavedAsksNothingWhenTheTextIsAsSaved() async throws {
        MarkdownDocument.host = HostSpy()
        defer { MarkdownDocument.host = nil }
        let (document, window, controller, folder) = try open("as opened", named: "same.md")
        defer { try? FileManager.default.removeItem(at: folder) }

        document.revertToSaved(nil)
        try await Task.sleep(for: .milliseconds(100))

        #expect(window.attachedSheet == nil)
        withExtendedLifetime(controller) {}
    }
}
