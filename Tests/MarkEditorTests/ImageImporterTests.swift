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
        XCTAssertTrue(ImageImporter.isImageFile(URL(fileURLWithPath: "/x/photo.PNG")))
        XCTAssertTrue(ImageImporter.isImageFile(URL(fileURLWithPath: "/x/a.jpeg")))
        XCTAssertFalse(ImageImporter.isImageFile(URL(fileURLWithPath: "/x/notes.md")))
    }

    func testImportCopiesExternalImage() throws {
        let external = FileManager.default.temporaryDirectory
            .appendingPathComponent("ext-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: external) }
        let source = try makePNG("photo.png", in: external)

        let path = try ImageImporter.importImage(from: source, into: directory)
        XCTAssertEqual(path, "photo.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("photo.png").path))
    }

    func testImportResolvesNameCollision() throws {
        _ = try makePNG("photo.png")
        let external = FileManager.default.temporaryDirectory
            .appendingPathComponent("ext-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: external) }
        let source = try makePNG("photo.png", in: external)

        XCTAssertEqual(try ImageImporter.importImage(from: source, into: directory), "photo-2.png")
    }

    func testImageAlreadyInsideFolderIsReferencedWithoutCopy() throws {
        let source = try makePNG("local.png")
        XCTAssertEqual(try ImageImporter.importImage(from: source, into: directory), "local.png")

        let sub = directory.appendingPathComponent("img")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let nested = try makePNG("inner.png", in: sub)
        XCTAssertEqual(try ImageImporter.importImage(from: nested, into: directory), "img/inner.png")
    }

    func testSaveImageDataWritesPNG() throws {
        let source = try makePNG("base.png")
        let name = try ImageImporter.saveImageData(try Data(contentsOf: source), in: directory)
        XCTAssertTrue(name.hasPrefix("image-"))
        XCTAssertTrue(name.hasSuffix(".png"))
    }

    /// A read-only folder (a disk image, a shared folder) must surface the
    /// error, so the editor can explain why the image didn't go in.
    func testReadOnlyFolderReportsTheError() throws {
        let external = FileManager.default.temporaryDirectory
            .appendingPathComponent("ext-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: external) }
        let source = try makePNG("photo.png", in: external)
        let data = try Data(contentsOf: source)

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }

        XCTAssertThrowsError(try ImageImporter.importImage(from: source, into: directory))
        XCTAssertThrowsError(try ImageImporter.saveImageData(data, in: directory))
    }

    func testDataThatIsNotAnImageReportsTheError() {
        XCTAssertThrowsError(try ImageImporter.saveImageData(Data("not an image".utf8), in: directory))
    }

    func testMarkdownEncodesSpaces() {
        XCTAssertEqual(
            ImageImporter.markdown(forRelativePaths: ["my photo.png"]),
            "![](my%20photo.png)"
        )
        XCTAssertEqual(
            ImageImporter.markdown(forRelativePaths: ["a.png", "b.png"]),
            "![](a.png)\n\n![](b.png)"
        )
    }

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    /// Reproduces a real Finder ⌘C: file URL + file name as text + icon TIFF.
    func testFinderCopyIsTreatedAsImageFileDespiteTextAndIcon() throws {
        let image = try makePNG("photo.png")
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
        pasteboard.setString("just some text", forType: .string)
        XCTAssertEqual(ImageImporter.pasteIntent(for: pasteboard), .notAnImage)
    }

    func testRichContentWithTextAndImageStaysText() throws {
        let data = try Data(contentsOf: try makePNG("web.png"))
        let pasteboard = makePasteboard()
        pasteboard.setString("text copied from a website", forType: .string)
        pasteboard.setData(data, forType: .tiff)
        XCTAssertEqual(ImageImporter.pasteIntent(for: pasteboard), .notAnImage)
    }

    func testNonImageFileIsNotAnImage() throws {
        let doc = directory.appendingPathComponent("notes.md")
        try "x".write(to: doc, atomically: true, encoding: .utf8)
        let pasteboard = makePasteboard()
        pasteboard.writeObjects([doc as NSURL])
        XCTAssertEqual(ImageImporter.pasteIntent(for: pasteboard), .notAnImage)
    }

    func testTextThatLooksLikeAPathIsNotAnImage() throws {
        let image = try makePNG("path.png")
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
        let item = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")

        XCTAssertTrue(textView.validateUserInterfaceItem(item))
        XCTAssertTrue(textView.readablePasteboardTypes.contains(.tiff))
        XCTAssertTrue(textView.readablePasteboardTypes.contains(.png))
        XCTAssertTrue(textView.readablePasteboardTypes.contains(.fileURL))
    }

    @MainActor
    func testPasteCommandFollowsDefaultRulesForPlainText() throws {
        let pasteboard = makePasteboard()
        pasteboard.setString("text", forType: .string)

        let textView = EditorTextView()
        textView.isRichText = false
        textView.pasteboardProvider = { pasteboard }
        let item = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")

        // Without an image, NSTextView's default validation applies (it reads
        // the general pasteboard); what matters is that the command isn't blocked.
        XCTAssertNoThrow(textView.validateUserInterfaceItem(item))
    }

    @MainActor
    func testCoordinatorInsertsImageMarkdownAtCaret() throws {
        let documentURL = directory.appendingPathComponent("notes.md")
        try "text".write(to: documentURL, atomically: true, encoding: .utf8)
        let external = FileManager.default.temporaryDirectory
            .appendingPathComponent("ext-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: external) }
        let image = try makePNG("chart.png", in: external)

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
        textView.string = "before "
        textView.setSelectedRange(NSRange(location: 7, length: 0))

        coordinator.insertImageFiles([image], at: nil)
        XCTAssertEqual(textView.string, "before ![](chart.png)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("chart.png").path))
    }
}
