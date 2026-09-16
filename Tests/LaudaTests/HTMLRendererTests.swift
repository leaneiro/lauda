import Foundation
import Testing
@testable import Lauda

struct HTMLRendererTests {
    @Test func heading() {
        #expect(HTMLRenderer.render("## Title") == "<h2>Title</h2>\n")
    }

    @Test func paragraphWithInlineStyles() {
        #expect(HTMLRenderer.render("Some **bold**, *italic* and `code`.")
            == "<p>Some <strong>bold</strong>, <em>italic</em> and <code>code</code>.</p>\n")
    }

    @Test func strikethrough() {
        #expect(HTMLRenderer.render("~~struck~~") == "<p><del>struck</del></p>\n")
    }

    @Test func escapesHTMLInText() {
        #expect(HTMLRenderer.render("a < b & c > d").contains("a &lt; b &amp; c &gt; d"))
    }

    @Test func codeBlockWithLanguageIsEscapedAndHighlighted() {
        let html = HTMLRenderer.render("```swift\nlet x = a < b\n```")
        #expect(html.hasPrefix("<pre class=\"keep\"><code class=\"language-swift\">"), "got: \(html)")
        #expect(html.contains("<span class=\"hl-kw\">let</span> x = a &lt; b"), "got: \(html)")
    }

    @Test func codeBlockWithoutLanguageStaysPlain() {
        #expect(HTMLRenderer.render("```\nlet x = a < b\n```")
            == "<pre class=\"keep\"><code>let x = a &lt; b\n</code></pre>\n")
    }

    @Test func longCodeBlockIsAllowedToBreakAcrossPages() {
        let code = (1...10).map { "let v\($0) = \($0)" }.joined(separator: "\n")
        let html = HTMLRenderer.render("```swift\n\(code)\n```")
        #expect(html.hasPrefix("<pre><code"), "a long block has no class=keep, got: \(html.prefix(60))")
    }

    @Test func link() {
        #expect(HTMLRenderer.render("[site](https://example.com)")
            == "<p><a href=\"https://example.com\">site</a></p>\n")
    }

    @Test func image() {
        #expect(HTMLRenderer.render("![alt](figure.png)") == "<p><img src=\"figure.png\" alt=\"alt\"></p>\n")
    }

    @Test func unorderedList() {
        #expect(HTMLRenderer.render("- one\n- two") == "<ul>\n<li>one</li>\n<li>two</li>\n</ul>\n")
    }

    @Test func orderedListWithCustomStart() {
        let html = HTMLRenderer.render("3. three\n4. four")
        #expect(html.hasPrefix("<ol start=\"3\">"), "got: \(html)")
    }

    @Test func taskList() {
        let html = HTMLRenderer.render("- [x] done\n- [ ] pending")
        #expect(html.contains("<li class=\"task\"><input type=\"checkbox\" disabled checked> done</li>"), "got: \(html)")
        #expect(html.contains("<li class=\"task\"><input type=\"checkbox\" disabled> pending</li>"), "got: \(html)")
    }

    @Test func blockQuote() {
        #expect(HTMLRenderer.render("> quote") == "<blockquote>\n<p>quote</p>\n</blockquote>\n")
    }

    @Test func thematicBreak() {
        #expect(HTMLRenderer.render("---") == "<hr>\n")
    }

    @Test func tableWithAlignments() {
        let markdown = """
        | a | b | c |
        |:--|:-:|--:|
        | 1 | 2 | 3 |
        """
        let html = HTMLRenderer.render(markdown)
        #expect(html.contains("<th style=\"text-align:left\">a</th>"), "got: \(html)")
        #expect(html.contains("<th style=\"text-align:center\">b</th>"), "got: \(html)")
        #expect(html.contains("<td style=\"text-align:right\">3</td>"), "got: \(html)")
    }

    @Test func hardLineBreak() {
        let html = HTMLRenderer.render("line one  \nline two")
        #expect(html.contains("<br>"), "got: \(html)")
    }

    @Test func singleEnterBecomesLineBreak() {
        #expect(HTMLRenderer.render("first line\nsecond line") == "<p>first line<br>\nsecond line</p>\n")
    }

    @Test func strictModeFoldsSingleEnterLikeCommonMark() {
        #expect(HTMLRenderer.render("first line\nsecond line", strictLineBreaks: true)
            == "<p>first line\nsecond line</p>\n")
    }

    @Test func strictModeStillHonorsHardBreaks() {
        let html = HTMLRenderer.render("line one  \nline two", strictLineBreaks: true)
        #expect(html.contains("line one<br>\nline two"), "got: \(html)")
    }

    @Test func strictModeAppliesToPrintRendering() {
        let html = HTMLRenderer.renderForPrint("# T\n\na\nb", strictLineBreaks: true)
        #expect(html.contains("<p>a\nb</p>"), "got: \(html)")
        #expect(HTMLRenderer.renderForPrint("# T\n\na\nb").contains("<p>a<br>\nb</p>"))
    }

    @Test func renderWithLinesMapsEachTopLevelBlock() {
        let markdown = "# Title\n\nParagraph one\ncontinues\n\n- a\n- b\n\n```\ncode\n```\n"
        let result = HTMLRenderer.renderWithLines(markdown)
        // The heading, the paragraph, the list with its two items, the code.
        #expect(result.anchorLines == [0, 2, 5, 5, 6, 8])
        #expect(result.lineCount == 12)
        #expect(result.html == HTMLRenderer.render(markdown))
    }

    @Test func renderWithLinesAnchorsTableRows() {
        let result = HTMLRenderer.renderWithLines("| h |\n| - |\n| r |\n| s |")
        // The table, its head row, then one anchor per body row.
        #expect(result.anchorLines == [0, 0, 2, 3])
    }

    @Test func renderWithLinesAnchorsNestedItemsInDocumentOrder() {
        let result = HTMLRenderer.renderWithLines("- a\n  - b\n- c")
        // The list, item a, the nested item b inside it, then item c.
        #expect(result.anchorLines == [0, 0, 1, 2])
    }

    @Test func renderWithLinesWrapsRawHTMLIntoOneElement() {
        let result = HTMLRenderer.renderWithLines("<div>a</div>\n<div>b</div>\n\ntext")
        #expect(result.anchorLines == [0, 3])
        #expect(result.html.hasPrefix("<div class=\"raw\"><div>a</div>\n<div>b</div>"), "got: \(result.html)")
    }

    /// Elements inside raw HTML map to no source line, so they must not
    /// shift the anchors that follow them.
    @Test func renderWithLinesSkipsItemsInsideRawHTML() {
        let result = HTMLRenderer.renderWithLines("<ul><li>raw</li></ul>\n\n- real")
        #expect(result.anchorLines == [0, 2, 2])
    }

    @Test func blankLineStillStartsNewParagraph() {
        #expect(HTMLRenderer.render("one\n\ntwo") == "<p>one</p>\n<p>two</p>\n")
    }

    @Test func singleEnterInsideListItemBecomesLineBreak() {
        let html = HTMLRenderer.render("- item\n  continued")
        #expect(html.contains("<li>item<br>\ncontinued</li>"), "got: \(html)")
    }

    @Test func codeBlockKeepsPlainNewlines() {
        let html = HTMLRenderer.render("```\na\nb\n```")
        #expect(!html.contains("<br>"), "got: \(html)")
    }

    @Test func rawHTMLPassesThrough() {
        let html = HTMLRenderer.render("<div>block</div>")
        #expect(html.contains("<div>block</div>"), "got: \(html)")
    }

    @Test func emptyDocument() {
        #expect(HTMLRenderer.render("") == "")
    }
}
