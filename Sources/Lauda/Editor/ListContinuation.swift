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

    /// What Tab or Shift-Tab does on a list line.
    enum IndentOutcome: Equatable {
        /// Not a list line: the key does whatever it does elsewhere.
        case notAList
        /// A list line already at the left edge: the key is spoken for, and
        /// nothing moves.
        case nothingToRemove
        case edit(TextEdit)
    }

    /// The line the caret is on, without its newline, and where it starts.
    private static func line(in text: NSString, at location: Int) -> (range: NSRange, text: String) {
        let range = text.lineRange(for: NSRange(location: location, length: 0))
        var line = text.substring(with: range)
        if line.hasSuffix("\n") { line.removeLast() }
        return (range, line)
    }

    /// What Return does on a list line: nothing, so the newline is inserted
    /// as usual, or the edit that ends or continues the list.
    static func newlineEdit(in text: NSString, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let (lineRange, lineText) = line(in: text, at: selection.location)
        switch newlineAction(forLine: lineText, caretOffset: selection.location - lineRange.location) {
        case .none:
            return nil
        case .endList(let prefixLength):
            return TextEdit(
                range: NSRange(location: lineRange.location, length: prefixLength),
                replacement: "",
                selection: NSRange(location: lineRange.location, length: 0)
            )
        case .continueList(let insertion):
            return TextEdit(
                range: selection,
                replacement: insertion,
                selection: NSRange(location: selection.location + (insertion as NSString).length, length: 0)
            )
        }
    }

    /// One step of indent added or taken off a list line, the step being the
    /// width of its own marker so nested items line up under it. Only from
    /// inside the prefix: further along the line, Tab is a tab.
    static func indent(in text: NSString, selection: NSRange, outdent: Bool) -> IndentOutcome {
        let (lineRange, lineText) = line(in: text, at: selection.location)
        guard let info = lineInfo(forLine: lineText),
              selection.location - lineRange.location <= info.prefixLength
        else { return .notAList }

        guard outdent else {
            let spaces = String(repeating: " ", count: info.indentUnit)
            return .edit(TextEdit(
                range: NSRange(location: lineRange.location, length: 0),
                replacement: spaces,
                selection: NSRange(location: selection.location + info.indentUnit, length: 0)
            ))
        }

        // One step back, counting spaces; a tab is a step on its own.
        var removable = 0
        while removable < info.indentUnit, lineRange.location + removable < text.length {
            let character = text.character(at: lineRange.location + removable)
            if character == 0x20 { removable += 1 } else if character == 0x09 { removable += 1; break } else { break }
        }
        guard removable > 0 else { return .nothingToRemove }
        return .edit(TextEdit(
            range: NSRange(location: lineRange.location, length: removable),
            replacement: "",
            selection: NSRange(location: max(selection.location - removable, lineRange.location), length: 0)
        ))
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
