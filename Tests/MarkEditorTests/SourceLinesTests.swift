import XCTest
@testable import MarkEditor

final class SourceLinesTests: XCTestCase {
    func testCountIsNewlinesPlusOne() {
        XCTAssertEqual(SourceLines.count(in: ""), 1)
        XCTAssertEqual(SourceLines.count(in: "a"), 1)
        XCTAssertEqual(SourceLines.count(in: "a\nb"), 2)
        XCTAssertEqual(SourceLines.count(in: "a\nb\n"), 3)
    }

    func testStartsAreUTF16Offsets() {
        XCTAssertEqual(SourceLines.starts(in: "ab\nção\n\nx"), [0, 3, 7, 8])
    }

    func testLineContainingOffset() {
        let starts = [0, 3, 7, 8]
        XCTAssertEqual(SourceLines.line(containing: 0, starts: starts), 0)
        XCTAssertEqual(SourceLines.line(containing: 2, starts: starts), 0)
        XCTAssertEqual(SourceLines.line(containing: 3, starts: starts), 1)
        XCTAssertEqual(SourceLines.line(containing: 7, starts: starts), 2)
        XCTAssertEqual(SourceLines.line(containing: 50, starts: starts), 3)
    }
}
