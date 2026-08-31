import SwiftUI
import AppKit

/// Plain-text markdown editor: NSTextView in a scroll view, with lightweight
/// syntax highlighting and scroll-position reporting for preview sync.
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var scrollSync: ScrollSync
    let actions: EditorActions

    @AppStorage(SettingsKeys.editorFontName) private var fontName = SettingsDefaults.editorFontName
    @AppStorage(SettingsKeys.editorFontSize) private var fontSize = SettingsDefaults.editorFontSize

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = EditorTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        actions.coordinator = context.coordinator

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
        actions.coordinator = coordinator
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

        // MARK: - Typing behaviors

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                return handleNewline(textView)
            case #selector(NSResponder.insertTab(_:)):
                return handleIndent(textView, outdent: false)
            case #selector(NSResponder.insertBacktab(_:)):
                return handleIndent(textView, outdent: true)
            default:
                return false
            }
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let replacement = replacementString,
                  !textView.hasMarkedText(),
                  let substitution = TypingSubstitutions.substitution(
                      in: textView.string as NSString,
                      affectedRange: affectedRange,
                      replacement: replacement
                  ),
                  !isInsideCode(at: affectedRange.location, textView: textView)
            else { return true }

            textView.insertText(substitution.replacement, replacementRange: substitution.range)
            return false
        }

        /// Arrows shouldn't be substituted inside code (```blocks``` or `inline`),
        /// where `->` is usually meant literally.
        private func isInsideCode(at location: Int, textView: NSTextView) -> Bool {
            let text = textView.string as NSString
            for range in highlighter.fencedBlockRanges(in: text) where NSLocationInRange(location, range) {
                return true
            }
            let lineRange = text.lineRange(for: NSRange(location: min(location, text.length), length: 0))
            var backticks = 0
            var index = lineRange.location
            while index < location, index < text.length {
                if text.character(at: index) == 0x60 { backticks += 1 }
                index += 1
            }
            return backticks % 2 == 1
        }

        private func handleNewline(_ textView: NSTextView) -> Bool {
            let selection = textView.selectedRange()
            guard selection.length == 0 else { return false }
            let text = textView.string as NSString
            let lineRange = text.lineRange(for: NSRange(location: selection.location, length: 0))
            var line = text.substring(with: lineRange)
            if line.hasSuffix("\n") { line.removeLast() }

            switch ListContinuation.newlineAction(
                forLine: line,
                caretOffset: selection.location - lineRange.location
            ) {
            case .none:
                return false
            case .endList(let prefixLength):
                replaceText(
                    in: NSRange(location: lineRange.location, length: prefixLength),
                    with: "",
                    selecting: NSRange(location: lineRange.location, length: 0)
                )
                return true
            case .continueList(let insertion):
                replaceText(
                    in: selection,
                    with: insertion,
                    selecting: NSRange(
                        location: selection.location + (insertion as NSString).length,
                        length: 0
                    )
                )
                return true
            }
        }

        private func handleIndent(_ textView: NSTextView, outdent: Bool) -> Bool {
            let selection = textView.selectedRange()
            let text = textView.string as NSString
            let lineRange = text.lineRange(for: NSRange(location: selection.location, length: 0))
            var line = text.substring(with: lineRange)
            if line.hasSuffix("\n") { line.removeLast() }

            guard let info = ListContinuation.lineInfo(forLine: line),
                  selection.location - lineRange.location <= info.prefixLength
            else { return false }

            if outdent {
                var removable = 0
                while removable < info.indentUnit,
                      lineRange.location + removable < text.length {
                    let character = text.character(at: lineRange.location + removable)
                    if character == 0x20 { removable += 1 }
                    else if character == 0x09 { removable += 1; break }
                    else { break }
                }
                guard removable > 0 else { return true }
                replaceText(
                    in: NSRange(location: lineRange.location, length: removable),
                    with: "",
                    selecting: NSRange(
                        location: max(selection.location - removable, lineRange.location),
                        length: 0
                    )
                )
            } else {
                let spaces = String(repeating: " ", count: info.indentUnit)
                replaceText(
                    in: NSRange(location: lineRange.location, length: 0),
                    with: spaces,
                    selecting: NSRange(location: selection.location + info.indentUnit, length: 0)
                )
            }
            return true
        }

        // MARK: - Formatting actions (⌘B / ⌘I / ⌘K)

        func toggleInlineMarker(_ marker: String) {
            guard let textView else { return }
            let text = textView.string as NSString
            var range = textView.selectedRange()
            let markerLength = (marker as NSString).length

            if range.length == 0 {
                let wordRange = textView.selectionRange(
                    forProposedRange: range,
                    granularity: .selectByWord
                )
                let word = wordRange.length > 0 ? text.substring(with: wordRange) : ""
                if word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    replaceText(
                        in: range,
                        with: marker + marker,
                        selecting: NSRange(location: range.location + markerLength, length: 0)
                    )
                    return
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
                replaceText(
                    in: range,
                    with: inner,
                    selecting: NSRange(location: range.location, length: (inner as NSString).length)
                )
                return
            }
            // …or just outside it.
            let before = NSRange(location: range.location - markerLength, length: markerLength)
            let after = NSRange(location: NSMaxRange(range), length: markerLength)
            if before.location >= 0, NSMaxRange(after) <= text.length,
               text.substring(with: before) == marker, text.substring(with: after) == marker {
                replaceText(
                    in: NSRange(location: before.location, length: range.length + markerLength * 2),
                    with: selected,
                    selecting: NSRange(location: before.location, length: range.length)
                )
                return
            }
            // Otherwise wrap.
            replaceText(
                in: range,
                with: marker + selected + marker,
                selecting: NSRange(location: range.location + markerLength, length: range.length)
            )
        }

        func insertLink() {
            guard let textView else { return }
            let text = textView.string as NSString
            let range = textView.selectedRange()
            let selected = range.length > 0 ? text.substring(with: range) : ""
            let clipboard = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let url = EditorTextView.isLikelyURL(clipboard) ? clipboard : ""

            let replacement = "[\(selected)](\(url))"
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
            replaceText(in: range, with: replacement, selecting: newSelection)
        }

        private func replaceText(in range: NSRange, with replacement: String, selecting newSelection: NSRange) {
            guard let textView,
                  textView.shouldChangeText(in: range, replacementString: replacement)
            else { return }
            textView.textStorage?.replaceCharacters(in: range, with: replacement)
            textView.didChangeText()
            textView.setSelectedRange(newSelection)
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
