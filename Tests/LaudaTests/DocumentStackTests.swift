import AppKit
import Testing
@testable import Lauda

/// Each open document keeps panes of its own; a tab only decides whose show.
/// The panes come to life in a window here, chain and all, which draws.
@MainActor
@Suite(.serialized, .enabled(if: TestMachine.drawsWithMetal, "the panes draw through Metal"))
final class DocumentStackTests {
    /// Its own preferences, so the tests never write to the reader's: the
    /// view mode and the open session are stored the moment they change.
    private let workspace = Workspace(defaults: TestDefaults())

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

    /// Typing hands the document a Swift string of its own, not the text
    /// view's lazy bridge to its storage, whose every comparison walked the
    /// whole text: in a 100 KB file typing hitched.
    @Test func typingHandsTheDocumentANativeString() async throws {
        let (stack, _) = makeStack()
        let document = makeDocument("text")
        stack.show([document], selected: document, in: workspace)
        try await settle { editor(in: stack.panes(of: document)) != nil }
        let textView = try #require(editor(in: stack.panes(of: document)))

        textView.insertText("ação ", replacementRange: NSRange(location: 0, length: 0))

        #expect(document.text == "ação text")
        #expect(document.text.utf8.withContiguousStorageIfAvailable { _ in true } == true)
    }

    /// Text from elsewhere (a revert, a file changed on disk) still reaches
    /// the editor after typing: only what the editor published itself is
    /// taken as already there.
    @Test func textFromElsewhereStillReachesTheEditorAfterTyping() async throws {
        let (stack, _) = makeStack()
        let document = makeDocument("text")
        stack.show([document], selected: document, in: workspace)
        try await settle { editor(in: stack.panes(of: document)) != nil }
        let textView = try #require(editor(in: stack.panes(of: document)))
        textView.insertText("typed ", replacementRange: NSRange(location: 0, length: 0))

        document.text = "from elsewhere"
        try await settle { textView.string == "from elsewhere" }

        #expect(textView.string == "from elsewhere")
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

    /// A stack in a window beside a view that holds the keyboard, as the tab
    /// strip does when the tabs are walked with the arrows.
    private func makeStackBesideTheTabs() -> (DocumentStackView, KeyboardHolder, NSWindow) {
        _ = NSApplication.shared
        let stack = DocumentStackView(frame: NSRect(x: 0, y: 40, width: 900, height: 560))
        let tabs = KeyboardHolder(frame: NSRect(x: 0, y: 0, width: 900, height: 40))
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        content.addSubview(stack)
        content.addSubview(tabs)
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 900, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = content
        window.orderFrontRegardless()
        return (stack, tabs, window)
    }

    /// A tab picked with the arrows leaves the keyboard on the tabs, so the
    /// next arrow still reaches them.
    @Test func theKeyboardStaysOnTheTabsWalkedWithTheArrows() async throws {
        let (stack, tabs, window) = makeStackBesideTheTabs()
        let first = makeDocument("first")
        let second = makeDocument("second")
        workspace.viewMode = .split
        stack.show([first, second], selected: first, in: workspace)
        try await settle { editor(in: stack.panes(of: first)) != nil && editor(in: stack.panes(of: second)) != nil }

        window.makeFirstResponder(tabs)
        stack.show([first, second], selected: second, in: workspace, keyboard: .stays)
        // Long enough for the panes' own attempts at the keyboard to have run.
        try await Task.sleep(for: .milliseconds(300))

        #expect(window.firstResponder === tabs)
    }

    /// A tab picked otherwise (a click, the menu) takes the keyboard into its
    /// document, wherever the keyboard was, so typing goes on there.
    @Test func theKeyboardFollowsATabPickedOtherwise() async throws {
        let (stack, tabs, window) = makeStackBesideTheTabs()
        let first = makeDocument("first")
        let second = makeDocument("second")
        workspace.viewMode = .split
        stack.show([first, second], selected: first, in: workspace)
        try await settle { editor(in: stack.panes(of: first)) != nil && editor(in: stack.panes(of: second)) != nil }

        window.makeFirstResponder(tabs)
        stack.show([first, second], selected: second, in: workspace)
        try await settle { window.firstResponder === editor(in: stack.panes(of: second)) }

        #expect(window.firstResponder === editor(in: stack.panes(of: second)))
    }
}

/// Stands in for the tab strip: a view outside the panes that takes the
/// keyboard.
private final class KeyboardHolder: NSView {
    override var acceptsFirstResponder: Bool { true }
}
