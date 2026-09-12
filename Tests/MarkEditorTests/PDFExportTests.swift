import Foundation
import PDFKit
import Testing
@testable import MarkEditor

@MainActor
@Suite(.serialized)
struct PDFExportTests {
    /// Regression: a synchronous print run asked WebKit for its page rects
    /// before they existed and kept writing pages until it was killed. The
    /// time limit is the guard against that hanging the suite again.
    @Test(.timeLimit(.minutes(1)))
    func exportsAShortDocumentAsAPaginatedPDF() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let markdown = "# Title\n\n" + (1...60).map { "Paragraph \($0) of the export test." }.joined(separator: "\n\n")

        let succeeded = await withCheckedContinuation { continuation in
            DocumentExporter.exportPDF(markdown: markdown, title: "Test", baseDirectory: nil, to: url) { ok in
                continuation.resume(returning: ok)
            }
        }

        #expect(succeeded)
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        #expect(size < 5_000_000)
        let pages = PDFDocument(url: url)?.pageCount ?? 0
        #expect((2...6).contains(pages), "pages: \(pages)")
    }
}
