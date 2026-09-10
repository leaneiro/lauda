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

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("teste-\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    /// Reproduces a real Finder ⌘C: file URL + file name as text + icon TIFF.
    func testFinderCopyIsTreatedAsImageFileDespiteTextAndIcon() throws {
        let image = try makePNG("foto.png")
        let pasteboard = makePasteboard()
        pasteboard.writeObjects([image as NSURL])
        pasteboard.setString(image.lastPathComponent, forType: .string)
        pasteboard.setData(try Data(contentsOf: image), forType: .tiff)

        XCTAssertEqual(ImageImporter.pasteIntent(for: pasteboard), .imageFiles([image]))
    }

    func testScreenshotDataIsTreatedAsImage() throws {
        let data = try Data(contentsOf: try makePNG("shot.png"))
        let pasteboard = makePasteboard()
        pasteboard.setData(data, forType: .tiff)

        XCTAssertEqual(ImageImporter.pasteIntent(for: pasteboard), .imageData(data))
    }

    func testPlainTextIsNotAnImage() {
        let pasteboard = makePasteboard()
        pasteboard.setString("só um texto", forType: .string)
        XCTAssertEqual(ImageImporter.pasteIntent(for: pasteboard), .notAnImage)
    }

    func testRichContentWithTextAndImageStaysText() throws {
        let data = try Data(contentsOf: try makePNG("web.png"))
        let pasteboard = makePasteboard()
        pasteboard.setString("trecho copiado de um site", forType: .string)
        pasteboard.setData(data, forType: .tiff)
        XCTAssertEqual(ImageImporter.pasteIntent(for: pasteboard), .notAnImage)
    }

    func testNonImageFileIsNotAnImage() throws {
        let doc = directory.appendingPathComponent("notas.md")
        try "x".write(to: doc, atomically: true, encoding: .utf8)
        let pasteboard = makePasteboard()
        pasteboard.writeObjects([doc as NSURL])
        XCTAssertEqual(ImageImporter.pasteIntent(for: pasteboard), .notAnImage)
    }

    func testTextThatLooksLikeAPathIsNotAnImage() throws {
        let image = try makePNG("caminho.png")
        let pasteboard = makePasteboard()
        pasteboard.setString(image.path, forType: .string)
        XCTAssertEqual(ImageImporter.pasteIntent(for: pasteboard), .notAnImage)
    }

    /// Regression: AppKit disables Paste (greyed menu, inert ⌘V) when a
    /// plain-text view reports nothing readable — an image-only clipboard
    /// never reached our paste handler.
    @MainActor
    func testPasteCommandStaysEnabledForImageOnlyClipboard() throws {
        let data = try Data(contentsOf: try makePNG("shot.png"))
        let pasteboard = makePasteboard()
        pasteboard.setData(data, forType: .tiff)

        let textView = EditorTextView()
        textView.isRichText = false
        textView.pasteboardProvider = { pasteboard }
        let item = NSMenuItem(title: "Colar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")

        XCTAssertTrue(textView.validateUserInterfaceItem(item))
        XCTAssertTrue(textView.readablePasteboardTypes.contains(.tiff))
        XCTAssertTrue(textView.readablePasteboardTypes.contains(.png))
        XCTAssertTrue(textView.readablePasteboardTypes.contains(.fileURL))
    }

    @MainActor
    func testPasteCommandFollowsDefaultRulesForPlainText() throws {
        let pasteboard = makePasteboard()
        pasteboard.setString("texto", forType: .string)

        let textView = EditorTextView()
        textView.isRichText = false
        textView.pasteboardProvider = { pasteboard }
        let item = NSMenuItem(title: "Colar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")

        // Sem imagem, cai na validação padrão do NSTextView (que aceita texto
        // do pasteboard geral) — o importante é não travar o comando.
        XCTAssertNoThrow(textView.validateUserInterfaceItem(item))
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
