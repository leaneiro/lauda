import Foundation
import Testing
@testable import MarkEditor

struct DocumentIdentityTests {
    /// Two windows can hold the same text; a save must mark only its own.
    @Test func documentsWithTheSameTextAreStillDifferentDocuments() {
        #expect(MarkdownDocument(text: "same").id != MarkdownDocument(text: "same").id)
    }

    @Test func copiesKeepTheIdentity() {
        let original = MarkdownDocument(text: "a")
        var copy = original
        copy.text = "b"
        #expect(copy.id == original.id)
    }
}
