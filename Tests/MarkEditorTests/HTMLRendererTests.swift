import XCTest
@testable import MarkEditor

final class HTMLRendererTests: XCTestCase {
    func testHeading() {
        XCTAssertEqual(HTMLRenderer.render("## Título"), "<h2>Título</h2>\n")
    }

    func testParagraphWithInlineStyles() {
        let html = HTMLRenderer.render("Um **negrito**, *itálico* e `código`.")
        XCTAssertEqual(html, "<p>Um <strong>negrito</strong>, <em>itálico</em> e <code>código</code>.</p>\n")
    }

    func testStrikethrough() {
        XCTAssertEqual(HTMLRenderer.render("~~riscado~~"), "<p><del>riscado</del></p>\n")
    }

    func testEscapesHTMLInText() {
        let html = HTMLRenderer.render("a < b & c > d")
        XCTAssertTrue(html.contains("a &lt; b &amp; c &gt; d"))
    }

    func testCodeBlockWithLanguageIsEscapedAndHighlighted() {
        let html = HTMLRenderer.render("```swift\nlet x = a < b\n```")
        XCTAssertTrue(html.hasPrefix("<pre class=\"keep\"><code class=\"language-swift\">"), "got: \(html)")
        XCTAssertTrue(html.contains("<span class=\"hl-kw\">let</span> x = a &lt; b"), "got: \(html)")
    }

    func testCodeBlockWithoutLanguageStaysPlain() {
        let html = HTMLRenderer.render("```\nlet x = a < b\n```")
        XCTAssertEqual(html, "<pre class=\"keep\"><code>let x = a &lt; b\n</code></pre>\n")
    }

    func testLongCodeBlockIsAllowedToBreakAcrossPages() {
        let code = (1...10).map { "let v\($0) = \($0)" }.joined(separator: "\n")
        let html = HTMLRenderer.render("```swift\n\(code)\n```")
        XCTAssertTrue(html.hasPrefix("<pre><code"), "bloco longo não leva class=keep — got: \(html.prefix(60))")
    }

    func testLink() {
        let html = HTMLRenderer.render("[site](https://example.com)")
        XCTAssertEqual(html, "<p><a href=\"https://example.com\">site</a></p>\n")
    }

    func testImage() {
        let html = HTMLRenderer.render("![alt](figura.png)")
        XCTAssertEqual(html, "<p><img src=\"figura.png\" alt=\"alt\"></p>\n")
    }

    func testUnorderedList() {
        let html = HTMLRenderer.render("- um\n- dois")
        XCTAssertEqual(html, "<ul>\n<li>um</li>\n<li>dois</li>\n</ul>\n")
    }

    func testOrderedListWithCustomStart() {
        let html = HTMLRenderer.render("3. três\n4. quatro")
        XCTAssertTrue(html.hasPrefix("<ol start=\"3\">"), "got: \(html)")
    }

    func testTaskList() {
        let html = HTMLRenderer.render("- [x] feito\n- [ ] pendente")
        XCTAssertTrue(html.contains("<li class=\"task\"><input type=\"checkbox\" disabled checked> feito</li>"), "got: \(html)")
        XCTAssertTrue(html.contains("<li class=\"task\"><input type=\"checkbox\" disabled> pendente</li>"), "got: \(html)")
    }

    func testBlockQuote() {
        let html = HTMLRenderer.render("> citação")
        XCTAssertEqual(html, "<blockquote>\n<p>citação</p>\n</blockquote>\n")
    }

    func testThematicBreak() {
        XCTAssertEqual(HTMLRenderer.render("---"), "<hr>\n")
    }

    func testTableWithAlignments() {
        let markdown = """
        | a | b | c |
        |:--|:-:|--:|
        | 1 | 2 | 3 |
        """
        let html = HTMLRenderer.render(markdown)
        XCTAssertTrue(html.contains("<th style=\"text-align:left\">a</th>"), "got: \(html)")
        XCTAssertTrue(html.contains("<th style=\"text-align:center\">b</th>"), "got: \(html)")
        XCTAssertTrue(html.contains("<td style=\"text-align:right\">3</td>"), "got: \(html)")
    }

    func testHardLineBreak() {
        let html = HTMLRenderer.render("linha um  \nlinha dois")
        XCTAssertTrue(html.contains("<br>"), "got: \(html)")
    }

    func testRawHTMLPassesThrough() {
        let html = HTMLRenderer.render("<div>bloco</div>")
        XCTAssertTrue(html.contains("<div>bloco</div>"), "got: \(html)")
    }

    func testEmptyDocument() {
        XCTAssertEqual(HTMLRenderer.render(""), "")
    }
}
