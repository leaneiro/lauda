import XCTest
@testable import MarkEditor

final class DocumentSchemeHandlerTests: XCTestCase {
    private let base = URL(fileURLWithPath: "/Users/alguem/Documentos/notas")

    private func resolve(_ path: String) -> URL? {
        DocumentSchemeHandler.resolveTarget(
            for: URL(string: "markeditor-doc://\(path)")!,
            baseDirectory: base
        )
    }

    func testResolvesImageInsideDocumentFolder() {
        XCTAssertEqual(resolve("/figura.png")?.path, "/Users/alguem/Documentos/notas/figura.png")
    }

    func testResolvesImageInSubfolder() {
        XCTAssertEqual(resolve("/img/foto.jpeg")?.path, "/Users/alguem/Documentos/notas/img/foto.jpeg")
    }

    func testRejectsPathTraversal() {
        XCTAssertNil(resolve("/../segredo.png"))
        XCTAssertNil(resolve("/img/../../../etc/senha.png"))
    }

    func testRejectsPercentEncodedTraversal() {
        XCTAssertNil(resolve("/%2e%2e/segredo.png"))
    }

    func testRejectsNonImageFiles() {
        XCTAssertNil(resolve("/chave.pem"))
        XCTAssertNil(resolve("/notas.md"))
        XCTAssertNil(resolve("/sem-extensao"))
    }

    func testExtensionCheckIsCaseInsensitive() {
        XCTAssertNotNil(resolve("/FOTO.PNG"))
    }
}

final class MarkdownDocumentDecodingTests: XCTestCase {
    func testDecodesUTF8() throws {
        let data = Data("Olá, coração!".utf8)
        XCTAssertEqual(try MarkdownDocument.decode(data), "Olá, coração!")
    }

    func testFallsBackToLatin1WithoutLoss() throws {
        let data = "Olá, coração!".data(using: .isoLatin1)!
        let decoded = try MarkdownDocument.decode(data)
        XCTAssertEqual(decoded, "Olá, coração!")
        XCTAssertFalse(decoded.contains("\u{FFFD}"))
    }
}
