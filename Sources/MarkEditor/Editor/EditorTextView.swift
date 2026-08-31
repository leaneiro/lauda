import AppKit

/// NSTextView subclass adding smart link paste: pasting a URL over selected
/// text turns the selection into `[texto](url)`.
final class EditorTextView: NSTextView {
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
