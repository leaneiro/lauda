import SwiftUI
import AppKit

/// Plain-text markdown editor: NSTextView in a scroll view, with lightweight
/// syntax highlighting and scroll-position reporting for preview sync.
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var scrollSync: ScrollSync

    @AppStorage(SettingsKeys.editorFontName) private var fontName = SettingsDefaults.editorFontName
    @AppStorage(SettingsKeys.editorFontSize) private var fontSize = SettingsDefaults.editorFontSize

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor

        textView.string = text
        context.coordinator.textView = textView
        context.coordinator.applyStyle(fontName: fontName, fontSize: fontSize)

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = coordinator.textView else { return }

        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            // The text view's undo entries hold ranges into the replaced text.
            coordinator.textUndoManager.removeAllActions()
            coordinator.highlight()
        }
        if coordinator.appliedFontName != fontName || coordinator.appliedFontSize != fontSize {
            coordinator.applyStyle(fontName: fontName, fontSize: fontSize)
        }
        if scrollSync.source == .preview {
            coordinator.applyRemoteScroll(fraction: scrollSync.fraction)
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        weak var textView: NSTextView?
        private(set) var appliedFontName: String?
        private(set) var appliedFontSize: Double?
        private let highlighter = MarkdownHighlighter()

        /// Private undo stack for typing, so NSTextView's coalesced undo never
        /// interleaves with the document-level undo SwiftUI registers for each
        /// binding write (interleaving breaks ⌘Z and can apply stale ranges).
        let textUndoManager = UndoManager()

        init(parent: MarkdownTextView) {
            self.parent = parent
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            textUndoManager
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            // During IME composition (dead keys: ´ + a → á) the text contains
            // uncommitted marked text; committing fires textDidChange again.
            guard !textView.hasMarkedText() else { return }
            parent.text = textView.string
            highlight()
        }

        func applyStyle(fontName: String, fontSize: Double) {
            guard let textView else { return }
            appliedFontName = fontName
            appliedFontSize = fontSize

            let font = FontOption.nsFont(for: fontName, size: fontSize)
            highlighter.baseFont = font
            textView.typingAttributes = highlighter.baseAttributes
            highlight()
        }

        func highlight() {
            guard let textView else { return }
            highlighter.highlight(textView.textStorage)
        }

        private var isApplyingRemoteScroll = false

        @objc func scrollViewBoundsDidChange(_ notification: Notification) {
            guard !isApplyingRemoteScroll,
                  let clipView = notification.object as? NSClipView,
                  let documentView = clipView.documentView else { return }

            let maxOffset = documentView.frame.height - clipView.bounds.height
            let fraction = maxOffset > 0 ? clipView.bounds.origin.y / maxOffset : 0
            let clamped = min(max(fraction, 0), 1)

            guard abs(clamped - parent.scrollSync.fraction) > 0.001 else { return }
            DispatchQueue.main.async { [weak self] in
                self?.parent.scrollSync = ScrollSync(fraction: clamped, source: .editor)
            }
        }

        /// Scrolls the editor to follow the preview. Compares against the live
        /// position (not a cached value) and suppresses the resulting bounds
        /// notification so the movement doesn't echo back to the preview.
        func applyRemoteScroll(fraction: CGFloat) {
            guard let textView,
                  let scrollView = textView.enclosingScrollView,
                  let documentView = scrollView.documentView else { return }

            let clipView = scrollView.contentView
            let maxOffset = documentView.frame.height - clipView.bounds.height
            guard maxOffset > 0 else { return }

            let currentFraction = clipView.bounds.origin.y / maxOffset
            guard abs(fraction - currentFraction) > 0.001 else { return }

            isApplyingRemoteScroll = true
            clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: fraction * maxOffset))
            scrollView.reflectScrolledClipView(clipView)
            isApplyingRemoteScroll = false
        }
    }
}
