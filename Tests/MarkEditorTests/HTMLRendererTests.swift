import XCTest
@testable import MarkEditor

final class HTMLRendererTests: XCTestCase {
    func testHeading() {
        XCTAssertEqual(HTMLRenderer.render("## Title"), "<h2>Title</h2>\n")
    }

    func testParagraphWithInlineStyles() {
        let html = HTMLRenderer.render("Some **bold**, *italic* and `code`.")
        XCTAssertEqual(html, "<p>Some <strong>bold</strong>, <em>italic</em> and <code>code</code>.</p>\n")
    }

    func testStrikethrough() {
        XCTAssertEqual(HTMLRenderer.render("~~struck~~"), "<p><del>struck</del></p>\n")
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
        XCTAssertTrue(html.hasPrefix("<pre><code"), "a long block has no class=keep, got: \(html.prefix(60))")
    }

    func testLink() {
        let html = HTMLRenderer.render("[site](https://example.com)")
        XCTAssertEqual(html, "<p><a href=\"https://example.com\">site</a></p>\n")
    }

    func testImage() {
        let html = HTMLRenderer.render("![alt](figure.png)")
        XCTAssertEqual(html, "<p><img src=\"figure.png\" alt=\"alt\"></p>\n")
    }

    func testUnorderedList() {
        let html = HTMLRenderer.render("- one\n- two")
        XCTAssertEqual(html, "<ul>\n<li>one</li>\n<li>two</li>\n</ul>\n")
    }

    func testOrderedListWithCustomStart() {
        let html = HTMLRenderer.render("3. three\n4. four")
        XCTAssertTrue(html.hasPrefix("<ol start=\"3\">"), "got: \(html)")
    }

    func testTaskList() {
        let html = HTMLRenderer.render("- [x] done\n- [ ] pending")
        XCTAssertTrue(html.contains("<li class=\"task\"><input type=\"checkbox\" disabled checked> done</li>"), "got: \(html)")
        XCTAssertTrue(html.contains("<li class=\"task\"><input type=\"checkbox\" disabled> pending</li>"), "got: \(html)")
    }

    func testBlockQuote() {
        let html = HTMLRenderer.render("> quote")
        XCTAssertEqual(html, "<blockquote>\n<p>quote</p>\n</blockquote>\n")
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
        let html = HTMLRenderer.render("line one  \nline two")
        XCTAssertTrue(html.contains("<br>"), "got: \(html)")
    }

    func testSingleEnterBecomesLineBreak() {
        XCTAssertEqual(
            HTMLRenderer.render("first line\nsecond line"),
            "<p>first line<br>\nsecond line</p>\n"
        )
    }

    func testStrictModeFoldsSingleEnterLikeCommonMark() {
        XCTAssertEqual(
            HTMLRenderer.render("first line\nsecond line", strictLineBreaks: true),
            "<p>first line\nsecond line</p>\n"
        )
    }

    func testStrictModeStillHonorsHardBreaks() {
        let html = HTMLRenderer.render("line one  \nline two", strictLineBreaks: true)
        XCTAssertTrue(html.contains("line one<br>\nline two"), "got: \(html)")
    }

    func testStrictModeAppliesToPrintRendering() {
        let html = HTMLRenderer.renderForPrint("# T\n\na\nb", strictLineBreaks: true)
        XCTAssertTrue(html.contains("<p>a\nb</p>"), "got: \(html)")
        XCTAssertTrue(HTMLRenderer.renderForPrint("# T\n\na\nb").contains("<p>a<br>\nb</p>"))
    }

    func testRenderWithLinesMapsEachTopLevelBlock() {
        let markdown = "# Title\n\nParagraph one\ncontinues\n\n- a\n- b\n\n```\ncode\n```\n"
        let result = HTMLRenderer.renderWithLines(markdown)
        XCTAssertEqual(result.blockLines, [0, 2, 5, 8])
        XCTAssertEqual(result.lineCount, 12)
        XCTAssertEqual(result.html, HTMLRenderer.render(markdown))
    }

    func testRenderWithLinesWrapsRawHTMLIntoOneElement() {
        let result = HTMLRenderer.renderWithLines("<div>a</div>\n<div>b</div>\n\ntext")
        XCTAssertEqual(result.blockLines, [0, 3])
        XCTAssertTrue(result.html.hasPrefix("<div><div>a</div>\n<div>b</div>"), "got: \(result.html)")
    }

    func testBlankLineStillStartsNewParagraph() {
        XCTAssertEqual(
            HTMLRenderer.render("one\n\ntwo"),
            "<p>one</p>\n<p>two</p>\n"
        )
    }

    func testSingleEnterInsideListItemBecomesLineBreak() {
        let html = HTMLRenderer.render("- item\n  continued")
        XCTAssertTrue(html.contains("<li>item<br>\ncontinued</li>"), "got: \(html)")
    }

    func testCodeBlockKeepsPlainNewlines() {
        let html = HTMLRenderer.render("```\na\nb\n```")
        XCTAssertFalse(html.contains("<br>"), "got: \(html)")
    }

    func testRawHTMLPassesThrough() {
        let html = HTMLRenderer.render("<div>block</div>")
        XCTAssertTrue(html.contains("<div>block</div>"), "got: \(html)")
    }

    func testEmptyDocument() {
        XCTAssertEqual(HTMLRenderer.render(""), "")
    }
}
