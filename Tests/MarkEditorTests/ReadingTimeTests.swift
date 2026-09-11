import XCTest
@testable import MarkEditor

final class ReadingTimeTests: XCTestCase {
    func testEmptyDocumentShowsNothing() {
        XCTAssertNil(ReadingTime.label(forWordCount: 0))
    }

    func testShortTextShowsLessThanOneMinute() {
        XCTAssertEqual(ReadingTime.label(forWordCount: 50), "less than 1 min read")
    }

    func testRoundsToNearestMinute() {
        XCTAssertEqual(ReadingTime.label(forWordCount: 200), "~1 min read")
        XCTAssertEqual(ReadingTime.label(forWordCount: 350), "~2 min read")
        XCTAssertEqual(ReadingTime.label(forWordCount: 1000), "~5 min read")
    }
}
