import Foundation
import Testing
@testable import Lauda

struct SourceLinesTests {
    @Test(arguments: [("", 1), ("a", 1), ("a\nb", 2), ("a\nb\n", 3)])
    func countIsNewlinesPlusOne(text: String, expected: Int) {
        #expect(SourceLines.count(in: text) == expected)
    }

    @Test func startsAreUTF16Offsets() {
        #expect(SourceLines.starts(in: "ab\ncafé\n\nx") == [0, 3, 8, 9])
    }

    @Test(arguments: [(0, 0), (2, 0), (3, 1), (7, 2), (50, 3)])
    func lineContainingOffset(offset: Int, line: Int) {
        #expect(SourceLines.line(containing: offset, starts: [0, 3, 7, 8]) == line)
    }
}
