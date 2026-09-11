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

    private var isApplyingRemoteScroll = false

    /// A freshly created pane starts at the top (view-mode switches
    /// recreate panes). Until real layout exists and the shared position
    /// is reapplied, ignore the spurious layout-driven scroll events —
    /// publishing them would drag the other pane to the top too.
    var needsRestore = false
    private var restoreAttempts = 0
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
            // Not laid out yet — keep retrying briefly so the pane doesn't
            // sit at the top waiting for an event that may never come.
            restoreAttempts += 1
            if restoreAttempts < 80 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
                    self?.restoreIfNeeded()
                }
            } else {
                needsRestore = false
            }
            return
        }

        needsRestore = false
        restoreAttempts = 0
        anchorToSharedPosition()
    }

    /// Positions the pane at the shared scroll position (used both when a
    /// recreated pane comes up and when a resize re-flows the text, so the
    /// same source line stays at the top).
    private func anchorToSharedPosition() {
        guard let textView,
              let scrollView = textView.enclosingScrollView else { return }
        if let layoutManager = textView.layoutManager, let container = textView.textContainer {
            layoutManager.ensureLayout(for: container)
        }
        let clipView = scrollView.contentView
        lastClipSize = clipView.bounds.size
        guard let target = lines.targetOffset(for: sharedPosition()) else { return }
        isApplyingRemoteScroll = true
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: target.rounded()))
        scrollView.reflectScrolledClipView(clipView)
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
        anchorToSharedPosition()
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
            anchorToSharedPosition()
            return
        }
        lastClipSize = clipView.bounds.size

        let maxOffset = documentView.frame.height - clipView.bounds.height
        let offset = clipView.bounds.origin.y
        let sync = ScrollSync(
            line: lines.line(atScrollOffset: offset),
            fraction: maxOffset > 0 ? min(max(offset / maxOffset, 0), 1) : 0,
            source: .editor
        )
        guard sync.differs(from: sharedPosition()) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.publish(sync)
        }
    }

    /// Scrolls the editor to follow the preview. Compares against the live
    /// position (not a cached value) and suppresses the resulting bounds
    /// notification so the movement doesn't echo back to the preview.
    func applyRemote(_ sync: ScrollSync) {
        guard let textView,
              let scrollView = textView.enclosingScrollView,
              let target = lines.targetOffset(for: sync) else { return }
        let clipView = scrollView.contentView
        guard abs(target - clipView.bounds.origin.y) > 0.5 else { return }

        isApplyingRemoteScroll = true
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: target.rounded()))
        scrollView.reflectScrolledClipView(clipView)
        isApplyingRemoteScroll = false
    }
}
