import Foundation
import Testing
@testable import MarkEditor

struct CodeHighlighterTests {
    @Test func highlightsSwiftKeywordsStringsCommentsAndNumbers() throws {
        let html = try #require(CodeHighlighter.highlight("// hi\nlet x = \"a < b\" + 42", language: "swift"))
        #expect(html.contains("<span class=\"hl-com\">// hi</span>"), "got: \(html)")
        #expect(html.contains("<span class=\"hl-kw\">let</span>"), "got: \(html)")
        #expect(html.contains("<span class=\"hl-str\">&quot;a &lt; b&quot;</span>"), "got: \(html)")
        #expect(html.contains("<span class=\"hl-num\">42</span>"), "got: \(html)")
    }

    @Test func keywordInsideStringIsNotHighlighted() throws {
        let html = try #require(CodeHighlighter.highlight("print(\"let if for\")", language: "swift"))
        #expect(html.contains("<span class=\"hl-str\">&quot;let if for&quot;</span>"), "got: \(html)")
        #expect(!html.contains("hl-kw"), "got: \(html)")
    }

    @Test func keywordInsideCommentIsNotDoubleWrapped() throws {
        let html = try #require(CodeHighlighter.highlight("# for x in y\n", language: "python"))
        #expect(html.contains("<span class=\"hl-com\"># for x in y</span>"), "got: \(html)")
        #expect(!html.contains("hl-kw"), "got: \(html)")
    }

    @Test func escapedQuoteInsideStringDoesNotEndIt() throws {
        let html = try #require(CodeHighlighter.highlight(#"let s = "a\"b""#, language: "swift"))
        #expect(html.contains("<span class=\"hl-str\">&quot;a\\&quot;b&quot;</span>"), "got: \(html)")
    }

    @Test func blockCommentSpansLines() throws {
        let html = try #require(CodeHighlighter.highlight("/* a\nb */ let x", language: "swift"))
        #expect(html.contains("<span class=\"hl-com\">/* a\nb */</span>"), "got: \(html)")
        #expect(html.contains("<span class=\"hl-kw\">let</span>"), "got: \(html)")
    }

    @Test func unknownLanguageReturnsNil() {
        #expect(CodeHighlighter.highlight("let x = 1", language: "brainfuck") == nil)
        #expect(CodeHighlighter.highlight("let x = 1", language: nil) == nil)
    }

    @Test func htmlIsAlwaysEscaped() throws {
        let html = try #require(CodeHighlighter.highlight("<script>alert('1')</script>", language: "javascript"))
        #expect(!html.contains("<script"), "got: \(html)")
        #expect(html.contains("&lt;script&gt;"), "got: \(html)")
    }

    @Test(arguments: [("ts", "const a = 1"), ("sh", "echo hi"), ("sql", "SELECT 1")])
    func languageAliases(alias: String, code: String) {
        #expect(CodeHighlighter.highlight(code, language: alias) != nil)
    }

    @Test func unterminatedStringDoesNotCrashOrLoop() throws {
        let html = try #require(CodeHighlighter.highlight("let s = \"unclosed", language: "swift"))
        #expect(html.contains("hl-str"), "got: \(html)")
    }
}
