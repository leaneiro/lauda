import AppKit

/// Lightweight regex-based markdown highlighting for the editor pane.
/// Re-highlights the whole document on each change; skipped above a size
/// threshold to keep typing responsive on very large files.
final class MarkdownHighlighter {
    private static let maxHighlightLength = 150_000

    var baseFont: NSFont = .monospacedSystemFont(ofSize: 14, weight: .regular) {
        didSet {
            boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
            italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
        }
    }
    private var boldFont: NSFont = .monospacedSystemFont(ofSize: 14, weight: .bold)
    private var italicFont: NSFont = .monospacedSystemFont(ofSize: 14, weight: .regular)

    var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.25
        return [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
    }

    private static func regex(_ pattern: String, options: NSRegularExpression.Options = [.anchorsMatchLines]) -> NSRegularExpression {
        // Patterns are static and known-valid; a failure here is a programmer error.
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let headingRegex = regex(#"^#{1,6}[ \t].*$"#)
    private static let listMarkerRegex = regex(#"^[ \t]*(?:[-*+]|\d{1,3}[.)])[ \t]"#)
    private static let blockquoteRegex = regex(#"^[ \t]*>.*$"#)
    private static let boldRegex = regex(#"(?:\*\*[^*\n]+\*\*|__[^_\n]+__)"#)
    private static let italicRegex = regex(#"(?<![\w*])\*(?!\*)[^*\n]+\*(?!\*)|(?<![\w_])_(?!_)[^_\n]+_(?!_)"#)
    private static let linkRegex = regex(#"\[([^\]\n]*)\]\(([^)\n]*)\)"#)
    private static let inlineCodeRegex = regex(#"`[^`\n]+`"#)
    private static let fencedCodeRegex = regex(#"^(```|~~~)[^\n]*\n[\s\S]*?^\1[ \t]*$"#)

    func highlight(_ textStorage: NSTextStorage?) {
        guard let textStorage else { return }
        let text = textStorage.string as NSString
        guard text.length <= Self.maxHighlightLength else { return }

        let fullRange = NSRange(location: 0, length: text.length)
        textStorage.beginEditing()
        textStorage.setAttributes(baseAttributes, range: fullRange)

        apply(Self.listMarkerRegex, in: text) { match in
            textStorage.addAttribute(.foregroundColor, value: NSColor.systemIndigo, range: match.range)
        }
        apply(Self.blockquoteRegex, in: text) { match in
            textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range)
        }
        apply(Self.boldRegex, in: text) { match in
            textStorage.addAttribute(.font, value: self.boldFont, range: match.range)
        }
        apply(Self.italicRegex, in: text) { match in
            textStorage.addAttribute(.font, value: self.italicFont, range: match.range)
        }
        apply(Self.linkRegex, in: text) { match in
            textStorage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: match.range(at: 1))
            textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: match.range(at: 2))
        }
        apply(Self.headingRegex, in: text) { match in
            textStorage.addAttribute(.font, value: self.boldFont, range: match.range)
            textStorage.addAttribute(.foregroundColor, value: NSColor.systemIndigo, range: match.range)
        }
        apply(Self.inlineCodeRegex, in: text) { match in
            textStorage.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: match.range)
        }
        apply(Self.fencedCodeRegex, in: text) { match in
            textStorage.setAttributes(self.baseAttributes, range: match.range)
            textStorage.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: match.range)
        }

        textStorage.endEditing()
    }

    private func apply(_ regex: NSRegularExpression, in text: NSString, _ action: (NSTextCheckingResult) -> Void) {
        let fullRange = NSRange(location: 0, length: text.length)
        regex.enumerateMatches(in: text as String, range: fullRange) { match, _, _ in
            if let match { action(match) }
        }
    }
}
