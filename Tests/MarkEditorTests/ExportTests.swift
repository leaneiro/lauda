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

    func testStandaloneHTMLUsesDefaultsWhenUnset() {
        let html = DocumentExporter.standaloneHTML(markdown: "- item", title: "Doc")
        XCTAssertTrue(html.contains("<li>item</li>"))
        XCTAssertTrue(html.contains("--pfont:"))
    }
}
