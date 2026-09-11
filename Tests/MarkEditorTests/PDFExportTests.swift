import PDFKit
import XCTest
@testable import MarkEditor

final class PDFExportTests: XCTestCase {
    /// Regression: a synchronous print run asked WebKit for its page rects
    /// before they existed and kept writing pages until it was killed.
    @MainActor
    func testExportsAShortDocumentAsAPaginatedPDF() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let markdown = "# Title\n\n" + (1...60).map { "Paragraph \($0) of the export test." }.joined(separator: "\n\n")

        let finished = expectation(description: "export finished")
        var succeeded = false
        DocumentExporter.exportPDF(markdown: markdown, title: "Test", baseDirectory: nil, to: url) { ok in
            succeeded = ok
            finished.fulfill()
        }
        wait(for: [finished], timeout: 20)

        XCTAssertTrue(succeeded)
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        XCTAssertLessThan(size, 5_000_000)
        let pages = PDFDocument(url: url)?.pageCount ?? 0
        XCTAssertTrue((2...6).contains(pages), "pages: \(pages)")
    }
}
