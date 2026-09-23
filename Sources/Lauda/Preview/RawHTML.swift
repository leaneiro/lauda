import Foundation

/// The document's own HTML, as far as keeping it whole in the preview goes.
///
/// The preview wraps each top-level block of raw HTML in an element of its
/// own (see HTMLRenderer.renderWithLines). An element opened in one block
/// and closed in a later one, with Markdown between, would be cut off at the
/// end of its wrapper: GitHub's `<details>` with a blank line after the
/// summary, or a centred `<div>` around an image. Such blocks share one
/// wrapper instead.
enum RawHTML {
    /// The last of the rendered blocks that the raw HTML at `start` runs
    /// through: `start` itself, unless it leaves an element open that a
    /// later block closes. Left open to the end, it stays alone, and the
    /// browser closes the element in its wrapper, as it always did.
    static func closingIndex(in pieces: [String], from start: Int) -> Int {
        var open = openElements(after: pieces[start])
        var index = start
        while !open.isEmpty {
            index += 1
            guard index < pieces.count else { return start }
            open = openElements(after: pieces[index], startingWith: open)
        }
        return index
    }

    /// The elements still open after `html`'s tags, in the order they
    /// opened: a closing tag also closes whatever was opened inside it, as
    /// the browser does.
    static func openElements(after html: String, startingWith open: [String] = []) -> [String] {
        var open = open
        let text = comment.stringByReplacingMatches(
            in: html, range: NSRange(html.startIndex..., in: html), withTemplate: "")
        for match in tag.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let nameRange = Range(match.range(at: 2), in: text) else { continue }
            let name = text[nameRange].lowercased()
            if match.range(at: 1).length > 0 {
                if let index = open.lastIndex(of: name) {
                    open.removeSubrange(index...)
                }
            } else if match.range(at: 3).length == 0, !neverOpen.contains(name) {
                open.append(name)
            }
        }
        return open
    }

    /// Elements that hold nothing, and ones the browser closes by itself
    /// when the next block begins: none of them keeps a later block inside.
    private static let neverOpen: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source",
        "track", "wbr", "p", "li", "dt", "dd", "tr", "td", "th", "thead", "tbody", "tfoot", "option",
        "optgroup", "colgroup", "caption", "rb", "rt", "rtc", "rp", "html", "head", "body",
    ]

    private static let tag = try! NSRegularExpression(pattern: #"<(/?)([A-Za-z][A-Za-z0-9-]*)(?:\s[^<>]*?)?(/?)>"#)
    private static let comment = try! NSRegularExpression(pattern: #"<!--[\s\S]*?-->"#)
}
