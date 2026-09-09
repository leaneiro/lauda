import Foundation
import Markdown

/// Renders a swift-markdown AST to HTML for the preview pane.
struct HTMLRenderer: MarkupVisitor {
    typealias Result = String

    static func render(_ markdown: String) -> String {
        let document = Document(parsing: markdown)
        var renderer = HTMLRenderer()
        return renderer.visit(document)
    }

    /// Print-oriented rendering: each top-level heading is wrapped together
    /// with an invisible probe that reserves a couple of lines below it.
    /// `break-inside: avoid` on the wrapper then pushes the heading to the
    /// next page instead of leaving it orphaned at the bottom (WebKit's print
    /// engine ignores `break-after: avoid`, so this is the reliable route).
    static func renderForPrint(_ markdown: String) -> String {
        let document = Document(parsing: markdown)
        var renderer = HTMLRenderer()
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
    private static func avoidsInnerBreaks(_ markup: Markup) -> Bool {
        markup is CodeBlock || markup is Markdown.Table || markup is BlockQuote
    }

    // MARK: - Escaping

    static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
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

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let languageClass = codeBlock.language.map { " class=\"language-\(Self.escape($0))\"" } ?? ""
        let body = CodeHighlighter.highlight(codeBlock.code, language: codeBlock.language)
            ?? Self.escape(codeBlock.code)
        return "<pre><code\(languageClass)>\(body)</code></pre>\n"
    }

    mutating func visitLink(_ link: Markdown.Link) -> String {
        let destination = Self.escape(link.destination ?? "")
        return "<a href=\"\(destination)\">\(childrenHTML(of: link))</a>"
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

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        "\n"
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
