import XCTest
@testable import MarkEditor

final class ReadingTimeTests: XCTestCase {
    func testEmptyDocumentShowsNothing() {
        XCTAssertNil(ReadingTime.label(forWordCount: 0))
    }

    func testShortTextShowsLessThanOneMinute() {
        XCTAssertEqual(ReadingTime.label(forWordCount: 50), "menos de 1 min de leitura")
    }

    func testRoundsToNearestMinute() {
        XCTAssertEqual(ReadingTime.label(forWordCount: 200), "~1 min de leitura")
        XCTAssertEqual(ReadingTime.label(forWordCount: 350), "~2 min de leitura")
        XCTAssertEqual(ReadingTime.label(forWordCount: 1000), "~5 min de leitura")
    }
}
