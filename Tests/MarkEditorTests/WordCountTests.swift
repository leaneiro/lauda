import XCTest
@testable import MarkEditor

final class WordCountTests: XCTestCase {
    func testCountsEnglishWordsAndIgnoresPunctuation() {
        XCTAssertEqual(WordCount.count(in: "Hello world, this is a test."), 6)
        XCTAssertEqual(WordCount.count(in: "one two  three\n\nfour"), 4)
    }

    func testMarkdownMarkersAreNotWords() {
        XCTAssertEqual(WordCount.count(in: "# Title\n\n- item one\n- **bold** word"), 5)
    }

    func testEmptyTextHasNoWords() {
        XCTAssertEqual(WordCount.count(in: ""), 0)
        XCTAssertEqual(WordCount.count(in: "  \n\n - "), 0)
    }

    /// Japanese and Chinese have no spaces between words; splitting on
    /// whitespace would count a whole sentence as one word.
    func testCountsWordsInLanguagesWithoutSpaces() {
        for sentence in ["今日は良い天気です。", "我们今天去公园散步。"] {
            let count = WordCount.count(in: sentence)
            XCTAssertGreaterThan(count, 2, sentence)
            XCTAssertLessThan(count, sentence.count, sentence)
        }
    }
}
