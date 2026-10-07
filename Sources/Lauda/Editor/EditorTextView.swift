import AppKit

/// NSTextView subclass adding smart link paste (pasting a URL over selected
/// text turns the selection into `[texto](url)`) and asymmetric padding so
/// the document ends with breathing room below the last line.
extension EditorTextView {
    /// The editor's views, assembled by hand: a TextKit 1 stack, because its
    /// layout is exact rather than viewport-estimated, which keeps the scroll
    /// position rock-steady when attributes change (TextKit 2 estimation
    /// caused jumps and blank runs).
    static func inScrollView() -> (scrollView: NSScrollView, textView: EditorTextView) {
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
        textView.applyEditorDefaults()

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        // Else a text that fits keeps an empty scroller, whose track shows
        // when the pointer comes near it, as it does along the divider (or
        // all the time, with scroll bars set to always show).
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return (scrollView, textView)
    }

    /// The text view writes Markdown as plain text, so everything that would
    /// rewrite what is typed is off.
    private func applyEditorDefaults() {
        isRichText = false
        // Left on the system default, Writing Tools may answer a rewrite with
        // text attributes, reading "**bold**" as bold and dropping the
        // asterisks it came from; asking for plain text keeps the document's
        // own syntax.
        if #available(macOS 15.0, *) {
            allowedWritingToolsResultOptions = .plainText
        }
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        smartInsertDeleteEnabled = false
        textContainerInset = NSSize(width: 24, height: EditorTextView.insetHeight)
        drawsBackground = true
        backgroundColor = .textBackgroundColor
    }
}

final class EditorTextView: NSTextView {
    static let topPadding: CGFloat = 20
    static let bottomPadding: CGFloat = 64
    /// textContainerInset splits its height equally between top and bottom;
    /// overriding textContainerOrigin pins the top back to topPadding, which
    /// leaves the remainder as extra space after the last line.
    static var insetHeight: CGFloat { (topPadding + bottomPadding) / 2 }

    override var textContainerOrigin: NSPoint {
        var origin = super.textContainerOrigin
        origin.y = Self.topPadding
        return origin
    }

    // MARK: - Pairs

    /// Typing comes through here, keys and input methods alike, so an
    /// opening character can bring its closing one (see AutoPairing). Undo
    /// doesn't, so it never pairs anything.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard let typed = (string as? String) ?? (string as? NSAttributedString)?.string,
              let coordinator = delegate as? MarkdownTextView.Coordinator,
              let pairing = coordinator.pairing(forTyping: typed, replacementRange: replacementRange)
        else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        let edit = pairing.edit
        if edit.range.length > 0 || !edit.replacement.isEmpty {
            super.insertText(edit.replacement, replacementRange: edit.range)
        }
        setSelectedRange(edit.selection)
        if let opener = pairing.opensPairAt {
            coordinator.openPairs.opened(at: opener)
        }
    }

    // MARK: - Image drag & drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        imageFileURLs(from: sender.draggingPasteboard).isEmpty
            ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        imageFileURLs(from: sender.draggingPasteboard).isEmpty
            ? super.draggingUpdated(sender) : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let images = imageFileURLs(from: sender.draggingPasteboard)
        if !images.isEmpty, let coordinator = delegate as? MarkdownTextView.Coordinator {
            let point = convert(sender.draggingLocation, from: nil)
            let index = characterIndexForInsertion(at: point)
            coordinator.insertImageFiles(images, at: index)
            return true
        }
        return super.performDragOperation(sender)
    }

    private func imageFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        return urls.filter(ImageImporter.isImageFile)
    }

    // MARK: - Paste (images, then smart link)

    /// A plain-text view reports nothing readable when the pasteboard only
    /// holds an image, so AppKit disables Paste (menu greyed out, ⌘V inert)
    /// before `paste(_:)` is ever reached. Advertise the image flavors we
    /// handle ourselves so the command stays enabled.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        super.readablePasteboardTypes + [.fileURL, .png, .tiff]
    }

    /// Injectable so tests can exercise paste without touching the user's
    /// clipboard.
    var pasteboardProvider: () -> NSPasteboard = { .general }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)),
           ImageImporter.pasteIntent(for: pasteboardProvider()) != .notAnImage {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }

    override func paste(_ sender: Any?) {
        if let coordinator = delegate as? MarkdownTextView.Coordinator {
            switch ImageImporter.pasteIntent(for: pasteboardProvider()) {
            case .imageFiles(let urls):
                coordinator.insertImageFiles(urls, at: nil)
                return
            case .imageData(let data):
                coordinator.insertPastedImageData(data)
                return
            case .notAnImage:
                break
            }
        }

        if let coordinator = delegate as? MarkdownTextView.Coordinator,
           coordinator.pasteLinkOverSelection() {
            return
        }
        super.paste(sender)
    }

    static func isLikelyURL(_ string: String) -> Bool {
        guard !string.isEmpty, !string.contains(where: { $0.isWhitespace }) else { return false }
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased() else { return false }
        return ExternalLinks.allowedSchemes.contains(scheme) && (url.host != nil || scheme == "mailto")
    }
}
