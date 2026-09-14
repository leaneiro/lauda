import Foundation
import Testing
@testable import Lauda

struct ExportTests {
    @Test func standaloneContainsRenderedContentAndStyles() {
        let html = PreviewTemplate.standalone(
            title: "My Notes",
            bodyHTML: HTMLRenderer.render("# Title\n\nSome **text**."),
            fontFamily: "Georgia, serif",
            fontSize: 18,
            lineHeight: 1.7
        )
        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("<title>My Notes</title>"))
        #expect(html.contains("<h1>Title</h1>"))
        #expect(html.contains("<strong>text</strong>"))
        #expect(html.contains("--pfont: Georgia, serif;"))
        #expect(html.contains("--psize: 18.0px;"))
        #expect(html.contains("@media print"), "should include the print CSS")
        #expect(!html.contains("<script"), "the exported document has no JS")
    }

    @Test func standaloneEscapesTitle() {
        let html = PreviewTemplate.standalone(
            title: "a < b & \"c\"",
            bodyHTML: "",
            fontFamily: "x",
            fontSize: 16,
            lineHeight: 1.6
        )
        #expect(html.contains("<title>a &lt; b &amp; &quot;c&quot;</title>"))
    }

    @Test func renderForPrintWrapsHeadingsWithProbe() {
        let html = HTMLRenderer.renderForPrint("# Title\n\nParagraph.\n\n## Another\n\nMore text.")
        #expect(html.contains("<div class=\"keep-with-next keep-pad\"><h1>Title</h1>\n<div class=\"keep-probe\"></div></div>"), "got: \(html)")
        #expect(html.contains("<div class=\"keep-with-next keep-pad\"><h2>Another</h2>\n<div class=\"keep-probe\"></div></div>"), "got: \(html)")
        #expect(html.contains("<p>Paragraph.</p>"))
        // The regular (preview) render gets no wrappers.
        #expect(!HTMLRenderer.render("# Title").contains("keep-with-next"))
    }

    @Test func renderForPrintGroupsHeadingWithCompactCodeBlock() {
        let html = HTMLRenderer.renderForPrint("## Code\n\n```swift\nlet x = 1\n```\n\nText after.")
        // The heading and a short block stay together, with no probe.
        #expect(html.contains("<div class=\"keep-with-next\"><h2>Code</h2>\n<pre class=\"keep\">"), "got: \(html)")
        #expect(!html.contains("<h2>Code</h2>\n<div class=\"keep-probe\">"), "got: \(html)")
        #expect(html.contains("</pre>\n</div>"), "got: \(html)")
        #expect(html.contains("<p>Text after.</p>"))
    }

    @Test func renderForPrintUsesProbeBeforeLongCodeBlock() {
        let code = (1...10).map { "let v\($0) = \($0)" }.joined(separator: "\n")
        let html = HTMLRenderer.renderForPrint("## Code\n\n```swift\n\(code)\n```")
        // A long block may break: the heading keeps the probe and the pre flows freely.
        #expect(html.contains("<div class=\"keep-with-next keep-pad\"><h2>Code</h2>\n<div class=\"keep-probe\"></div></div>"), "got: \(html)")
        #expect(html.contains("<pre><code"), "got: \(html)")
    }

    /// Exports carry the wordmark face themselves, so the app's name keeps its
    /// typeface in HTML and PDF, offline.
    @Test func stylesEmbedTheWordmarkFont() throws {
        let styles = PreviewTemplate.styles
        #expect(styles.contains(#"font-family: "Lauda Wordmark""#))
        let start = try #require(styles.range(of: "data:font/woff;base64,"))
        let encoded = styles[start.upperBound...].prefix { $0 != "\"" }
        let font = try #require(Data(base64Encoded: String(encoded)))
        #expect(font.prefix(4) == Data("wOFF".utf8))
    }

    /// The style is passed in, not read from the running Mac's settings, so
    /// the test says the same thing on every machine.
    @Test func standaloneHTMLAppliesTheGivenStyle() {
        let html = DocumentExporter.standaloneHTML(
            markdown: "- item",
            title: "Doc",
            style: PreviewStyle(fontName: FontOption.systemSerif, fontSize: 19, lineHeight: 1.5, strictLineBreaks: false)
        )
        #expect(html.contains("<li>item</li>"))
        #expect(html.contains("--psize: 19.0px;"), "got: \(html.prefix(600))")
    }
}
