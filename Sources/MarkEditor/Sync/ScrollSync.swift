import Foundation

/// Shared scroll position between the panes, anchored in the source text so
/// both show the same block even when images or tables make the preview much
/// taller than the text. `source` marks which pane the user scrolled, so the
/// other pane follows and echoes are ignored.
struct ScrollSync: Equatable {
    /// Which pane the user scrolled (the other follows, echoes are ignored),
    /// or `navigation` for a jump both panes follow, like the outline's.
    enum Source { case editor, preview, navigation }
    /// Fractional source line at the top of the pane; [-1, 0) is the padding
    /// above the first line. nil when the pane has no line map.
    var line: Double?
    /// Proportional position, the fallback when there's no line map.
    var fraction: CGFloat = 0
    var source: Source = .editor

    func differs(from other: ScrollSync) -> Bool {
        abs(fraction - other.fraction) > 0.001
            || abs((line ?? -2) - (other.line ?? -2)) > 0.005
    }
}
