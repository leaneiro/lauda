import Foundation
import Testing
@testable import Lauda

struct PreviewSecurityTests {
    // MARK: - Links

    @Test(arguments: [
        "https://example.com", "http://example.com", "mailto:someone@example.com",
        "notes.md", "./img/a.png", "#section", "folder/page?x=a:b",
    ])
    func keepsExternalRelativeAndFragmentLinks(destination: String) {
        let html = HTMLRenderer.render("[x](\(destination))")
        #expect(html.contains("<a href="), "\(destination): \(html)")
    }

    @Test(arguments: ["javascript:alert(1)", "JavaScript:alert(1)", "data:text/html,hi", "file:///etc/passwd"])
    func dropsScriptAndDataLinksButKeepsTheirText(destination: String) {
        let html = HTMLRenderer.render("[click me](\(destination))")
        #expect(!html.contains("<a"), "\(destination): \(html)")
        #expect(html.contains("click me"), "\(html)")
    }

    @Test func schemeCheckIgnoresWhitespaceAndControlCharacters() {
        #expect(!HTMLRenderer.isAllowedLinkDestination(" java\tscript:alert(1)"))
        #expect(!HTMLRenderer.isAllowedLinkDestination("java\nscript:alert(1)"))
        #expect(HTMLRenderer.isAllowedLinkDestination("page.md#part:two"))
    }

    /// A combining mark right after the colon joins it into one Character
    /// with it; the scheme is found all the same.
    @Test func schemeCheckSeesAColonWithACombiningMarkAfterIt() {
        #expect(!HTMLRenderer.isAllowedLinkDestination("javascript:\u{301}alert(1)"))
        let html = HTMLRenderer.render("[click me](javascript:\u{301}alert(1))")
        #expect(!html.contains("<a"), "\(html)")
        #expect(html.contains("click me"), "\(html)")
    }

    // MARK: - Escaping

    /// A combining mark after one of HTML's special characters makes a single
    /// Character with it; the special character is escaped all the same.
    @Test(arguments: [("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"), ("\"", "&quot;")])
    func escapesMarkupCharactersFollowedByACombiningMark(pair: (String, String)) {
        #expect(HTMLRenderer.escape("a\(pair.0)\u{301}b") == "a\(pair.1)\u{301}b")
    }

    @Test func anImagesAltTextStaysInsideItsAttribute() {
        let html = HTMLRenderer.render("![photo &quot;\u{301} beach](a.png)")
        #expect(html.contains("alt=\"photo &quot;\u{301} beach\""), "\(html)")
    }

    // MARK: - Page policies

    @Test func previewPageBlocksDocumentScripts() {
        let policy = PreviewTemplate.previewContentSecurityPolicy
        #expect(PreviewTemplate.html.contains("<meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\">"))
        #expect(policy.hasPrefix("default-src 'none'"), "\(policy)")
        #expect(!policy.contains("script-src"), "\(policy)")
        #expect(!policy.contains("connect-src"), "\(policy)")
        // The app's script is injected into its own content world, not the page.
        #expect(!PreviewTemplate.html.contains("<script"))
        #expect(PreviewTemplate.script.contains("function setContent("))
    }

    /// Fonts only come embedded (the wordmark face), never from the network.
    @Test func previewPageLoadsFontsOnlyFromDataURIs() {
        let policy = PreviewTemplate.previewContentSecurityPolicy
        #expect(policy.contains("font-src data:; "), "\(policy)")
    }

    @Test func previewPageStillShowsImagesFromEverywhere() {
        let policy = PreviewTemplate.previewContentSecurityPolicy
        #expect(policy.contains("img-src \(DocumentSchemeHandler.scheme): data: https: http:"), "\(policy)")
    }

    @Test func exportedDocumentBlocksScripts() {
        let html = PreviewTemplate.standalone(
            title: "T", bodyHTML: "<p>x</p>", fontFamily: "x", fontSize: 16, lineHeight: 1.6
        )
        #expect(html.contains("content=\"\(PreviewTemplate.exportContentSecurityPolicy)\""))
        #expect(PreviewTemplate.exportContentSecurityPolicy.hasPrefix("script-src 'none'"))
    }

    // MARK: - Local images

    private func resolve(_ path: String, in folder: URL) -> URL? {
        DocumentSchemeHandler.resolveTarget(
            for: URL(string: "\(DocumentSchemeHandler.scheme):///\(path)")!,
            baseDirectory: folder
        )
    }

    @Test func symlinkPointingOutsideTheFolderIsNotServed() throws {
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

        #expect(resolve("inside.png", in: folder) != nil)
        #expect(resolve("link.png", in: folder) == nil)
    }

    @Test func iconFilesCountAsImagesInEditorAndPreview() {
        #expect(ImageImporter.isImageFile(URL(fileURLWithPath: "/x/favicon.ico")))
        #expect(resolve("favicon.ico", in: URL(fileURLWithPath: "/Users/someone/doc")) != nil)
    }
}
