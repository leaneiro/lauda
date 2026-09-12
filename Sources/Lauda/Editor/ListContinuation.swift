import Foundation

/// Pure logic for continuing/indenting markdown lists while typing.
enum ListContinuation {
    struct LineInfo {
        /// UTF-16 length of the full list prefix (indent + marker + spaces + task box).
        let prefixLength: Int
        /// UTF-16 length of one indent step (the marker + trailing spaces width).
        let indentUnit: Int
    }

    enum NewlineAction: Equatable {
        case none
        /// Empty item: remove its prefix and swallow the newline (ends the list).
        case endList(prefixLength: Int)
        /// Item with content: insert newline + the next item's prefix.
        case continueList(insertion: String)
    }

    // 1: indent, 2: bullet, 3: number, 4: number delimiter, 5: spaces, 6: task box
    private static let prefixRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)(?:([-*+])|(\d{1,9})([.)]))([ \t]+)(\[[ xX]\][ \t]+)?"#
    )

    private static func match(in line: String) -> (NSTextCheckingResult, NSString)? {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = prefixRegex.firstMatch(in: line, range: range) else { return nil }
        return (match, nsLine)
    }

    static func lineInfo(forLine line: String) -> LineInfo? {
        guard let (match, _) = match(in: line) else { return nil }
        let taskLength = match.range(at: 6).location != NSNotFound ? match.range(at: 6).length : 0
        return LineInfo(
            prefixLength: match.range.length,
            indentUnit: match.range.length - match.range(at: 1).length - taskLength
        )
    }

    /// `line` must not include its trailing newline; `caretOffset` is UTF-16.
    static func newlineAction(forLine line: String, caretOffset: Int) -> NewlineAction {
        guard let (match, nsLine) = match(in: line) else { return .none }
        let prefixLength = match.range.length
        guard caretOffset >= prefixLength else { return .none }

        let content = nsLine.substring(from: prefixLength).trimmingCharacters(in: .whitespaces)
        if content.isEmpty {
            return .endList(prefixLength: prefixLength)
        }

        let indent = nsLine.substring(with: match.range(at: 1))
        let spaces = nsLine.substring(with: match.range(at: 5))
        var prefix: String
        if match.range(at: 2).location != NSNotFound {
            prefix = indent + nsLine.substring(with: match.range(at: 2)) + spaces
        } else {
            let number = Int(nsLine.substring(with: match.range(at: 3))) ?? 0
            let delimiter = nsLine.substring(with: match.range(at: 4))
            prefix = indent + "\(number + 1)" + delimiter + spaces
        }
        if match.range(at: 6).location != NSNotFound {
            prefix += "[ ] "
        }
        return .continueList(insertion: "\n" + prefix)
    }
}

/// Notion-style typing substitutions (e.g. `->` becomes `→` as you type).
enum TypingSubstitutions {
    private static let pairs: [(prior: String, typed: String, result: String)] = [
        ("-", ">", "→"),
        ("<", "-", "←"),
    ]

    /// If typing `replacement` into `affectedRange` completes a known pair,
    /// returns the wider range to replace and the substituted string.
    static func substitution(
        in text: NSString,
        affectedRange: NSRange,
        replacement: String
    ) -> (range: NSRange, replacement: String)? {
        for pair in pairs where replacement == pair.typed {
            let priorLength = (pair.prior as NSString).length
            let start = affectedRange.location - priorLength
            guard start >= 0, NSMaxRange(affectedRange) <= text.length else { continue }
            if text.substring(with: NSRange(location: start, length: priorLength)) == pair.prior {
                return (
                    NSRange(location: start, length: priorLength + affectedRange.length),
                    pair.result
                )
            }
        }
        return nil
    }
}
