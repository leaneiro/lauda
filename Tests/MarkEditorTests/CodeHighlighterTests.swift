import XCTest
@testable import MarkEditor

final class CodeHighlighterTests: XCTestCase {
    func testSwiftKeywordsStringsCommentsNumbers() {
        let html = CodeHighlighter.highlight(
            "// oi\nlet x = \"a < b\" + 42",
            language: "swift"
        )!
        XCTAssertTrue(html.contains("<span class=\"hl-com\">// oi</span>"), "got: \(html)")
        XCTAssertTrue(html.contains("<span class=\"hl-kw\">let</span>"), "got: \(html)")
        XCTAssertTrue(html.contains("<span class=\"hl-str\">&quot;a &lt; b&quot;</span>"), "got: \(html)")
        XCTAssertTrue(html.contains("<span class=\"hl-num\">42</span>"), "got: \(html)")
    }

    func testKeywordInsideStringIsNotHighlighted() {
        let html = CodeHighlighter.highlight("print(\"let if for\")", language: "swift")!
        XCTAssertTrue(html.contains("<span class=\"hl-str\">&quot;let if for&quot;</span>"), "got: \(html)")
        XCTAssertFalse(html.contains("hl-kw"), "got: \(html)")
    }

    func testKeywordInsideCommentIsNotDoubleWrapped() {
        let html = CodeHighlighter.highlight("# for x in y\n", language: "python")!
        XCTAssertTrue(html.contains("<span class=\"hl-com\"># for x in y</span>"), "got: \(html)")
        XCTAssertFalse(html.contains("hl-kw"), "got: \(html)")
    }

    func testEscapedQuoteInsideStringDoesNotEndIt() {
        let html = CodeHighlighter.highlight(#"let s = "a\"b""#, language: "swift")!
        XCTAssertTrue(html.contains("<span class=\"hl-str\">&quot;a\\&quot;b&quot;</span>"), "got: \(html)")
    }

    func testBlockCommentSpansLines() {
        let html = CodeHighlighter.highlight("/* a\nb */ let x", language: "swift")!
        XCTAssertTrue(html.contains("<span class=\"hl-com\">/* a\nb */</span>"), "got: \(html)")
        XCTAssertTrue(html.contains("<span class=\"hl-kw\">let</span>"), "got: \(html)")
    }

    func testUnknownLanguageReturnsNil() {
        XCTAssertNil(CodeHighlighter.highlight("let x = 1", language: "brainfuck"))
        XCTAssertNil(CodeHighlighter.highlight("let x = 1", language: nil))
    }

    func testHTMLIsAlwaysEscaped() {
        let html = CodeHighlighter.highlight("<script>alert('1')</script>", language: "javascript")!
        XCTAssertFalse(html.contains("<script"), "got: \(html)")
        XCTAssertTrue(html.contains("&lt;script&gt;"), "got: \(html)")
    }

    func testLanguageAliases() {
        XCTAssertNotNil(CodeHighlighter.highlight("const a = 1", language: "ts"))
        XCTAssertNotNil(CodeHighlighter.highlight("echo oi", language: "sh"))
        XCTAssertNotNil(CodeHighlighter.highlight("SELECT 1", language: "sql"))
    }

    func testUnterminatedStringDoesNotCrashOrLoop() {
        let html = CodeHighlighter.highlight("let s = \"aberta", language: "swift")!
        XCTAssertTrue(html.contains("hl-str"), "got: \(html)")
    }
}
