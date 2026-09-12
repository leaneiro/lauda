import Foundation

/// A text replacement and the selection after it, worked out without the text
/// view, so the formatting rules can be tested on plain strings.
struct TextEdit: Equatable {
    var range: NSRange
    var replacement: String
    var selection: NSRange
}

/// ⌘B / ⌘I (markers) and ⌘K (links) as plain text rules.
enum InlineFormatting {
    /// Toggles `marker` (e.g. "**") around the selection. With nothing
    /// selected it applies to `wordRange`, the word under the caret; outside
    /// a word it inserts an empty pair with the caret inside.
    static func toggle(_ marker: String, in text: NSString, selection: NSRange, wordRange: NSRange) -> TextEdit {
        var range = selection
        let markerLength = (marker as NSString).length

        if range.length == 0 {
            let word = wordRange.length > 0 ? text.substring(with: wordRange) : ""
            if word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return TextEdit(
                    range: range,
                    replacement: marker + marker,
                    selection: NSRange(location: range.location + markerLength, length: 0)
                )
            }
            range = wordRange
        }

        let selected = text.substring(with: range)
        let selectedLength = (selected as NSString).length

        // Unwrap when the markers are inside the selection…
        if selected.hasPrefix(marker), selected.hasSuffix(marker),
           selectedLength >= markerLength * 2 + 1 {
            let inner = (selected as NSString).substring(
                with: NSRange(location: markerLength, length: selectedLength - markerLength * 2)
            )
            return TextEdit(
                range: range,
                replacement: inner,
                selection: NSRange(location: range.location, length: (inner as NSString).length)
            )
        }
        // …or just outside it.
        let before = NSRange(location: range.location - markerLength, length: markerLength)
        let after = NSRange(location: NSMaxRange(range), length: markerLength)
        if before.location >= 0, NSMaxRange(after) <= text.length,
           text.substring(with: before) == marker, text.substring(with: after) == marker {
            return TextEdit(
                range: NSRange(location: before.location, length: range.length + markerLength * 2),
                replacement: selected,
                selection: NSRange(location: before.location, length: range.length)
            )
        }
        // Otherwise wrap.
        return TextEdit(
            range: range,
            replacement: marker + selected + marker,
            selection: NSRange(location: range.location + markerLength, length: range.length)
        )
    }

    /// ⌘K: `[selection](url)`, taking the URL from the clipboard when it
    /// holds one. The caret lands where the next thing to type goes.
    static func link(in text: NSString, selection range: NSRange, clipboard: String?) -> TextEdit {
        let selected = range.length > 0 ? text.substring(with: range) : ""
        let pasted = clipboard?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let url = EditorTextView.isLikelyURL(pasted) ? pasted : ""

        let selectedLength = (selected as NSString).length
        let newSelection: NSRange
        if selected.isEmpty {
            newSelection = NSRange(location: range.location + 1, length: 0)
        } else if url.isEmpty {
            newSelection = NSRange(location: range.location + selectedLength + 3, length: 0)
        } else {
            newSelection = NSRange(
                location: range.location + selectedLength + 3,
                length: (url as NSString).length
            )
        }
        return TextEdit(range: range, replacement: "[\(selected)](\(url))", selection: newSelection)
    }
}
