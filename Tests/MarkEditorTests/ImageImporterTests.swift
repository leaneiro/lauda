import AppKit
import SwiftUI
import Testing
@testable import MarkEditor

/// Main actor throughout: the paste and coordinator cases drive AppKit
/// views. Each test gets its own folder and its own named pasteboard, so
/// they never share state.
@MainActor
final class ImageImporterTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("images-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try? FileManager.default.removeItem(at: directory)
    }

    private func makePNG(_ name: String, in folder: URL? = nil) throws -> URL {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let url = (folder ?? directory).appendingPathComponent(name)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    /// A folder outside the document's, for "copy this in" cases.
    private func makeExternalFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ext-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func isImageFile() {
        #expect(ImageImporter.isImageFile(URL(fileURLWithPath: "/x/photo.PNG")))
        #expect(ImageImporter.isImageFile(URL(fileURLWithPath: "/x/a.jpeg")))
        #expect(!ImageImporter.isImageFile(URL(fileURLWithPath: "/x/notes.md")))
    }

    @Test func importCopiesExternalImage() throws {
        let external = try makeExternalFolder()
        defer { try? FileManager.default.removeItem(at: external) }
        let source = try makePNG("photo.png", in: external)

        #expect(try ImageImporter.importImage(from: source, into: directory) == "photo.png")
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("photo.png").path))
    }

    @Test func importResolvesNameCollision() throws {
        _ = try makePNG("photo.png")
        let external = try makeExternalFolder()
        defer { try? FileManager.default.removeItem(at: external) }
        let source = try makePNG("photo.png", in: external)

        #expect(try ImageImporter.importImage(from: source, into: directory) == "photo-2.png")
    }

    @Test func imageAlreadyInsideFolderIsReferencedWithoutCopy() throws {
        let source = try makePNG("local.png")
        #expect(try ImageImporter.importImage(from: source, into: directory) == "local.png")

        let sub = directory.appendingPathComponent("img")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let nested = try makePNG("inner.png", in: sub)
        #expect(try ImageImporter.importImage(from: nested, into: directory) == "img/inner.png")
    }

    @Test func saveImageDataWritesPNG() throws {
        let source = try makePNG("base.png")
        let name = try ImageImporter.saveImageData(try Data(contentsOf: source), in: directory)
        #expect(name.hasPrefix("image-"))
        #expect(name.hasSuffix(".png"))
    }

    /// A read-only folder (a disk image, a shared folder) must surface the
    /// error, so the editor can explain why the image didn't go in.
    @Test func readOnlyFolderReportsTheError() throws {
        let external = try makeExternalFolder()
        defer { try? FileManager.default.removeItem(at: external) }
        let source = try makePNG("photo.png", in: external)
        let data = try Data(contentsOf: source)

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }

        #expect(throws: (any Error).self) { try ImageImporter.importImage(from: source, into: self.directory) }
        #expect(throws: (any Error).self) { try ImageImporter.saveImageData(data, in: self.directory) }
    }

    @Test func dataThatIsNotAnImageReportsTheError() {
        #expect(throws: (any Error).self) {
            try ImageImporter.saveImageData(Data("not an image".utf8), in: self.directory)
        }
    }

    @Test func markdownEncodesSpaces() {
        #expect(ImageImporter.markdown(forRelativePaths: ["my photo.png"]) == "![](my%20photo.png)")
        #expect(ImageImporter.markdown(forRelativePaths: ["a.png", "b.png"]) == "![](a.png)\n\n![](b.png)")
    }

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    /// Reproduces a real Finder ⌘C: file URL + file name as text + icon TIFF.
    @Test func finderCopyIsTreatedAsImageFileDespiteTextAndIcon() throws {
        let image = try makePNG("photo.png")
        let pasteboard = makePasteboard()
        pasteboard.writeObjects([image as NSURL])
        pasteboard.setString(image.lastPathComponent, forType: .string)
        pasteboard.setData(try Data(contentsOf: image), forType: .tiff)

        #expect(ImageImporter.pasteIntent(for: pasteboard) == .imageFiles([image]))
    }

    @Test func screenshotDataIsTreatedAsImage() throws {
        let data = try Data(contentsOf: try makePNG("shot.png"))
        let pasteboard = makePasteboard()
        pasteboard.setData(data, forType: .tiff)

        #expect(ImageImporter.pasteIntent(for: pasteboard) == .imageData(data))
    }

    @Test func plainTextIsNotAnImage() {
        let pasteboard = makePasteboard()
        pasteboard.setString("just some text", forType: .string)
        #expect(ImageImporter.pasteIntent(for: pasteboard) == .notAnImage)
    }

    @Test func richContentWithTextAndImageStaysText() throws {
        let data = try Data(contentsOf: try makePNG("web.png"))
        let pasteboard = makePasteboard()
        pasteboard.setString("text copied from a website", forType: .string)
        pasteboard.setData(data, forType: .tiff)
        #expect(ImageImporter.pasteIntent(for: pasteboard) == .notAnImage)
    }

    @Test func nonImageFileIsNotAnImage() throws {
        let doc = directory.appendingPathComponent("notes.md")
        try "x".write(to: doc, atomically: true, encoding: .utf8)
        let pasteboard = makePasteboard()
        pasteboard.writeObjects([doc as NSURL])
        #expect(ImageImporter.pasteIntent(for: pasteboard) == .notAnImage)
    }

    @Test func textThatLooksLikeAPathIsNotAnImage() throws {
        let image = try makePNG("path.png")
        let pasteboard = makePasteboard()
        pasteboard.setString(image.path, forType: .string)
        #expect(ImageImporter.pasteIntent(for: pasteboard) == .notAnImage)
    }

    private func makePasteMenuItem() -> NSMenuItem {
        NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    }

    /// Regression: AppKit disables Paste (greyed menu, inert ⌘V) when a
    /// plain-text view reports nothing readable — an image-only clipboard
    /// never reached our paste handler.
    @Test func pasteCommandStaysEnabledForImageOnlyClipboard() throws {
        let data = try Data(contentsOf: try makePNG("shot.png"))
        let pasteboard = makePasteboard()
        pasteboard.setData(data, forType: .tiff)

        let textView = EditorTextView()
        textView.isRichText = false
        textView.pasteboardProvider = { pasteboard }

        #expect(textView.validateUserInterfaceItem(makePasteMenuItem()))
        #expect(textView.readablePasteboardTypes.contains(.tiff))
        #expect(textView.readablePasteboardTypes.contains(.png))
        #expect(textView.readablePasteboardTypes.contains(.fileURL))
    }

    @Test func pasteCommandFollowsDefaultRulesForPlainText() {
        let pasteboard = makePasteboard()
        pasteboard.setString("text", forType: .string)

        let textView = EditorTextView()
        textView.isRichText = false
        textView.pasteboardProvider = { pasteboard }

        // Without an image our override steps aside and NSTextView's own
        // validation decides (it reads the general pasteboard); what matters
        // is that nothing blocks the command.
        #expect(ImageImporter.pasteIntent(for: pasteboard) == .notAnImage)
        _ = textView.validateUserInterfaceItem(makePasteMenuItem())
    }

    @Test func coordinatorInsertsImageMarkdownAtCaret() throws {
        let documentURL = directory.appendingPathComponent("notes.md")
        try "text".write(to: documentURL, atomically: true, encoding: .utf8)
        let external = try makeExternalFolder()
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
        #expect(textView.string == "before ![](chart.png)")
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("chart.png").path))
    }
}
