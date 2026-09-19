import Foundation

/// Typing an opening character types its closing one too, with the caret
/// between them, and typed over a selection the pair wraps it. Brackets and
/// double quotes pair everywhere; Markdown's markers only outside code, where
/// they mean something.
///
/// Only a pair the editor typed is the editor's to take back: typing its
/// closing character steps over it, and deleting into it empty removes both
/// (see OpenPairs). What the writer typed stays as typed.
enum AutoPairing {
    /// What a keystroke does instead of inserting its character.
    struct Typing: Equatable {
        var edit: TextEdit
        /// Where a pair the editor just typed opens, for OpenPairs.
        var opensPairAt: Int?
    }

    /// Opening characters and the ones that close them.
    private static let pairs: [Character: Character] = [
        "(": ")", "[": "]", "{": "}", "\"": "\"", "*": "*", "_": "_", "`": "`",
    ]
    /// Markdown's markers, plain characters inside code.
    private static let markers: Set<Character> = ["*", "_", "`"]
    /// Markers that say more doubled (`**` is bold), so a second one typed
    /// in an empty pair of them opens a pair inside it.
    private static let doubling: Set<Character> = ["*", "_"]
    /// What a new pair may be typed right before. Before anything else, a
    /// word most of all, the opening character is marking text by hand.
    private static let roomyNeighbours: Set<Character> = [")", "]", "}", ".", ",", ";", ":", "!", "?"]

    /// What typing `typed` in place of `range` does, when it isn't simply
    /// inserting it. `composing` says `range` holds what an input method is
    /// still composing (an accent's dead key), which the typed character
    /// replaces; otherwise `range` is the selection.
    static func typing(
        _ typed: String,
        replacing range: NSRange,
        composing: Bool,
        in text: NSString,
        openPair: OpenPairs.Pair?,
        isCode: () -> Bool
    ) -> Typing? {
        guard typed.count == 1, let character = typed.first else { return nil }
        let isCaret = composing || range.length == 0
        let start = range.location
        let end = NSMaxRange(range)
        let before = Self.character(at: start - 1, in: text)
        let after = Self.character(at: end, in: text)
        let reachesOpenPair = isCaret && openPair?.closer == end
        let isInEmptyOpenPair = reachesOpenPair && openPair?.opener == start - 1
        let caretAfterOne = NSRange(location: start + 1, length: 0)

        // The closing character of a pair the editor typed: step over it.
        // An empty `*` or `_` pair is the exception, the second marker
        // making it `**` or `__`.
        if reachesOpenPair, after == character {
            if isInEmptyOpenPair, doubling.contains(character) {
                return Typing(
                    edit: TextEdit(range: range, replacement: typed + typed, selection: caretAfterOne),
                    opensPairAt: start
                )
            }
            return Typing(edit: TextEdit(range: range, replacement: "", selection: caretAfterOne), opensPairAt: nil)
        }
        // A space in an empty `*` or `_` pair: the star begins a list item
        // or stands alone, as in 2 * 3, and closes nothing.
        if character == " ", isInEmptyOpenPair, let marker = before, doubling.contains(marker) {
            return Typing(
                edit: TextEdit(range: NSRange(location: start, length: end + 1 - start), replacement: " ", selection: caretAfterOne),
                opensPairAt: nil
            )
        }

        guard let closer = pairs[character] else { return nil }
        if markers.contains(character), isCode() { return nil }

        if !isCaret {
            let selected = text.substring(with: range)
            return Typing(
                edit: TextEdit(
                    range: range,
                    replacement: String(character) + selected + String(closer),
                    selection: NSRange(location: start + 1, length: range.length)
                ),
                opensPairAt: nil
            )
        }
        let hasRoom = after.map { $0.isWhitespace || roomyNeighbours.contains($0) } ?? true
        guard hasRoom || reachesOpenPair, before != "\\" else { return nil }
        // A quote or a marker opens and closes with the same character:
        // after a letter, a digit or another one of it, the character closes.
        if closer == character, let before, before.isLetter || before.isNumber || before == character {
            return nil
        }
        return Typing(
            edit: TextEdit(range: range, replacement: String(character) + String(closer), selection: caretAfterOne),
            opensPairAt: start
        )
    }

    /// Deleting the opening character of an empty pair the editor typed
    /// takes the closing one with it.
    static func deletingBackward(selection: NSRange, openPair: OpenPairs.Pair?) -> TextEdit? {
        guard selection.length == 0, let pair = openPair,
              pair.opener == selection.location - 1, pair.closer == selection.location
        else { return nil }
        return TextEdit(
            range: NSRange(location: pair.opener, length: 2),
            replacement: "",
            selection: NSRange(location: pair.opener, length: 0)
        )
    }

    /// The character at a UTF-16 index; nil past either end of the text.
    private static func character(at index: Int, in text: NSString) -> Character? {
        guard index >= 0, index < text.length else { return nil }
        // Half of a character outside the BMP (an emoji): neither a word
        // nor room for a pair.
        return Unicode.Scalar(text.character(at: index)).map(Character.init) ?? "\u{FFFD}"
    }
}

/// The pairs the editor typed that the caret hasn't left yet, innermost
/// last. They move with the edits around them, and an edit that takes
/// either of a pair's characters ends that pair.
struct OpenPairs {
    struct Pair: Equatable {
        var opener: Int
        var closer: Int
    }

    private(set) var pairs: [Pair] = []

    var innermost: Pair? { pairs.last }

    mutating func opened(at location: Int) {
        pairs.append(Pair(opener: location, closer: location + 1))
    }

    mutating func textWillChange(in range: NSRange, replacementLength: Int) {
        let shift = replacementLength - range.length
        pairs = pairs.compactMap { pair in
            if NSLocationInRange(pair.opener, range) || NSLocationInRange(pair.closer, range) {
                return nil
            }
            var moved = pair
            if pair.opener >= NSMaxRange(range) { moved.opener += shift }
            if pair.closer >= NSMaxRange(range) { moved.closer += shift }
            return moved
        }
    }

    mutating func selectionDidChange(to selection: NSRange) {
        pairs.removeAll { selection.location <= $0.opener || NSMaxRange(selection) > $0.closer }
    }

    mutating func removeAll() {
        pairs.removeAll()
    }
}
