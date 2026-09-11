import XCTest
@testable import MarkEditor

final class DocumentSchemeHandlerTests: XCTestCase {
    private let base = URL(fileURLWithPath: "/Users/someone/Documents/notes")

    private func resolve(_ path: String) -> URL? {
        DocumentSchemeHandler.resolveTarget(
            for: URL(string: "markeditor-doc://\(path)")!,
            baseDirectory: base
        )
    }

    func testResolvesImageInsideDocumentFolder() {
        XCTAssertEqual(resolve("/figure.png")?.path, "/Users/someone/Documents/notes/figure.png")
    }

    func testResolvesImageInSubfolder() {
        XCTAssertEqual(resolve("/img/photo.jpeg")?.path, "/Users/someone/Documents/notes/img/photo.jpeg")
    }

    func testRejectsPathTraversal() {
        XCTAssertNil(resolve("/../secret.png"))
        XCTAssertNil(resolve("/img/../../../etc/password.png"))
    }

    func testRejectsPercentEncodedTraversal() {
        XCTAssertNil(resolve("/%2e%2e/secret.png"))
    }

    func testRejectsNonImageFiles() {
        XCTAssertNil(resolve("/key.pem"))
        XCTAssertNil(resolve("/notes.md"))
        XCTAssertNil(resolve("/no-extension"))
    }

    func testExtensionCheckIsCaseInsensitive() {
        XCTAssertNotNil(resolve("/PHOTO.PNG"))
    }
}

final class MarkdownDocumentDecodingTests: XCTestCase {
    func testDecodesUTF8() throws {
        let data = Data("Café, naïve façade!".utf8)
        XCTAssertEqual(try MarkdownDocument.decode(data), "Café, naïve façade!")
    }

    func testFallsBackToLatin1WithoutLoss() throws {
        let data = "Café, naïve façade!".data(using: .isoLatin1)!
        let decoded = try MarkdownDocument.decode(data)
        XCTAssertEqual(decoded, "Café, naïve façade!")
        XCTAssertFalse(decoded.contains("\u{FFFD}"))
    }
}
