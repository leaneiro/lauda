import SwiftUI
import AppKit

/// Plain-text markdown editor: NSTextView in a scroll view, with lightweight
/// syntax highlighting and scroll-position reporting for preview sync.
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var scrollSync: ScrollSync
    let actions: EditorActions
    let fileURL: URL?

    @AppStorage(SettingsKeys.editorFontName) private var fontName = SettingsDefaults.editorFontName
    @AppStorage(SettingsKeys.editorFontSize) private var fontSize = SettingsDefaults.editorFontSize

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1 stack, assembled by hand: its layout is exact rather than
        // viewport-estimated, which keeps the scroll position rock-steady when
        // attributes change (TextKit 2 estimation caused jumps and blank runs).
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = EditorTextView(frame: .zero, textContainer: textContainer)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
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
        textView.textContainerInset = NSSize(width: 24, height: EditorTextView.insetHeight)
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor

        textView.string = text
        context.coordinator.textView = textView
        context.coordinator.applyStyle(fontName: fontName, fontSize: fontSize)
        context.coordinator.needsScrollRestore = true
        DispatchQueue.main.async { [weak coordinator = context.coordinator] in
            coordinator?.restoreScrollIfNeeded()
        }

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
        coordinator.restoreScrollIfNeeded()
        guard let textView = coordinator.textView else { return }

        // Never replace text mid-IME-composition: the marked text makes the
        // strings differ, and resetting would kill the accent being composed.
        if textView.string != text, !textView.hasMarkedText() {
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
            highlightAfterEdit()
            refreshFindAfterEdit()
            scheduleCaretComfortScroll(textView)
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

            clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: clamped))
            scrollView.reflectScrolledClipView(clipView)
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
            guard let textView else { return }
            // Programmatic edits (formatting, list continuation) get their own
            // undo step, separate from surrounding typing.
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

        // MARK: - Find engine (unified find bar)

        private(set) var findQuery = ""
        private var findMatches: [NSRange] = []
        private var findCurrentIndex = -1
        /// Notifies the find bar when counts change due to typing.
        var findCountsChanged: ((Int, Int) -> Void)?

        /// Recomputes matches and jumps to the first one at/after the caret.
        func findUpdate(_ query: String) -> (current: Int, total: Int) {
            findQuery = query
            recomputeFindMatches()
            if findMatches.isEmpty {
                findCurrentIndex = -1
            } else {
                let caret = textView?.selectedRange().location ?? 0
                findCurrentIndex = findMatches.firstIndex { $0.location >= caret } ?? 0
            }
            applyFindHighlights(scrollToCurrent: true)
            return (findCurrentIndex + 1, findMatches.count)
        }

        func findStep(forward: Bool) -> (current: Int, total: Int) {
            guard !findMatches.isEmpty else { return (0, 0) }
            findCurrentIndex = (findCurrentIndex + (forward ? 1 : -1) + findMatches.count)
                % findMatches.count
            applyFindHighlights(scrollToCurrent: true)
            return (findCurrentIndex + 1, findMatches.count)
        }

        func findClear() {
            findQuery = ""
            findMatches = []
            findCurrentIndex = -1
            removeFindHighlights()
        }

        /// Edits shift match ranges; recompute and repaint (without scrolling).
        fileprivate func refreshFindAfterEdit() {
            guard !findQuery.isEmpty else { return }
            recomputeFindMatches()
            if findMatches.isEmpty {
                findCurrentIndex = -1
            } else {
                findCurrentIndex = min(max(findCurrentIndex, 0), findMatches.count - 1)
            }
            applyFindHighlights(scrollToCurrent: false)
            findCountsChanged?(findCurrentIndex + 1, findMatches.count)
        }

        private func recomputeFindMatches() {
            findMatches = []
            guard let textView, !findQuery.isEmpty else { return }
            let text = textView.string as NSString
            var location = 0
            while location < text.length {
                let range = text.range(
                    of: findQuery,
                    options: [.caseInsensitive],
                    range: NSRange(location: location, length: text.length - location)
                )
                guard range.location != NSNotFound else { break }
                findMatches.append(range)
                location = range.location + max(range.length, 1)
            }
        }

        private func applyFindHighlights(scrollToCurrent: Bool) {
            guard let textView, let layoutManager = textView.layoutManager else { return }
            removeFindHighlights()
            // Current match: strong orange, clearly distinct from the pale
            // yellow of the other matches (yellow-on-yellow was too subtle).
            for (index, range) in findMatches.enumerated() {
                if index == findCurrentIndex {
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
            if scrollToCurrent, findCurrentIndex >= 0 {
                textView.scrollRangeToVisible(findMatches[findCurrentIndex])
            }
        }

        private func removeFindHighlights() {
            guard let textView, let layoutManager = textView.layoutManager else { return }
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
        }

        // MARK: - Image insertion (drag & drop / paste)

        /// Imports image files into the document's folder and inserts the
        /// relative markdown at `index` (or the caret). Returns true when the
        /// event was consumed.
        func insertImageFiles(_ urls: [URL], at index: Int?) -> Bool {
            guard let directory = documentDirectory() else { return true }
            let paths = urls.compactMap { ImageImporter.importImage(from: $0, into: directory) }
            guard !paths.isEmpty else { return false }
            insertImageMarkdown(paths, at: index)
            return true
        }

        /// Saves pasted raw image data (e.g. a screenshot) as PNG in the
        /// document's folder and inserts the markdown at the caret.
        func insertPastedImageData(_ data: Data) -> Bool {
            guard let directory = documentDirectory() else { return true }
            guard let name = ImageImporter.saveImageData(data, in: directory) else { return false }
            insertImageMarkdown([name], at: nil)
            return true
        }

        private func documentDirectory() -> URL? {
            if let fileURL = parent.fileURL {
                return fileURL.deletingLastPathComponent()
            }
            let alert = NSAlert()
            alert.messageText = "Salve o documento primeiro"
            alert.informativeText = "Imagens são copiadas para a pasta do documento — salve o arquivo para ele ter uma."
            alert.runModal()
            return nil
        }

        private func insertImageMarkdown(_ paths: [String], at index: Int?) {
            guard let textView else { return }
            let markdown = ImageImporter.markdown(forRelativePaths: paths)
            let range = index.map { NSRange(location: $0, length: 0) } ?? textView.selectedRange()
            replaceText(
                in: range,
                with: markdown,
                selecting: NSRange(location: range.location + (markdown as NSString).length, length: 0)
            )
        }

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

        private var isApplyingRemoteScroll = false

        /// A freshly created pane starts at the top (view-mode switches
        /// recreate panes). Until real layout exists and the shared position
        /// is reapplied, ignore the spurious layout-driven scroll events —
        /// publishing them would drag the other pane to the top too.
        var needsScrollRestore = false
        private var restoreAttempts = 0
        private var lastClipSize: NSSize?

        func restoreScrollIfNeeded() {
            guard needsScrollRestore else { return }
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
                        self?.restoreScrollIfNeeded()
                    }
                } else {
                    needsScrollRestore = false
                }
                return
            }

            needsScrollRestore = false
            restoreAttempts = 0
            anchorToSharedFraction()
        }

        /// Positions the pane at the shared scroll fraction (used both when a
        /// recreated pane comes up and when a resize re-flows the text).
        private func anchorToSharedFraction() {
            guard let textView,
                  let scrollView = textView.enclosingScrollView else { return }
            if let layoutManager = textView.layoutManager, let container = textView.textContainer {
                layoutManager.ensureLayout(for: container)
            }
            let clipView = scrollView.contentView
            lastClipSize = clipView.bounds.size
            let maxOffset = textView.frame.height - clipView.bounds.height
            guard maxOffset > 0 else { return }
            isApplyingRemoteScroll = true
            clipView.scroll(to: NSPoint(
                x: clipView.bounds.origin.x,
                y: (parent.scrollSync.fraction * maxOffset).rounded()
            ))
            scrollView.reflectScrolledClipView(clipView)
            isApplyingRemoteScroll = false
        }

        @objc func scrollViewBoundsDidChange(_ notification: Notification) {
            if needsScrollRestore {
                restoreScrollIfNeeded()
                return
            }
            guard !isApplyingRemoteScroll,
                  let clipView = notification.object as? NSClipView,
                  let documentView = clipView.documentView else { return }

            // A pane resize (divider drag, mode switch) re-flows the text and
            // shifts what fraction the same offset means. Re-anchor to the
            // shared position instead of publishing the drifted value.
            if let lastSize = lastClipSize, lastSize != clipView.bounds.size {
                anchorToSharedFraction()
                return
            }
            lastClipSize = clipView.bounds.size

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
