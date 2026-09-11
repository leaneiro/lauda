import AppKit

/// Maps source lines to the editor's layout and back: where a line sits,
/// which line is at a scroll offset, and where to scroll to follow the
/// preview. Line starts are cached until the text changes.
final class SourceLineLayout {
    weak var textView: NSTextView?

    /// UTF-16 offsets where each source line starts, rebuilt after edits.
    private var cachedStarts: [Int]?

    func invalidate() {
        cachedStarts = nil
    }

    func lineStarts() -> [Int] {
        if let cachedStarts { return cachedStarts }
        let starts = SourceLines.starts(in: textView?.string ?? "")
        cachedStarts = starts
        return starts
    }

    /// Laid-out extent of a source line (all of its wrapped fragments),
    /// in text-container coordinates.
    func rect(forLine line: Int) -> NSRect? {
        guard let textView, let layoutManager = textView.layoutManager else { return nil }
        let starts = lineStarts()
        guard line >= 0, line < starts.count else { return nil }
        let length = (textView.string as NSString).length
        let start = starts[line]
        let end = line + 1 < starts.count ? starts[line + 1] : length
        guard end > start else {
            // The empty last line only exists as the extra line fragment.
            let extra = layoutManager.extraLineFragmentRect
            return extra.height > 0 ? extra : nil
        }
        let first = layoutManager.lineFragmentRect(
            forGlyphAt: layoutManager.glyphIndexForCharacter(at: start), effectiveRange: nil)
        let last = layoutManager.lineFragmentRect(
            forGlyphAt: layoutManager.glyphIndexForCharacter(at: end - 1), effectiveRange: nil)
        return NSRect(x: 0, y: first.minY, width: first.width, height: last.maxY - first.minY)
    }

    /// Fractional source line at the top of the pane when scrolled to
    /// `offset`; [-1, 0) covers the padding above the first line.
    func line(atScrollOffset offset: CGFloat) -> Double? {
        guard let textView, let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return nil }
        let inset = textView.textContainerOrigin.y
        let y = offset - inset
        if y < 0 {
            return inset > 0 ? max(Double(y / inset), -1) : 0
        }
        guard (textView.string as NSString).length > 0 else { return 0 }
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: y), in: container)
        let character = layoutManager.characterIndexForGlyph(at: glyph)
        let line = SourceLines.line(containing: character, starts: lineStarts())
        guard let rect = rect(forLine: line), rect.height > 0 else { return Double(line) }
        return Double(line) + Double(min(max((y - rect.minY) / rect.height, 0), 1))
    }

    /// Scroll offset that puts `line` at the top of the visible area.
    func scrollOffset(forLine line: Double) -> CGFloat? {
        guard let textView, line.isFinite else { return nil }
        let inset = textView.textContainerOrigin.y
        if line < 0 {
            return inset * CGFloat(1 + max(line, -1))
        }
        let starts = lineStarts()
        let index = min(Int(line.rounded(.down)), starts.count - 1)
        guard let rect = rect(forLine: index) else { return nil }
        let within = CGFloat(min(max(line - Double(index), 0), 1))
        return inset + rect.minY + within * rect.height
    }

    /// Where the editor should scroll to follow `sync`: the synced source
    /// line, or proportionally when there's no line map. The same line stays
    /// at the top of both panes, which also means the shorter pane reaches
    /// its bottom first.
    func targetOffset(for sync: ScrollSync) -> CGFloat? {
        guard let textView,
              let scrollView = textView.enclosingScrollView,
              let documentView = scrollView.documentView else { return nil }
        let maxOffset = documentView.frame.height - scrollView.contentView.bounds.height
        guard maxOffset > 0 else { return nil }
        guard let lineTarget = sync.line.flatMap(scrollOffset(forLine:)) else {
            return min(max(sync.fraction * maxOffset, 0), maxOffset)
        }
        return min(max(lineTarget, 0), maxOffset)
    }
}
