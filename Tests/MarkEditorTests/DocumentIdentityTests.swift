import XCTest
@testable import MarkEditor

final class DocumentIdentityTests: XCTestCase {
    /// Two windows can hold the same text; a save must mark only its own.
    func testDocumentsWithTheSameTextAreStillDifferentDocuments() {
        XCTAssertNotEqual(MarkdownDocument(text: "same").id, MarkdownDocument(text: "same").id)
    }

    func testCopiesKeepTheIdentity() {
        let original = MarkdownDocument(text: "a")
        var copy = original
        copy.text = "b"
        XCTAssertEqual(copy.id, original.id)
    }
}
