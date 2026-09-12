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
    /// Source line at the top of this pane when scrolled all the way down.
    var endLine: Double?
    /// Points left to scroll before the bottom. The follower uses it to
    /// absorb, over a short final stretch, the gap between where `endLine`
    /// lands in it and its own end, so both panes reach the bottom together
    /// while staying line-aligned everywhere before it.
    var toEndDistance: Double = 100_000
    var source: Source = .editor

    /// How much of the leader's final scrolling the follower spends closing
    /// that gap, in points. Kept short (about two lines) on purpose: spread
    /// over a whole screen, the follower visibly ran ahead well before the
    /// end; confined here, the panes stay line-aligned until the last
    /// moment and still land on the bottom together. The preview applies
    /// the same value, passed in from here.
    static let endConvergence: Double = 60

    func differs(from other: ScrollSync) -> Bool {
        abs(fraction - other.fraction) > 0.001
            || abs(toEndDistance - other.toEndDistance) > 1
            || abs((line ?? -2) - (other.line ?? -2)) > 0.005
    }
}
