import AppKit
import Testing
@testable import Lauda

/// Each open document keeps panes of its own; a tab only decides whose show.
@MainActor
@Suite(.serialized)
struct DocumentStackTests {
    private let workspace = Workspace()

    private func makeDocument(_ text: String) -> MarkdownDocument {
        let document = MarkdownDocument()
        document.text = text
        return document
    }

    /// A stack in a window, which is where panes come to life and where the
    /// keyboard has somewhere to go.
    private func makeStack() -> (DocumentStackView, NSWindow) {
        _ = NSApplication.shared
        let stack = DocumentStackView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 900, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = stack
        window.orderFrontRegardless()
        return (stack, window)
    }

    private func editor(in view: NSView?) -> EditorTextView? {
        guard let view else { return nil }
        if let editor = view as? EditorTextView { return editor }
        for subview in view.subviews {
            if let found = editor(in: subview) { return found }
        }
        return nil
    }

    /// Lets SwiftUI build the panes and the stack hand the keyboard over.
    /// Suspending (rather than spinning the run loop) is what lets work
    /// queued on the main queue run while a main-actor test waits.
    private func settle(until done: () -> Bool) async throws {
        for _ in 0..<150 where !done() {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func everyDocumentHasItsOwnPanesAndOnlyTheSelectedOnesShow() throws {
        let (stack, _) = makeStack()
        let first = makeDocument("# First")
        let second = makeDocument("# Second")

        stack.show([first, second], selected: second, in: workspace)

        let firstPanes = try #require(stack.panes(of: first))
        let secondPanes = try #require(stack.panes(of: second))
        #expect(firstPanes !== secondPanes)
        #expect(firstPanes.isHidden)
        #expect(!secondPanes.isHidden)
    }

    /// Nothing is rebuilt on a switch: the panes that come forward are the
    /// ones that went out of sight, text view and all.
    @Test func selectingATabBringsBackTheVeryPanesThatWereLeft() async throws {
        let (stack, _) = makeStack()
        let first = makeDocument("# First")
        let second = makeDocument("# Second")
        stack.show([first, second], selected: first, in: workspace)
        try await settle { editor(in: stack.panes(of: first)) != nil && editor(in: stack.panes(of: second)) != nil }
        let firstPanes = try #require(stack.panes(of: first))
        let firstEditor = try #require(editor(in: firstPanes))

        stack.show([first, second], selected: second, in: workspace)
        stack.show([first, second], selected: first, in: workspace)

        #expect(stack.panes(of: first) === firstPanes)
        #expect(editor(in: firstPanes) === firstEditor)
        #expect(!firstPanes.isHidden)
        #expect(stack.panes(of: second)?.isHidden == true)
    }

    /// Two documents never share a text view, so one's text, caret and undo
    /// can't end up in the other.
    @Test func eachDocumentTypesIntoItsOwnEditor() async throws {
        let (stack, _) = makeStack()
        let first = makeDocument("first text")
        let second = makeDocument("second text")
        stack.show([first, second], selected: first, in: workspace)
        try await settle { editor(in: stack.panes(of: first)) != nil && editor(in: stack.panes(of: second)) != nil }

        let firstEditor = try #require(editor(in: stack.panes(of: first)))
        let secondEditor = try #require(editor(in: stack.panes(of: second)))
        #expect(firstEditor !== secondEditor)
        #expect(firstEditor.string == "first text")
        #expect(secondEditor.string == "second text")

        secondEditor.insertText("!", replacementRange: NSRange(location: 0, length: 0))

        #expect(second.text == "!second text")
        #expect(first.text == "first text")
    }

    @Test func closingADocumentTakesItsPanesAway() {
        let (stack, _) = makeStack()
        let first = makeDocument("# First")
        let second = makeDocument("# Second")
        stack.show([first, second], selected: second, in: workspace)

        // The first tab closes while the second one shows.
        stack.show([second], selected: second, in: workspace)

        #expect(stack.panes(of: first) == nil)
        #expect(stack.panes(of: second)?.isHidden == false)
        #expect(stack.subviews.count == 1)
    }

    /// Typing must go on in the tab that was picked, never in one that is
    /// out of sight.
    @Test func theKeyboardFollowsTheTabInFront() async throws {
        let (stack, window) = makeStack()
        let first = makeDocument("first")
        let second = makeDocument("second")
        workspace.viewMode = .split

        stack.show([first, second], selected: first, in: workspace)
        try await settle { window.firstResponder === editor(in: stack.panes(of: first)) }
        #expect(window.firstResponder === editor(in: stack.panes(of: first)))

        stack.show([first, second], selected: second, in: workspace)
        try await settle { window.firstResponder === editor(in: stack.panes(of: second)) }
        #expect(window.firstResponder === editor(in: stack.panes(of: second)))
        #expect(window.firstResponder !== editor(in: stack.panes(of: first)))
    }
}
