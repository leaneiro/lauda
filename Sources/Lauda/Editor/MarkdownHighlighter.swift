import AppKit

/// Lightweight regex-based markdown highlighting for the editor pane.
/// Skipped above a size threshold to keep typing responsive on huge files.
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
    private static let fenceLineRegex = regex(#"^[ \t]{0,3}(?:`{3,}|~{3,})"#)

    /// Restyles `editedRange` (extended to whole lines) or, when nil, the
    /// whole document. Restricting the range on every keystroke keeps layout
    /// invalidation local — restyling everything made the scroll position
    /// jump. Pass precomputed `fenceRanges` to avoid a second fence scan.
    func highlight(
        _ textStorage: NSTextStorage?,
        in editedRange: NSRange? = nil,
        fenceRanges: [NSRange]? = nil
    ) {
        guard let textStorage else { return }
        let text = textStorage.string as NSString
        guard text.length <= Self.maxHighlightLength else { return }

        let range: NSRange
        if let editedRange {
            let location = min(editedRange.location, text.length)
            let length = min(editedRange.length, text.length - location)
            range = text.lineRange(for: NSRange(location: location, length: length))
        } else {
            range = NSRange(location: 0, length: text.length)
        }
        let fences = fenceRanges ?? fencedBlockRanges(in: text)

        textStorage.beginEditing()
        textStorage.setAttributes(baseAttributes, range: range)

        apply(Self.listMarkerRegex, in: text, range: range) { match in
            textStorage.addAttribute(.foregroundColor, value: NSColor.systemIndigo, range: match.range)
        }
        apply(Self.blockquoteRegex, in: text, range: range) { match in
            textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range)
        }
        apply(Self.boldRegex, in: text, range: range) { match in
            textStorage.addAttribute(.font, value: self.boldFont, range: match.range)
        }
        apply(Self.italicRegex, in: text, range: range) { match in
            textStorage.addAttribute(.font, value: self.italicFont, range: match.range)
        }
        apply(Self.linkRegex, in: text, range: range) { match in
            textStorage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: match.range(at: 1))
            textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: match.range(at: 2))
        }
        apply(Self.headingRegex, in: text, range: range) { match in
            textStorage.addAttribute(.font, value: self.boldFont, range: match.range)
            textStorage.addAttribute(.foregroundColor, value: NSColor.systemIndigo, range: match.range)
        }
        apply(Self.inlineCodeRegex, in: text, range: range) { match in
            textStorage.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: match.range)
        }
        for fence in fences {
            let intersection = NSIntersectionRange(fence, range)
            guard intersection.length > 0 else { continue }
            textStorage.setAttributes(baseAttributes, range: intersection)
            textStorage.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: intersection)
        }

        textStorage.endEditing()
    }

    /// Single linear pass pairing ```/~~~ fence lines; an unclosed fence runs
    /// to the end of the document (avoids the pathological backtracking a
    /// multiline regex has on documents with orphan fences). Also used by the
    /// editor to suppress typing substitutions inside code.
    func fencedBlockRanges(in text: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var openLocation: Int?
        var location = 0
        while location < text.length {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            let isFenceLine = Self.fenceLineRegex.firstMatch(
                in: text as String,
                options: [.anchored],
                range: lineRange
            ) != nil
            if isFenceLine {
                if let start = openLocation {
                    ranges.append(NSRange(location: start, length: NSMaxRange(lineRange) - start))
                    openLocation = nil
                } else {
                    openLocation = lineRange.location
                }
            }
            location = NSMaxRange(lineRange)
        }
        if let start = openLocation {
            ranges.append(NSRange(location: start, length: text.length - start))
        }
        return ranges
    }

    private func apply(
        _ regex: NSRegularExpression,
        in text: NSString,
        range: NSRange,
        _ action: (NSTextCheckingResult) -> Void
    ) {
        regex.enumerateMatches(in: text as String, range: range) { match, _, _ in
            if let match { action(match) }
        }
    }
}
