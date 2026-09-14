import Foundation
import Testing
@testable import Lauda

struct WelcomeGuideTests {
    private static let welcomeDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources/Welcome")

    @Test(arguments: ["en", "pt-BR", "de", "es", "fr", "ja", "zh-Hans"])
    func everyAppLanguageHasAGuideThatRenders(language: String) throws {
        let url = Self.welcomeDirectory.appendingPathComponent("\(language).lproj/Welcome.md")
        let text = try String(contentsOf: url, encoding: .utf8)
        let outline = Outline.items(in: text)
        #expect(outline.first?.level == 1, "\(language)")
        #expect(outline.count == 8, "\(language): the guide shows off the outline")
        let html = HTMLRenderer.render(text)
        // Emphasis next to CJK punctuation can fail to parse; none may leak.
        #expect(!html.contains("**"), "\(language)")
        // The app's name is set in the icon's typeface wherever the guide names it.
        #expect(html.contains(#"<span class="wordmark">Lauda</span>"#), "\(language)")
        #expect(outline.first?.title.contains("Lauda") == true, "\(language)")
        #expect(outline.first?.title.contains("<") == false, "\(language)")
    }
}
