import XCTest
@testable import MarkEditor

final class PreviewSecurityTests: XCTestCase {
    // MARK: - Links

    func testKeepsExternalRelativeAndFragmentLinks() {
        let destinations = [
            "https://example.com", "http://example.com", "mailto:someone@example.com",
            "notes.md", "./img/a.png", "#section", "folder/page?x=a:b",
        ]
        for destination in destinations {
            let html = HTMLRenderer.render("[x](\(destination))")
            XCTAssertTrue(html.contains("<a href="), "\(destination): \(html)")
        }
    }

    func testDropsScriptAndDataLinksButKeepsTheirText() {
        let destinations = ["javascript:alert(1)", "JavaScript:alert(1)", "data:text/html,hi", "file:///etc/passwd"]
        for destination in destinations {
            let html = HTMLRenderer.render("[click me](\(destination))")
            XCTAssertFalse(html.contains("<a"), "\(destination): \(html)")
            XCTAssertTrue(html.contains("click me"), html)
        }
    }

    func testSchemeCheckIgnoresWhitespaceAndControlCharacters() {
        XCTAssertFalse(HTMLRenderer.isAllowedLinkDestination(" java\tscript:alert(1)"))
        XCTAssertFalse(HTMLRenderer.isAllowedLinkDestination("java\nscript:alert(1)"))
        XCTAssertTrue(HTMLRenderer.isAllowedLinkDestination("page.md#part:two"))
    }

    // MARK: - Page policies

    func testPreviewPageBlocksDocumentScripts() {
        let policy = PreviewTemplate.previewContentSecurityPolicy
        XCTAssertTrue(PreviewTemplate.html.contains("<meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\">"))
        XCTAssertTrue(policy.hasPrefix("default-src 'none'"), policy)
        XCTAssertFalse(policy.contains("script-src"), policy)
        XCTAssertFalse(policy.contains("connect-src"), policy)
        // The app's script is injected into its own content world, not the page.
        XCTAssertFalse(PreviewTemplate.html.contains("<script"))
        XCTAssertTrue(PreviewTemplate.script.contains("function setContent("))
    }

    func testPreviewPageStillShowsImagesFromEverywhere() {
        let policy = PreviewTemplate.previewContentSecurityPolicy
        XCTAssertTrue(policy.contains("img-src \(DocumentSchemeHandler.scheme): data: https: http:"), policy)
    }

    func testExportedDocumentBlocksScripts() {
        let html = PreviewTemplate.standalone(
            title: "T", bodyHTML: "<p>x</p>", fontFamily: "x", fontSize: 16, lineHeight: 1.6
        )
        XCTAssertTrue(html.contains("content=\"\(PreviewTemplate.exportContentSecurityPolicy)\""))
        XCTAssertTrue(PreviewTemplate.exportContentSecurityPolicy.hasPrefix("script-src 'none'"))
    }

    // MARK: - Local images

    private func resolve(_ path: String, in folder: URL) -> URL? {
        DocumentSchemeHandler.resolveTarget(
            for: URL(string: "\(DocumentSchemeHandler.scheme):///\(path)")!,
            baseDirectory: folder
        )
    }

    func testSymlinkPointingOutsideTheFolderIsNotServed() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("scheme-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("doc")
        let outside = root.appendingPathComponent("outside")
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        try Data([0]).write(to: outside.appendingPathComponent("secret.png"))
        try Data([0]).write(to: folder.appendingPathComponent("inside.png"))
        try fileManager.createSymbolicLink(
            at: folder.appendingPathComponent("link.png"),
            withDestinationURL: outside.appendingPathComponent("secret.png")
        )

        XCTAssertNotNil(resolve("inside.png", in: folder))
        XCTAssertNil(resolve("link.png", in: folder))
    }

    func testIconFilesCountAsImagesInEditorAndPreview() {
        XCTAssertTrue(ImageImporter.isImageFile(URL(fileURLWithPath: "/x/favicon.ico")))
        XCTAssertNotNil(resolve("favicon.ico", in: URL(fileURLWithPath: "/Users/someone/doc")))
    }
}
