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
}
