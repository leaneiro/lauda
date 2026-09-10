import XCTest
import SwiftUI
@testable import MarkEditor

final class ImageImporterTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("images-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makePNG(_ name: String, in folder: URL? = nil) throws -> URL {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let url = (folder ?? directory).appendingPathComponent(name)
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    func testIsImageFile() {
        XCTAssertTrue(ImageImporter.isImageFile(URL(fileURLWithPath: "/x/foto.PNG")))
        XCTAssertTrue(ImageImporter.isImageFile(URL(fileURLWithPath: "/x/a.jpeg")))
        XCTAssertFalse(ImageImporter.isImageFile(URL(fileURLWithPath: "/x/notas.md")))
    }

    func testImportCopiesExternalImage() throws {
        let external = FileManager.default.temporaryDirectory
            .appendingPathComponent("ext-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: external) }
        let source = try makePNG("foto.png", in: external)

        let path = ImageImporter.importImage(from: source, into: directory)
        XCTAssertEqual(path, "foto.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("foto.png").path))
    }

    func testImportResolvesNameCollision() throws {
        _ = try makePNG("foto.png")
        let external = FileManager.default.temporaryDirectory
            .appendingPathComponent("ext-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: external) }
        let source = try makePNG("foto.png", in: external)

        XCTAssertEqual(ImageImporter.importImage(from: source, into: directory), "foto-2.png")
    }

    func testImageAlreadyInsideFolderIsReferencedWithoutCopy() throws {
        let source = try makePNG("local.png")
        XCTAssertEqual(ImageImporter.importImage(from: source, into: directory), "local.png")

        let sub = directory.appendingPathComponent("img")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let nested = try makePNG("dentro.png", in: sub)
        XCTAssertEqual(ImageImporter.importImage(from: nested, into: directory), "img/dentro.png")
    }

    func testSaveImageDataWritesPNG() throws {
        let source = try makePNG("base.png")
        let name = ImageImporter.saveImageData(try Data(contentsOf: source), in: directory)
        XCTAssertNotNil(name)
        XCTAssertTrue(name!.hasPrefix("imagem-"))
        XCTAssertTrue(name!.hasSuffix(".png"))
    }

    func testMarkdownEncodesSpaces() {
        XCTAssertEqual(
            ImageImporter.markdown(forRelativePaths: ["minha foto.png"]),
            "![](minha%20foto.png)"
        )
        XCTAssertEqual(
            ImageImporter.markdown(forRelativePaths: ["a.png", "b.png"]),
            "![](a.png)\n\n![](b.png)"
        )
    }

    @MainActor
    func testCoordinatorInsertsImageMarkdownAtCaret() throws {
        let documentURL = directory.appendingPathComponent("notas.md")
        try "texto".write(to: documentURL, atomically: true, encoding: .utf8)
        let external = FileManager.default.temporaryDirectory
            .appendingPathComponent("ext-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: external) }
        let image = try makePNG("grafico.png", in: external)

        let view = MarkdownTextView(
            text: .constant(""),
            scrollSync: .constant(ScrollSync()),
            actions: EditorActions(),
            fileURL: documentURL
        )
        let coordinator = view.makeCoordinator()
        let textView = NSTextView()
        textView.isRichText = false
        textView.delegate = coordinator
        coordinator.textView = textView
        textView.string = "antes "
        textView.setSelectedRange(NSRange(location: 6, length: 0))

        XCTAssertTrue(coordinator.insertImageFiles([image], at: nil))
        XCTAssertEqual(textView.string, "antes ![](grafico.png)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("grafico.png").path))
    }
}
