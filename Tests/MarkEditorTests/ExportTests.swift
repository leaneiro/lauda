import XCTest
@testable import MarkEditor

final class ExportTests: XCTestCase {
    func testStandaloneContainsRenderedContentAndStyles() {
        let html = PreviewTemplate.standalone(
            title: "My Notes",
            bodyHTML: HTMLRenderer.render("# Title\n\nSome **text**."),
            fontFamily: "Georgia, serif",
            fontSize: 18,
            lineHeight: 1.7
        )
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("<title>My Notes</title>"))
        XCTAssertTrue(html.contains("<h1>Title</h1>"))
        XCTAssertTrue(html.contains("<strong>text</strong>"))
        XCTAssertTrue(html.contains("--pfont: Georgia, serif;"))
        XCTAssertTrue(html.contains("--psize: 18.0px;"))
        XCTAssertTrue(html.contains("@media print"), "should include the print CSS")
        XCTAssertFalse(html.contains("<script"), "the exported document has no JS")
    }

    func testStandaloneEscapesTitle() {
        let html = PreviewTemplate.standalone(
            title: "a < b & \"c\"",
            bodyHTML: "",
            fontFamily: "x",
            fontSize: 16,
            lineHeight: 1.6
        )
        XCTAssertTrue(html.contains("<title>a &lt; b &amp; &quot;c&quot;</title>"))
    }

    func testRenderForPrintWrapsHeadingsWithProbe() {
        let html = HTMLRenderer.renderForPrint("# Title\n\nParagraph.\n\n## Another\n\nMore text.")
        XCTAssertTrue(html.contains("<div class=\"keep-with-next keep-pad\"><h1>Title</h1>\n<div class=\"keep-probe\"></div></div>"), "got: \(html)")
        XCTAssertTrue(html.contains("<div class=\"keep-with-next keep-pad\"><h2>Another</h2>\n<div class=\"keep-probe\"></div></div>"), "got: \(html)")
        XCTAssertTrue(html.contains("<p>Paragraph.</p>"))
        // The regular (preview) render gets no wrappers.
        XCTAssertFalse(HTMLRenderer.render("# Title").contains("keep-with-next"))
    }

    func testRenderForPrintGroupsHeadingWithCompactCodeBlock() {
        let html = HTMLRenderer.renderForPrint("## Code\n\n```swift\nlet x = 1\n```\n\nText after.")
        // The heading and a short block stay together, with no probe.
        XCTAssertTrue(html.contains("<div class=\"keep-with-next\"><h2>Code</h2>\n<pre class=\"keep\">"), "got: \(html)")
        XCTAssertFalse(html.contains("<h2>Code</h2>\n<div class=\"keep-probe\">"), "got: \(html)")
        XCTAssertTrue(html.contains("</pre>\n</div>"), "got: \(html)")
        XCTAssertTrue(html.contains("<p>Text after.</p>"))
    }

    func testRenderForPrintUsesProbeBeforeLongCodeBlock() {
        let code = (1...10).map { "let v\($0) = \($0)" }.joined(separator: "\n")
        let html = HTMLRenderer.renderForPrint("## Code\n\n```swift\n\(code)\n```")
        // A long block may break: the heading keeps the probe and the pre flows freely.
        XCTAssertTrue(html.contains("<div class=\"keep-with-next keep-pad\"><h2>Code</h2>\n<div class=\"keep-probe\"></div></div>"), "got: \(html)")
        XCTAssertTrue(html.contains("<pre><code"), "got: \(html)")
    }

    func testStandaloneHTMLUsesDefaultsWhenUnset() {
        let html = DocumentExporter.standaloneHTML(markdown: "- item", title: "Doc")
        XCTAssertTrue(html.contains("<li>item</li>"))
        XCTAssertTrue(html.contains("--pfont:"))
    }
}
