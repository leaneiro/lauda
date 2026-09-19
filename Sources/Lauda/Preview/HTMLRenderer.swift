import Foundation
import Markdown

/// Renders a swift-markdown AST to HTML for the preview pane.
struct HTMLRenderer: MarkupVisitor {
    typealias Result = String

    /// CommonMark behavior: a single Enter inside a paragraph folds into a
    /// space. Off by default, where every Enter is a visible line break.
    var strictLineBreaks = false

    static func render(_ markdown: String, strictLineBreaks: Bool = false) -> String {
        let document = Document(parsing: markdown)
        var renderer = HTMLRenderer(strictLineBreaks: strictLineBreaks)
        return renderer.visit(document)
    }

    /// Preview rendering plus the 0-based source lines the preview anchors its
    /// scroll on, in the order it walks the DOM: every top-level block,
    /// followed by the list items and table rows inside it.
    ///
    /// Anchoring inside blocks is what keeps long lists aligned. Between two
    /// anchors the preview can only interpolate by line number, while the
    /// rendered height of each line depends on how its text wraps at the
    /// current width — so a document made of a few huge blocks (a list of
    /// hundreds of items) drifted the more the window narrowed.
    static func renderWithLines(
        _ markdown: String,
        strictLineBreaks: Bool = false
    ) -> (html: String, anchorLines: [Int], lineCount: Int) {
        let document = Document(parsing: markdown)
        var renderer = HTMLRenderer(strictLineBreaks: strictLineBreaks)
        var html = ""
        var anchorLines: [Int] = []
        for child in document.children {
            let piece = renderer.visit(child)
            // Raw HTML can hold zero or several top-level elements; a wrapper
            // keeps the one-element-per-block correspondence. Its class tells
            // the preview not to look for anchors inside, where the elements
            // are the document's own and map to no source line of ours.
            html += child is HTMLBlock ? "<div class=\"raw\">\(piece)</div>\n" : piece
            anchorLines.append(startLine(of: child) ?? anchorLines.last ?? 0)
            if !(child is HTMLBlock) {
                appendInnerAnchors(of: child, to: &anchorLines)
            }
        }
        return (html, anchorLines, SourceLines.count(in: markdown))
    }

    /// 0-based source line a piece of markup starts on.
    private static func startLine(of markup: Markup) -> Int? {
        markup.range.map { $0.lowerBound.line - 1 }
    }

    /// Source lines of the list items and table rows inside a block, in
    /// document order: the same order the preview's `anchorElements()` walks
    /// them in, which pairs each line with the element's measured position.
    private static func appendInnerAnchors(of markup: Markup, to anchorLines: inout [Int]) {
        for child in markup.children {
            // A table's head renders as the row inside <thead>.
            if child is ListItem || child is Markdown.Table.Head || child is Markdown.Table.Row {
                anchorLines.append(startLine(of: child) ?? anchorLines.last ?? 0)
            }
            appendInnerAnchors(of: child, to: &anchorLines)
        }
    }

    /// Print-oriented rendering: each top-level heading is wrapped together
    /// with an invisible probe that reserves a couple of lines below it.
    /// `break-inside: avoid` on the wrapper then pushes the heading to the
    /// next page instead of leaving it orphaned at the bottom (WebKit's print
    /// engine ignores `break-after: avoid`, so this is the reliable route).
    static func renderForPrint(_ markdown: String, strictLineBreaks: Bool = false) -> String {
        let document = Document(parsing: markdown)
        var renderer = HTMLRenderer(strictLineBreaks: strictLineBreaks)
        let children = Array(document.children)
        var html = ""
        var index = 0
        while index < children.count {
            guard children[index] is Heading else {
                html += renderer.visit(children[index])
                index += 1
                continue
            }
            var group = renderer.visit(children[index])
            index += 1
            while index < children.count, children[index] is Heading {
                group += renderer.visit(children[index])
                index += 1
            }
            if index < children.count, Self.avoidsInnerBreaks(children[index]) {
                // The next block is itself unbreakable (pre/table/quote): if it
                // doesn't fit it would jump to the next page alone, stranding
                // the heading above an empty gap — so they travel as one unit.
                group += renderer.visit(children[index])
                index += 1
                html += "<div class=\"keep-with-next\">\(group)</div>\n"
            } else {
                html += "<div class=\"keep-with-next keep-pad\">\(group)<div class=\"keep-probe\"></div></div>\n"
            }
        }
        return html
    }

