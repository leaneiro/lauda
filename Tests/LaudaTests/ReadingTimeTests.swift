import Foundation
import Testing
@testable import Lauda

struct ReadingTimeTests {
    @Test func emptyDocumentShowsNothing() {
        #expect(ReadingTime.label(forWordCount: 0) == nil)
    }

    @Test func shortTextShowsLessThanOneMinute() {
        #expect(ReadingTime.label(forWordCount: 50) == "less than 1 min read")
    }

    @Test(arguments: [(200, "~1 min read"), (350, "~2 min read"), (1000, "~5 min read")])
    func roundsToNearestMinute(words: Int, label: String) {
        #expect(ReadingTime.label(forWordCount: words) == label)
    }
}
