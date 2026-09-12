import AppKit

/// Find in the editor for the unified find bar: the matches, the current one
/// and their highlights, drawn as temporary layout attributes so they never
/// touch the text or its undo.
final class EditorFind {
    weak var textView: NSTextView?
    private(set) var query = ""
    private var matches: [NSRange] = []
    private var currentIndex = -1
    /// Notifies the find bar when counts change due to typing.
    var countsChanged: ((Int, Int) -> Void)?

    /// Recomputes matches and jumps to the first one at/after the caret.
    func update(_ query: String) -> (current: Int, total: Int) {
        self.query = query
        recomputeMatches()
        if matches.isEmpty {
            currentIndex = -1
        } else {
            let caret = textView?.selectedRange().location ?? 0
            currentIndex = matches.firstIndex { $0.location >= caret } ?? 0
        }
        applyHighlights(scrollToCurrent: true)
        return (currentIndex + 1, matches.count)
    }

    func step(forward: Bool) -> (current: Int, total: Int) {
        guard !matches.isEmpty else { return (0, 0) }
        currentIndex = (currentIndex + (forward ? 1 : -1) + matches.count) % matches.count
        applyHighlights(scrollToCurrent: true)
        return (currentIndex + 1, matches.count)
    }

    func clear() {
        query = ""
        matches = []
        currentIndex = -1
        removeHighlights()
    }

    /// Edits shift match ranges; recompute and repaint (without scrolling).
    func refreshAfterEdit() {
        guard !query.isEmpty else { return }
        recomputeMatches()
        if matches.isEmpty {
            currentIndex = -1
        } else {
            currentIndex = min(max(currentIndex, 0), matches.count - 1)
        }
        applyHighlights(scrollToCurrent: false)
        countsChanged?(currentIndex + 1, matches.count)
    }

    private func recomputeMatches() {
        matches = []
        guard let textView, !query.isEmpty else { return }
        let text = textView.string as NSString
        var location = 0
        while location < text.length {
            let range = text.range(
                of: query,
                options: [.caseInsensitive],
                range: NSRange(location: location, length: text.length - location)
            )
            guard range.location != NSNotFound else { break }
            matches.append(range)
            location = range.location + max(range.length, 1)
        }
    }

    private func applyHighlights(scrollToCurrent: Bool) {
        guard let textView, let layoutManager = textView.layoutManager else { return }
        removeHighlights()
        // Current match: strong orange, clearly distinct from the pale
        // yellow of the other matches (yellow-on-yellow was too subtle).
        for (index, range) in matches.enumerated() {
            if index == currentIndex {
                layoutManager.addTemporaryAttribute(
                    .backgroundColor, value: NSColor.systemOrange, forCharacterRange: range)
                layoutManager.addTemporaryAttribute(
                    .foregroundColor, value: NSColor.black, forCharacterRange: range)
            } else {
                layoutManager.addTemporaryAttribute(
                    .backgroundColor,
                    value: NSColor.systemYellow.withAlphaComponent(0.22),
                    forCharacterRange: range)
            }
        }
        if scrollToCurrent, currentIndex >= 0 {
            textView.scrollRangeToVisible(matches[currentIndex])
        }
    }

    private func removeHighlights() {
        guard let textView, let layoutManager = textView.layoutManager else { return }
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
    }
}