    /// Blocks styled with `break-inside: avoid` in the print stylesheet.
    /// Long code blocks are allowed to flow across pages, so only compact
    /// ones travel glued to their heading.
    private static func avoidsInnerBreaks(_ markup: Markup) -> Bool {
        if let codeBlock = markup as? CodeBlock {
            return lineCount(of: codeBlock) <= compactCodeBlockLineLimit
        }
        return markup is Markdown.Table || markup is BlockQuote
    }

    // MARK: - Escaping

    /// Compared unit by unit: a combining mark right after one of these
    /// characters (a quote, then U+0301) makes a single Character with it,
    /// which a plain search passes over, leaving a raw quote that closes the
    /// attribute it sits in.
    static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;", options: .literal)
            .replacingOccurrences(of: "<", with: "&lt;", options: .literal)
            .replacingOccurrences(of: ">", with: "&gt;", options: .literal)
            .replacingOccurrences(of: "\"", with: "&quot;", options: .literal)
    }

    // MARK: - Visitor

    mutating func defaultVisit(_ markup: Markup) -> String {
        childrenHTML(of: markup)
    }

    private mutating func childrenHTML(of markup: Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    mutating func visitDocument(_ document: Document) -> String {
        childrenHTML(of: document)
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        "<h\(heading.level)>\(childrenHTML(of: heading))</h\(heading.level)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        "<p>\(childrenHTML(of: paragraph))</p>\n"
    }

    mutating func visitText(_ text: Markdown.Text) -> String {
        Self.escape(text.string)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>\(childrenHTML(of: emphasis))</em>"
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        "<strong>\(childrenHTML(of: strong))</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        "<del>\(childrenHTML(of: strikethrough))</del>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(Self.escape(inlineCode.code))</code>"
    }

    /// Code blocks up to this many lines never split across PDF pages (small
    /// enough that moving them whole costs little); longer ones flow freely,
    /// which avoids large end-of-page gaps.
    static let compactCodeBlockLineLimit = 6

    static func lineCount(of codeBlock: CodeBlock) -> Int {
        let lines = codeBlock.code.components(separatedBy: "\n").count
        return codeBlock.code.hasSuffix("\n") ? lines - 1 : lines
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let keepClass = Self.lineCount(of: codeBlock) <= Self.compactCodeBlockLineLimit
            ? " class=\"keep\"" : ""
        let languageClass = codeBlock.language.map { " class=\"language-\(Self.escape($0))\"" } ?? ""
        let body = CodeHighlighter.highlight(codeBlock.code, language: codeBlock.language)
            ?? Self.escape(codeBlock.code)
        return "<pre\(keepClass)><code\(languageClass)>\(body)</code></pre>\n"
    }

    mutating func visitLink(_ link: Markdown.Link) -> String {
        let content = childrenHTML(of: link)
        guard let destination = link.destination, Self.isAllowedLinkDestination(destination) else {
            return content
        }
        return "<a href=\"\(Self.escape(destination))\">\(content)</a>"
    }

    /// Relative links, fragments and the external schemes the app opens.
    /// Anything else (javascript:, data:, file:…) is dropped, keeping the text.
    static func isAllowedLinkDestination(_ destination: String) -> Bool {
        // Browsers skip whitespace and control characters inside a scheme.
        // Read scalar by scalar, as they read it: a combining mark after the
        // colon would hide it inside a single Character.
        let scalars = destination.unicodeScalars.filter { $0.value > 0x20 && $0.value != 0x7F }
        guard let colon = scalars.firstIndex(of: ":") else { return true }
        let scheme = scalars[..<colon]
        // A colon after a path, query or fragment separator isn't a scheme.
        if scheme.contains(where: { "/?#".unicodeScalars.contains($0) }) { return true }
        return ExternalLinks.allowedSchemes.contains(String(String.UnicodeScalarView(scheme)).lowercased())
    }

    mutating func visitImage(_ image: Markdown.Image) -> String {
        let source = Self.escape(image.source ?? "")
        let alt = Self.escape(image.plainText)
        let title = image.title.map { " title=\"\(Self.escape($0))\"" } ?? ""
        return "<img src=\"\(source)\" alt=\"\(alt)\"\(title)>"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        "<ul>\n\(childrenHTML(of: unorderedList))</ul>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        let start = orderedList.startIndex > 1 ? " start=\"\(orderedList.startIndex)\"" : ""
        return "<ol\(start)>\n\(childrenHTML(of: orderedList))</ol>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        var prefix = ""
        var cssClass = ""
        if let checkbox = listItem.checkbox {
            let checked = checkbox == .checked ? " checked" : ""
            prefix = "<input type=\"checkbox\" disabled\(checked)> "
            cssClass = " class=\"task\""
        }

        // swift-markdown always wraps item content in a Paragraph (tightness is
        // not exposed), so unwrap the leading paragraph for the classic tight
        // list rendering; any following blocks keep their own tags.
        var inner = ""
        let children = Array(listItem.children)
        if let firstParagraph = children.first as? Paragraph {
            inner = childrenHTML(of: firstParagraph)
            for child in children.dropFirst() {
                inner += "\n" + visit(child)
            }
        } else {
            inner = children.map { visit($0) }.joined()
        }
        return "<li\(cssClass)>\(prefix)\(inner)</li>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        "<blockquote>\n\(childrenHTML(of: blockQuote))</blockquote>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        "<hr>\n"
    }

    mutating func visitTable(_ table: Markdown.Table) -> String {
        let alignments = table.columnAlignments
        func style(for column: Int) -> String {
            guard column < alignments.count, let alignment = alignments[column] else { return "" }
            switch alignment {
            case .left: return " style=\"text-align:left\""
            case .center: return " style=\"text-align:center\""
            case .right: return " style=\"text-align:right\""
            }
        }

        var html = "<table>\n<thead>\n<tr>"
        for (column, cell) in table.head.cells.enumerated() {
            html += "<th\(style(for: column))>\(childrenHTML(of: cell))</th>"
        }
        html += "</tr>\n</thead>\n<tbody>\n"
        for row in table.body.rows {
            html += "<tr>"
            for (column, cell) in row.cells.enumerated() {
                html += "<td\(style(for: column))>\(childrenHTML(of: cell))</td>"
            }
            html += "</tr>\n"
        }
        html += "</tbody>\n</table>\n"
        return html
    }

    /// By default every Enter is a visible line break (GitHub-comment /
    /// Obsidian style); strict mode keeps CommonMark's fold-into-a-space.
    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        strictLineBreaks ? "\n" : "<br>\n"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        "<br>\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        html.rawHTML
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
        inlineHTML.rawHTML
    }
}

private extension Markdown.Table.Head {
    var cells: [Markdown.Table.Cell] {
        children.compactMap { $0 as? Markdown.Table.Cell }
    }
}

private extension Markdown.Table.Body {
    var rows: [Markdown.Table.Row] {
        children.compactMap { $0 as? Markdown.Table.Row }
    }
}

private extension Markdown.Table.Row {
    var cells: [Markdown.Table.Cell] {
        children.compactMap { $0 as? Markdown.Table.Cell }
    }
}
