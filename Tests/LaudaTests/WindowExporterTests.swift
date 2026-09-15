import Foundation
import Testing
@testable import Lauda

struct WindowExporterTests {
    private func exporter(for fileURL: URL?) -> WindowExporter {
        WindowExporter(markdown: { "# Notes" }, fileURL: fileURL, window: WindowReference())
    }

    @Test func theSuggestedNameIsTheDocumentsWithoutItsExtension() {
        #expect(exporter(for: URL(fileURLWithPath: "/Users/someone/Docs/notes.md")).title == "notes")
        #expect(exporter(for: URL(fileURLWithPath: "/tmp/release.notes.md")).title == "release.notes")
    }

    @Test func anUnsavedDocumentExportsAsUntitled() {
        #expect(exporter(for: nil).title == "Untitled")
        #expect(exporter(for: nil).baseDirectory == nil)
    }

    /// Relative image paths resolve next to the document, as in the preview.
    @Test func imagesAreFoundInTheDocumentsFolder() {
        let folder = exporter(for: URL(fileURLWithPath: "/Users/someone/Docs/notes.md")).baseDirectory
        #expect(folder?.path == "/Users/someone/Docs")
    }
}
