import XCTest
@testable import MarkEditor

final class WelcomeGuideTests: XCTestCase {
    private let welcomeDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources/Welcome")

    func testEveryAppLanguageHasAGuideThatRenders() throws {
        for language in ["en", "pt-BR", "de", "es", "fr", "ja", "zh-Hans"] {
            let url = welcomeDirectory.appendingPathComponent("\(language).lproj/Welcome.md")
            let text = try String(contentsOf: url, encoding: .utf8)
            let outline = Outline.items(in: text)
            XCTAssertEqual(outline.first?.level, 1, language)
            XCTAssertEqual(outline.count, 8, "\(language): the guide shows off the outline")
            // Emphasis next to CJK punctuation can fail to parse; none may leak.
            XCTAssertFalse(HTMLRenderer.render(text).contains("**"), language)
        }
    }
}
