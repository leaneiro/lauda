import Foundation
import Testing
@testable import Lauda

struct MarkdownDocumentDecodingTests {
    @Test func decodesUTF8() throws {
        #expect(try MarkdownDocument.decode(Data("Café, naïve façade!".utf8)) == "Café, naïve façade!")
    }

    @Test func fallsBackToLatin1WithoutLoss() throws {
        let data = try #require("Café, naïve façade!".data(using: .isoLatin1))
        let decoded = try MarkdownDocument.decode(data)
        #expect(decoded == "Café, naïve façade!")
        #expect(!decoded.contains("\u{FFFD}"))
    }
}
