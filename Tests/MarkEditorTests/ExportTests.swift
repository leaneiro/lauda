import XCTest
@testable import MarkEditor

final class ExportTests: XCTestCase {
    func testStandaloneContainsRenderedContentAndStyles() {
        let html = PreviewTemplate.standalone(
            title: "Minhas Notas",
            bodyHTML: HTMLRenderer.render("# Título\n\nUm **texto**."),
            fontFamily: "Georgia, serif",
            fontSize: 18,
            lineHeight: 1.7
        )
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("<title>Minhas Notas</title>"))
        XCTAssertTrue(html.contains("<h1>Título</h1>"))
        XCTAssertTrue(html.contains("<strong>texto</strong>"))
        XCTAssertTrue(html.contains("--pfont: Georgia, serif;"))
        XCTAssertTrue(html.contains("--psize: 18.0px;"))
        XCTAssertTrue(html.contains("@media print"), "deve levar o CSS de impressão")
        XCTAssertFalse(html.contains("<script"), "documento exportado não leva JS")
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
        let html = HTMLRenderer.renderForPrint("# Título\n\nParágrafo.\n\n## Outro\n\nMais texto.")
        XCTAssertTrue(html.contains("<div class=\"keep-with-next keep-pad\"><h1>Título</h1>\n<div class=\"keep-probe\"></div></div>"), "got: \(html)")
        XCTAssertTrue(html.contains("<div class=\"keep-with-next keep-pad\"><h2>Outro</h2>\n<div class=\"keep-probe\"></div></div>"), "got: \(html)")
        XCTAssertTrue(html.contains("<p>Parágrafo.</p>"))
        // O render normal (preview) não ganha wrappers.
        XCTAssertFalse(HTMLRenderer.render("# Título").contains("keep-with-next"))
    }

    func testRenderForPrintGroupsHeadingWithUnbreakableBlock() {
        let html = HTMLRenderer.renderForPrint("## Código\n\n```swift\nlet x = 1\n```\n\nTexto depois.")
        // Título + bloco de código viajam juntos, sem sonda.
        XCTAssertTrue(html.contains("<div class=\"keep-with-next\"><h2>Código</h2>\n<pre>"), "got: \(html)")
        XCTAssertFalse(html.contains("<h2>Código</h2>\n<div class=\"keep-probe\">"), "got: \(html)")
        XCTAssertTrue(html.contains("</pre>\n</div>"), "got: \(html)")
        XCTAssertTrue(html.contains("<p>Texto depois.</p>"))
    }

    func testStandaloneHTMLUsesDefaultsWhenUnset() {
        let html = DocumentExporter.standaloneHTML(markdown: "- item", title: "Doc")
        XCTAssertTrue(html.contains("<li>item</li>"))
        XCTAssertTrue(html.contains("--pfont:"))
    }
}
