import AppKit

/// Keeps the editor pane in step with the scroll position it shares with the
/// preview: publishes where the user scrolls, follows the preview, and
/// re-anchors when the pane is recreated or resized.
final class EditorScrolling: NSObject {
    weak var textView: NSTextView?
    private let lines: SourceLineLayout

    /// The shared position (a SwiftUI binding), read and published through
    /// the editor's coordinator.
    var sharedPosition: () -> ScrollSync = { ScrollSync() }
    var publish: (ScrollSync) -> Void = { _ in }
    /// Whether the text is taller than the pane, as last told, and whom to
    /// tell when that changes; nil before the pane is laid out.
    private(set) var scrollable: Bool?
    var scrollableChanged: (Bool) -> Void = { _ in }

    /// Whether this pane scrolls together with the preview. Apart, it still
    /// publishes where it is, but keeps its own line when its text reflows,
    /// since the shared one may then be the preview's.
    var isLinked = true
    /// Where this pane is by its own account: what it last reported (shared
    /// or not), took from the preview or a jump, or was anchored to.
    private var ownPosition: ScrollSync?

    private var isApplyingRemoteScroll = false

    /// A freshly created pane starts at the top (view-mode switches
    /// recreate panes). Until real layout exists and the shared position
    /// is reapplied, ignore the spurious layout-driven scroll events —
    /// publishing them would drag the other pane to the top too.
    var needsRestore = false
    private var restoreRetry = LayoutRetry()
    private var lastClipSize: NSSize?

    init(lines: SourceLineLayout) {
        self.lines = lines
    }

    func restoreIfNeeded() {
        guard needsRestore else { return }
        guard let textView,
              let scrollView = textView.enclosingScrollView,
              textView.window != nil,
              scrollView.contentView.bounds.width > 0,
              scrollView.contentView.bounds.height > 0 else {
            // Not laid out yet — keep asking briefly so the pane doesn't sit
            // at the top waiting for an event that may never come.
            let asked = restoreRetry.again { [weak self] in self?.restoreIfNeeded() }
            if !asked { needsRestore = false }
            return
        }

        needsRestore = false
        restoreRetry.startOver()
        anchor()
    }

    /// Positions the pane at the line it keeps (used both when a recreated
    /// pane comes up and when a resize re-flows the text, so the same
    /// source line stays at the top): the shared position, or this pane's
    /// own while the panes scroll apart. A pane just created has no
    /// position of its own yet, and starts from the shared one.
    private func anchor() {
        guard let textView,
              let scrollView = textView.enclosingScrollView else { return }
        if let layoutManager = textView.layoutManager, let container = textView.textContainer {
            layoutManager.ensureLayout(for: container)
        }
        let clipView = scrollView.contentView
        lastClipSize = clipView.bounds.size
        reportScrollable()
        let position = isLinked ? sharedPosition() : (ownPosition ?? sharedPosition())
        guard let target = lines.targetOffset(for: position) else { return }
        ownPosition = position
        isApplyingRemoteScroll = true
        scrollView.scrollVertically(to: target.rounded())
        isApplyingRemoteScroll = false
    }

    /// The pane changed size (window resize, divider drag, a scroll bar
    /// appearing): the text re-flows, so the same offset would show another
    /// line. Re-anchor right away; left for later, the next scroll event
    /// would be spent re-anchoring instead of scrolling.
    @objc func frameDidChange(_ notification: Notification) {
        guard !needsRestore, !isApplyingRemoteScroll,
              let clipView = notification.object as? NSClipView,
              let lastSize = lastClipSize, lastSize != clipView.bounds.size else { return }
        anchor()
    }

    @objc func boundsDidChange(_ notification: Notification) {
        if needsRestore {
            restoreIfNeeded()
            return
        }
        guard !isApplyingRemoteScroll,
              let clipView = notification.object as? NSClipView,
              let documentView = clipView.documentView else { return }

        // A pane resize (divider drag, mode switch) re-flows the text, so
        // the same offset now shows a different line. Re-anchor to the
        // shared position instead of publishing the drifted value.
        if let lastSize = lastClipSize, lastSize != clipView.bounds.size {
            anchor()
            return
        }
        lastClipSize = clipView.bounds.size
        reportScrollable()

        let maxOffset = documentView.frame.height - clipView.bounds.height
        let offset = clipView.bounds.origin.y
        let sync = ScrollSync(
            line: lines.line(atScrollOffset: offset),
            fraction: maxOffset > 0 ? min(max(offset / maxOffset, 0), 1) : 0,
            endLine: lines.line(atScrollOffset: max(maxOffset, 0)),
            toEndDistance: Double(max(maxOffset - offset, 0)),
            source: .editor
        )
        ownPosition = sync
        guard sync.differs(from: sharedPosition()) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.publish(sync)
        }
    }

    /// The text view's frame changed, with its text or with the pane's
    /// width: whether there is more than fits may have changed with it.
    @objc func contentDidChange(_ notification: Notification) {
        reportScrollable()
    }

    /// Tells, when it changes, whether the text is taller than the pane by
    /// more than a hair.
    private func reportScrollable() {
        guard let textView, let scrollView = textView.enclosingScrollView else { return }
        let scrollable = textView.frame.height > scrollView.contentView.bounds.height + 1
        guard scrollable != self.scrollable else { return }
        self.scrollable = scrollable
        DispatchQueue.main.async { [weak self] in
            self?.scrollableChanged(scrollable)
        }
    }

    /// Scrolls the editor to follow the preview. Compares against the live
    /// position (not a cached value) and suppresses the resulting bounds
    /// notification so the movement doesn't echo back to the preview.
    func applyRemote(_ sync: ScrollSync) {
        guard let textView,
              let scrollView = textView.enclosingScrollView,
              let target = lines.targetOffset(for: sync) else { return }
        ownPosition = sync
        let clipView = scrollView.contentView
        guard abs(target - clipView.bounds.origin.y) > 0.5 else { return }

        isApplyingRemoteScroll = true
        scrollView.scrollVertically(to: target.rounded())
        isApplyingRemoteScroll = false
    }
}

extension NSScrollView {
    /// Scrolls the content to `y` and tells the scroll view about it, which
    /// is what keeps the scrollers and the rulers in step with a scroll the
    /// app makes rather than the reader.
    func scrollVertically(to y: CGFloat) {
        let clipView = contentView
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: y))
        reflectScrolledClipView(clipView)
    }
}
