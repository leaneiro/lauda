import Foundation
import Testing
@testable import Lauda

struct EditorTextViewURLTests {
    @Test(arguments: ["https://example.com/page", "http://example.com"])
    func acceptsHTTPAndHTTPS(text: String) {
        #expect(EditorTextView.isLikelyURL(text))
    }

    @Test(arguments: ["just text", "file:///etc/passwd", "text with https://example.com inside", ""])
    func rejectsPlainTextAndOtherSchemes(text: String) {
        #expect(!EditorTextView.isLikelyURL(text))
    }
}
