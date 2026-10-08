import SwiftUI
import AppKit

/// Plain-text markdown editor: NSTextView in a scroll view, with lightweight
/// syntax highlighting and scroll-position reporting for preview sync.
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var scrollSync: ScrollSync
    /// Whether this pane follows the preview's scrolling, and keeps its own
    /// line when its text reflows, or the shared one.
    let scrollsLinked: Bool
    /// Whether the text is taller than the pane, for the divider's chain.
    @Binding var scrollable: Bool
    let actions: EditorActions
    let fileURL: URL?

    @AppStorage(AppSettings.editorFontName) private var fontName: String
    @AppStorage(AppSettings.editorFontSize) private var fontSize: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = EditorTextView.inScrollView()
        let coordinator = context.coordinator
        actions.coordinator = coordinator
        textView.delegate = coordinator

        textView.string = text
        coordinator.textView = textView
        coordinator.applyStyle(fontName: fontName, fontSize: fontSize)
        // The pane comes up before its scroll view has a size; the position
        // is restored as soon as it has one (EditorScrolling).
        coordinator.scrolling.needsRestore = true
        DispatchQueue.main.async { [weak coordinator] in
            coordinator?.scrolling.restoreIfNeeded()
        }

        observeScrolling(of: scrollView, with: coordinator.scrolling)
        return scrollView
    }

    /// Scroll position and size changes both reach the sync: one moves the
    /// other pane, the other re-flows this one.
    private func observeScrolling(of scrollView: NSScrollView, with scrolling: EditorScrolling) {
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            scrolling,
            selector: #selector(EditorScrolling.boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            scrolling,
            selector: #selector(EditorScrolling.frameDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: scrollView.contentView
        )
        // The text view grows and shrinks with its text: whether there is
        // more than fits changes with it.
        scrollView.documentView?.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            scrolling,
            selector: #selector(EditorScrolling.contentDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: scrollView.documentView
        )
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        actions.coordinator = coordinator
        coordinator.scrolling.isLinked = scrollsLinked
        coordinator.scrolling.restoreIfNeeded()
        guard let textView = coordinator.textView else { return }

        // Text this editor published itself is already in it; only text from
        // elsewhere (a revert, a file changed on disk) is compared with the
        // text view's, which walks the whole of it.
        // Never replace text mid-IME-composition: the marked text makes the
        // strings differ, and resetting would kill the accent being composed.
        if text != coordinator.lastPublished, textView.string != text, !textView.hasMarkedText() {
            let selection = textView.selectedRange()
            textView.string = text
            coordinator.lastPublished = text
            coordinator.lines.invalidate()
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            // The text view's undo entries hold ranges into the replaced text,
            // and so do the pairs it typed.
            coordinator.textUndoManager.removeAllActions()
            coordinator.openPairs.removeAll()
            coordinator.highlight()
        }
        if coordinator.appliedFontName != fontName || coordinator.appliedFontSize != fontSize {
            coordinator.applyStyle(fontName: fontName, fontSize: fontSize)
        }
        if scrollSync.movesEditor(linked: scrollsLinked) {
            coordinator.scrolling.applyRemote(scrollSync)
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator.scrolling)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        weak var textView: NSTextView? {
            didSet {
                find.textView = textView
                lines.textView = textView
                scrolling.textView = textView
            }
        }
        private(set) var appliedFontName: String?
        private(set) var appliedFontSize: Double?
        private let highlighter = MarkdownHighlighter()

        /// Find for the unified find bar.
        let find = EditorFind()
        /// Source lines ↔ layout positions, for scroll sync and the outline.
        let lines: SourceLineLayout
        /// Keeps this pane in step with the scroll position shared with the preview.
        let scrolling: EditorScrolling

        /// Private undo stack for typing, so NSTextView's coalesced undo never
        /// interleaves with the document-level undo SwiftUI registers for each
        /// binding write (interleaving breaks ⌘Z and can apply stale ranges).
        let textUndoManager = UndoManager()

        init(parent: MarkdownTextView) {
            self.parent = parent
            let lines = SourceLineLayout()
            self.lines = lines
            scrolling = EditorScrolling(lines: lines)
            super.init()
            scrolling.sharedPosition = { [weak self] in self?.parent.scrollSync ?? ScrollSync() }
            scrolling.publish = { [weak self] sync in self?.parent.scrollSync = sync }
            scrolling.scrollableChanged = { [weak self] scrollable in self?.parent.scrollable = scrollable }
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            textUndoManager
        }

        /// The pairs this editor typed that the caret is still inside of.
        var openPairs = OpenPairs()
        /// The text this editor last handed the document.
        var lastPublished: String?

        private var isUndoingOrRedoing: Bool {
            textUndoManager.isUndoing || textUndoManager.isRedoing
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            lines.invalidate()
            if isUndoingOrRedoing {
                openPairs.removeAll()
            }
            // During IME composition (dead keys: ´ + a → á) the text contains
            // uncommitted marked text; committing fires textDidChange again.
            guard !textView.hasMarkedText() else { return }
            let published = Self.copy(of: textView)
            lastPublished = published
            parent.text = published
            highlightAfterEdit()
            find.refreshAfterEdit()
            scheduleCaretComfortScroll(textView)
        }

        /// The text view's text as a Swift string of its own. `string` hands
        /// over a lazy bridge to the text storage, and every comparison of
        /// one walks it a character at a time: with about ten per keystroke
        /// (SwiftUI's checks of the views that take the text, the status
        /// bar, the preview), typing in a 100 KB file took 54 ms of the main
        /// thread per key, 9 ms with this copy, which costs 0.1 ms.
        static func copy(of textView: NSTextView) -> String {
            guard let storage = textView.textStorage?.mutableString else { return textView.string }
            let length = storage.length
            let units = [UInt16](unsafeUninitializedCapacity: length) { buffer, count in
                if let base = buffer.baseAddress, length > 0 {
                    storage.getCharacters(base, range: NSRange(location: 0, length: length))
                }
                count = length
            }
            return String(decoding: units, as: UTF16.self)
        }

        /// Restyles only the edited neighborhood. A full restyle happens only
        /// when the number of fence lines changes (a ``` was added/removed,
        /// which recolors everything below it) — rare enough not to matter.
        private var lastFenceCount = 0
        private var lastEditedRange: NSRange?

        private func highlightAfterEdit() {
            guard let textView, let storage = textView.textStorage else { return }
            let text = textView.string as NSString
            let fences = highlighter.fencedBlockRanges(in: text)
            guard fences.count == lastFenceCount else {
                lastFenceCount = fences.count
                highlighter.highlight(storage, fenceRanges: fences)
                return
            }

            let caret = min(textView.selectedRange().location, text.length)
            var region = text.lineRange(for: NSRange(location: caret, length: 0))
            if region.location > 0 {
                region = NSUnionRange(
                    region,
                    text.lineRange(for: NSRange(location: region.location - 1, length: 0))
                )
            }
            if let edited = lastEditedRange {
                lastEditedRange = nil
                let location = min(edited.location, text.length)
                let length = min(edited.length, text.length - location)
                region = NSUnionRange(region, NSRange(location: location, length: length))
            }
            highlighter.highlight(storage, in: region, fenceRanges: fences)
        }

        /// NSTextView autoscrolls only enough to put the caret at the very
        /// bottom edge, which hides where you're typing. When typing brings
        /// the caret past the threshold, scroll one clean step so a few lines
        /// of breathing room stay below it. Runs on the next runloop tick so
        /// layout (and the text view's own autoscroll) have settled first —
        /// measuring earlier gives stale caret positions and causes jitter.
        private var caretMargin: CGFloat = 60
        private var caretScrollScheduled = false

        private func scheduleCaretComfortScroll(_ textView: NSTextView) {
            guard !caretScrollScheduled else { return }
            caretScrollScheduled = true
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self else { return }
                self.caretScrollScheduled = false
                if let textView {
                    self.keepCaretInComfortZone(textView)
                }
            }
        }

        private func keepCaretInComfortZone(_ textView: NSTextView) {
            let selection = textView.selectedRange()
            guard selection.length == 0,
                  let window = textView.window,
                  let scrollView = textView.enclosingScrollView else { return }

            let screenRect = textView.firstRect(forCharacterRange: selection, actualRange: nil)
            guard screenRect != .zero else { return }
            let caretRect = textView.convert(window.convertFromScreen(screenRect), from: nil)

            let visible = textView.visibleRect
            guard caretRect.maxY > visible.maxY - caretMargin else { return }

            let clipView = scrollView.contentView
            let target = (caretRect.maxY + caretMargin - clipView.bounds.height).rounded()
            let maxOffset = max(textView.frame.height - clipView.bounds.height, 0)
            let clamped = min(max(target, 0), maxOffset)
            // Only ever reveal space below the caret — scrolling up here could
            // push the line being edited out of view.
            guard clamped > clipView.bounds.origin.y + 0.5 else { return }

            scrollView.scrollVertically(to: clamped)
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
            case #selector(NSResponder.deleteBackward(_:)):
                return handleDeleteBackward(textView)
            default:
                return false
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            openPairs.selectionDidChange(to: textView.selectedRange())
        }

        /// What typing a character does when it opens or closes a pair (see
        /// AutoPairing); nil when it is simply inserted.
        func pairing(forTyping typed: String, replacementRange: NSRange) -> AutoPairing.Typing? {
            guard let textView, typed.count == 1 else { return nil }
            let composing = textView.hasMarkedText()
            let range = replacementRange.location != NSNotFound ? replacementRange
                : composing ? textView.markedRange() : textView.selectedRange()
            return AutoPairing.typing(
                typed,
                replacing: range,
                composing: composing,
                in: textView.string as NSString,
                openPair: openPairs.innermost,
                isCode: { self.highlighter.isInsideCode(at: range.location, in: textView.string as NSString) }
            )
        }

        private func handleDeleteBackward(_ textView: NSTextView) -> Bool {
            guard !textView.hasMarkedText(),
                  let edit = AutoPairing.deletingBackward(
                      selection: textView.selectedRange(), openPair: openPairs.innermost
                  )
            else { return false }
            textView.insertText(edit.replacement, replacementRange: edit.range)
            textView.setSelectedRange(edit.selection)
            return true
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedRange: NSRange,
            replacementString: String?
        ) -> Bool {
            // Remember where the edit lands so the incremental highlight can
            // cover multi-line changes (paste, undo) beyond the caret's line.
            if let replacement = replacementString {
                lastEditedRange = NSRange(
                    location: affectedRange.location,
                    length: (replacement as NSString).length
                )
                // Word-level undo: typing normally coalesces into one giant
                // undo group; breaking at each whitespace makes ⌘Z step back
                // word by word instead of wiping the whole typing session.
                if replacement.count == 1, let character = replacement.first,
                   character.isWhitespace || character.isNewline {
                    textView.breakUndoCoalescing()
                }
            }
            if let replacement = replacementString,
               !textView.hasMarkedText(),
               let substitution = TypingSubstitutions.substitution(
                   in: textView.string as NSString,
                   affectedRange: affectedRange,
                   replacement: replacement
               ),
               !highlighter.isInsideCode(at: affectedRange.location, in: textView.string as NSString) {
                textView.insertText(substitution.replacement, replacementRange: substitution.range)
                return false
            }

            // The pairs the editor typed move with the text around them.
            // Undo puts back text from before they were typed, so it ends them.
            if isUndoingOrRedoing {
                openPairs.removeAll()
            } else if let replacement = replacementString {
                openPairs.textWillChange(
                    in: affectedRange, replacementLength: (replacement as NSString).length
                )
            }
            return true
        }

        private func handleNewline(_ textView: NSTextView) -> Bool {
            guard let edit = ListContinuation.newlineEdit(
                in: textView.string as NSString, selection: textView.selectedRange()
            ) else { return false }
            apply(edit)
            return true
        }

        private func handleIndent(_ textView: NSTextView, outdent: Bool) -> Bool {
            switch ListContinuation.indent(
                in: textView.string as NSString, selection: textView.selectedRange(), outdent: outdent
            ) {
            case .notAList:
                return false
            case .nothingToRemove:
                return true
            case .edit(let edit):
                apply(edit)
                return true
            }
        }

        // MARK: - Formatting actions (⌘B / ⌘I / ⌘U / ⇧⌘X / ⌘K)

        func toggleInlineMarker(_ marker: String) {
            toggleInlinePair(marker, marker)
        }

        func toggleInlinePair(_ opening: String, _ closing: String) {
            guard let textView else { return }
            let selection = textView.selectedRange()
            // With nothing selected, formatting applies to the word under the caret.
            let wordRange = selection.length == 0
                ? textView.selectionRange(forProposedRange: selection, granularity: .selectByWord)
                : selection
            apply(InlineFormatting.toggle(
                opening, closing, in: textView.string as NSString, selection: selection, wordRange: wordRange
            ))
        }

        /// Where pasted text comes from. Injected so the rules that read it
        /// are exercised without the real pasteboard.
        var clipboardText: () -> String? = { NSPasteboard.general.string(forType: .string) }

        func insertLink() {
            guard let textView else { return }
            apply(InlineFormatting.link(
                in: textView.string as NSString,
                selection: textView.selectedRange(),
                clipboard: clipboardText()
            ))
        }

        /// A URL pasted over a selection makes a link of it. False when this
        /// paste is an ordinary one, which the text view then performs.
        func pasteLinkOverSelection() -> Bool {
            guard let textView,
                  let edit = InlineFormatting.linkFromPaste(
                      in: textView.string as NSString,
                      selection: textView.selectedRange(),
                      clipboard: clipboardText()
                  )
            else { return false }
            apply(edit)
            return true
        }

        private func apply(_ edit: TextEdit) {
            replaceText(in: edit.range, with: edit.replacement, selecting: edit.selection)
        }

        func replaceText(in range: NSRange, with replacement: String, selecting newSelection: NSRange) {
            guard let textView else { return }
            // Programmatic edits (formatting, list continuation, images) get
            // their own undo step, separate from surrounding typing.
            textView.breakUndoCoalescing()
            guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
            textView.textStorage?.replaceCharacters(in: range, with: replacement)
            textView.didChangeText()
            textView.breakUndoCoalescing()
            textView.setSelectedRange(newSelection)
        }

        /// Drives the native find bar (used for ⌥⌘F replace).
        func performFindAction(_ action: NSTextFinder.Action) {
            guard let textView else { return }
            let sender = NSMenuItem()
            sender.tag = action.rawValue
            textView.window?.makeFirstResponder(textView)
            textView.performTextFinderAction(sender)
        }

        // MARK: - Style

        func applyStyle(fontName: String, fontSize: Double) {
            guard let textView else { return }
            appliedFontName = fontName
            appliedFontSize = fontSize

            let font = FontOption.nsFont(for: fontName, size: fontSize)
            highlighter.baseFont = font
            textView.typingAttributes = highlighter.baseAttributes
            caretMargin = NSLayoutManager().defaultLineHeight(for: font) * 1.25 * 3
            highlight()
        }

        func highlight() {
            guard let textView else { return }
            let fences = highlighter.fencedBlockRanges(in: textView.string as NSString)
            lastFenceCount = fences.count
            highlighter.highlight(textView.textStorage, fenceRanges: fences)
        }

        /// Gives the editor the keyboard; false while it isn't in a window yet.
        func focus() -> Bool {
            guard let textView, let window = textView.window else { return false }
            return window.makeFirstResponder(textView)
        }

        /// Puts the caret at the start of a source line and focuses the
        /// editor (outline navigation).
        func placeCaret(atSourceLine line: Int) {
            guard let textView else { return }
            let starts = lines.lineStarts()
            guard line >= 0, line < starts.count else { return }
            textView.setSelectedRange(NSRange(location: starts[line], length: 0))
            textView.window?.makeFirstResponder(textView)
        }
    }
}
