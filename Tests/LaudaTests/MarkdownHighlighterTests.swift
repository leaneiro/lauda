import AppKit
import Testing
@testable import Lauda

/// What the editor pane shows as you write: the markers keep their place in
/// the text and take the styling with them.
@MainActor
struct MarkdownHighlighterTests {
    private func highlighted(_ text: String) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        MarkdownHighlighter().highlight(storage)
        return storage
    }

    private func colour(_ storage: NSTextStorage, at location: Int) -> NSColor? {
        storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
    }

    private func isBold(_ storage: NSTextStorage, at location: Int) -> Bool {
        let font = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        return font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
    }

    private func hasLine(_ key: NSAttributedString.Key, _ storage: NSTextStorage, at location: Int) -> Bool {
        (storage.attribute(key, at: location, effectiveRange: nil) as? Int) == NSUnderlineStyle.single.rawValue
    }

    @Test func aHeadingIsBoldAndInTheAccentColour() {
        let storage = highlighted("# Title\n\nplain\n")
        #expect(isBold(storage, at: 2))
        #expect(colour(storage, at: 2) == .systemIndigo)
        #expect(colour(storage, at: 9) == .labelColor)
        #expect(!isBold(storage, at: 9))
    }

    @Test func inlineCodeIsColouredWithItsBackticks() {
        let storage = highlighted("run `code` now")
        #expect(colour(storage, at: 4) == .systemPurple)
        #expect(colour(storage, at: 6) == .systemPurple)
        #expect(colour(storage, at: 0) == .labelColor)
    }

    @Test func strikethroughAndUnderlineAreShownAsThemselves() {
        let storage = highlighted("a ~~struck~~ and <u>lined</u> b")
        #expect(hasLine(.strikethroughStyle, storage, at: 4))
        #expect(!hasLine(.strikethroughStyle, storage, at: 0))
        #expect(hasLine(.underlineStyle, storage, at: 20))
        #expect(!hasLine(.underlineStyle, storage, at: 0))
    }

    @Test func listMarkersAndQuotesKeepTheirOwnColours() {
        let storage = highlighted("- item\n> quoted\n")
        #expect(colour(storage, at: 0) == .systemIndigo)
        #expect(colour(storage, at: 3) == .labelColor)
        #expect(colour(storage, at: 7) == .secondaryLabelColor)
    }

    @Test func aLinksTextAndItsDestinationDiffer() {
        let storage = highlighted("see [docs](https://example.com) now")
        #expect(colour(storage, at: 5) == .linkColor)
        #expect(colour(storage, at: 12) == .tertiaryLabelColor)
    }

    /// Inside a fenced block everything is code, whatever it would be outside.
    @Test func aFencedBlockOverridesWhatIsInsideIt() {
        let storage = highlighted("```\n# not a heading\n- not a list\n```\n")
        #expect(colour(storage, at: 6) == .systemPurple)
        #expect(!isBold(storage, at: 6))
        #expect(colour(storage, at: 22) == .systemPurple)
    }

    @Test func anUnclosedFenceRunsToTheEnd() {
        let storage = highlighted("text\n```\n# inside\n")
        #expect(colour(storage, at: 0) == .labelColor)
        #expect(colour(storage, at: 11) == .systemPurple)
    }

    /// Typing restyles the edited lines, which is what keeps the scroll
    /// position steady in a long document.
    @Test func highlightingARangeLeavesTheRestAsItWas() {
        let storage = NSTextStorage(string: "# Title\n\n`code`\n")
        let highlighter = MarkdownHighlighter()
        highlighter.highlight(storage)
        storage.setAttributes(highlighter.baseAttributes, range: NSRange(location: 9, length: 6))
        highlighter.highlight(storage, in: NSRange(location: 9, length: 6))
        #expect(colour(storage, at: 9) == .systemPurple)
        #expect(colour(storage, at: 2) == .systemIndigo)
    }

    // MARK: - Where code is

    @Test(arguments: [
        ("inside a fenced block", "```\narrow -> here\n```\n", 10, true),
        ("after an opening backtick", "an `inline -> span`", 11, true),
        ("after a closed span", "an `inline` -> plain", 13, false),
        ("plain prose", "an arrow -> here", 9, false),
    ])
    func codeIsWhereTheMarkersSayItIs(_ what: String, text: String, location: Int, expected: Bool) {
        #expect(MarkdownHighlighter().isInsideCode(at: location, in: text as NSString) == expected, "\(what)")
    }
}
