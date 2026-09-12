import Foundation
import Testing
@testable import MarkEditor

struct WordCountTests {
    @Test func countsEnglishWordsAndIgnoresPunctuation() {
        #expect(WordCount.count(in: "Hello world, this is a test.") == 6)
        #expect(WordCount.count(in: "one two  three\n\nfour") == 4)
    }

    @Test func markdownMarkersAreNotWords() {
        #expect(WordCount.count(in: "# Title\n\n- item one\n- **bold** word") == 5)
    }

    @Test func emptyTextHasNoWords() {
        #expect(WordCount.count(in: "") == 0)
        #expect(WordCount.count(in: "  \n\n - ") == 0)
    }

    /// Japanese and Chinese have no spaces between words; splitting on
    /// whitespace would count a whole sentence as one word.
    @Test(arguments: ["今日は良い天気です。", "我们今天去公园散步。"])
    func countsWordsInLanguagesWithoutSpaces(sentence: String) {
        let count = WordCount.count(in: sentence)
        #expect(count > 2, "\(sentence)")
        #expect(count < sentence.count, "\(sentence)")
    }
}
