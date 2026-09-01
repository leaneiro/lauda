import AppKit

/// NSTextView subclass adding smart link paste (pasting a URL over selected
/// text turns the selection into `[texto](url)`) and asymmetric padding so
/// the document ends with breathing room below the last line.
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

    override func paste(_ sender: Any?) {
        let selection = selectedRange()
        if selection.length > 0,
           let clipboard = NSPasteboard.general.string(forType: .string)?
               .trimmingCharacters(in: .whitespacesAndNewlines),
           Self.isLikelyURL(clipboard) {
            let selected = (string as NSString).substring(with: selection)
            if !selected.contains("\n"),
               !Self.isLikelyURL(selected.trimmingCharacters(in: .whitespaces)) {
                let replacement = "[\(selected)](\(clipboard))"
                if shouldChangeText(in: selection, replacementString: replacement) {
                    textStorage?.replaceCharacters(in: selection, with: replacement)
                    didChangeText()
                    setSelectedRange(NSRange(
                        location: selection.location + (replacement as NSString).length,
                        length: 0
                    ))
                    return
                }
            }
        }
        super.paste(sender)
    }

    static func isLikelyURL(_ string: String) -> Bool {
        guard !string.isEmpty, !string.contains(where: { $0.isWhitespace }) else { return false }
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto"].contains(scheme) && (url.host != nil || scheme == "mailto")
    }
}
