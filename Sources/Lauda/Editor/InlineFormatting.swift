import Foundation

/// A text replacement and the selection after it, worked out without the text
/// view, so the formatting rules can be tested on plain strings.
struct TextEdit: Equatable {
    var range: NSRange
    var replacement: String
    var selection: NSRange
}

/// ⌘B / ⌘I / ⌘U / ⇧⌘X (markers) and ⌘K (links) as plain text rules.
enum InlineFormatting {
    /// Toggles `marker` (e.g. "**") around the selection.
    static func toggle(_ marker: String, in text: NSString, selection: NSRange, wordRange: NSRange) -> TextEdit {
        toggle(marker, marker, in: text, selection: selection, wordRange: wordRange)
    }

    /// Toggles `opening` … `closing` around the selection. Markdown's markers
    /// are the same on both sides; underline has no marker of its own and
    /// takes the `<u>` tags the preview lets through. With nothing selected
    /// the change applies to `wordRange`, the word under the caret; outside a
    /// word it inserts an empty pair with the caret inside.
    static func toggle(
        _ opening: String, _ closing: String, in text: NSString, selection: NSRange, wordRange: NSRange
    ) -> TextEdit {
        var range = selection
        let openingLength = (opening as NSString).length
        let closingLength = (closing as NSString).length

        if range.length == 0 {
            let word = wordRange.length > 0 ? text.substring(with: wordRange) : ""
            if word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return TextEdit(
                    range: range,
                    replacement: opening + closing,
                    selection: NSRange(location: range.location + openingLength, length: 0)
                )
            }
            range = wordRange
        }

        let selected = text.substring(with: range)
        let selectedLength = (selected as NSString).length

        // Unwrap when the markers are inside the selection…
        if selected.hasPrefix(opening), selected.hasSuffix(closing),
           selectedLength >= openingLength + closingLength + 1 {
            let inner = (selected as NSString).substring(
                with: NSRange(location: openingLength, length: selectedLength - openingLength - closingLength)
            )
            return TextEdit(
                range: range,
                replacement: inner,
                selection: NSRange(location: range.location, length: (inner as NSString).length)
            )
        }
        // …or just outside it.
        let before = NSRange(location: range.location - openingLength, length: openingLength)
        let after = NSRange(location: NSMaxRange(range), length: closingLength)
        if before.location >= 0, NSMaxRange(after) <= text.length,
           text.substring(with: before) == opening, text.substring(with: after) == closing {
            return TextEdit(
                range: NSRange(location: before.location, length: range.length + openingLength + closingLength),
                replacement: selected,
                selection: NSRange(location: before.location, length: range.length)
            )
        }
        // Otherwise wrap.
        return TextEdit(
            range: range,
            replacement: opening + selected + closing,
            selection: NSRange(location: range.location + openingLength, length: range.length)
        )
    }

    /// Pasting a URL over a selection makes a link of the selection instead
    /// of replacing it. Nothing to do — and so the ordinary paste — when the
    /// clipboard holds no URL, when nothing is selected, when the selection
    /// spans lines, or when it is itself a URL (where replacing is what the
    /// reader means).
    static func linkFromPaste(in text: NSString, selection: NSRange, clipboard: String?) -> TextEdit? {
        guard selection.length > 0 else { return nil }
        let url = (clipboard ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard EditorTextView.isLikelyURL(url) else { return nil }
        let selected = text.substring(with: selection)
        guard !selected.contains("\n"),
              !EditorTextView.isLikelyURL(selected.trimmingCharacters(in: .whitespaces)) else { return nil }
        let replacement = "[\(selected)](\(url))"
        return TextEdit(
            range: selection,
            replacement: replacement,
            selection: NSRange(location: selection.location + (replacement as NSString).length, length: 0)
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
