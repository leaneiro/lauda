import Foundation
import Testing
@testable import Lauda

struct DocumentSchemeHandlerTests {
    private func resolve(_ path: String) -> URL? {
        DocumentSchemeHandler.resolveTarget(
            for: URL(string: "lauda-doc://\(path)")!,
            baseDirectory: URL(fileURLWithPath: "/Users/someone/Documents/notes")
        )
    }

    @Test func resolvesImageInsideDocumentFolder() {
        #expect(resolve("/figure.png")?.path == "/Users/someone/Documents/notes/figure.png")
    }

    @Test func resolvesImageInSubfolder() {
        #expect(resolve("/img/photo.jpeg")?.path == "/Users/someone/Documents/notes/img/photo.jpeg")
    }

    @Test(arguments: ["/../secret.png", "/img/../../../etc/password.png", "/%2e%2e/secret.png"])
    func rejectsPathTraversal(path: String) {
        #expect(resolve(path) == nil)
    }

    @Test(arguments: ["/key.pem", "/notes.md", "/no-extension"])
    func rejectsNonImageFiles(path: String) {
        #expect(resolve(path) == nil)
    }

    @Test func extensionCheckIsCaseInsensitive() {
        #expect(resolve("/PHOTO.PNG") != nil)
    }
}

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
