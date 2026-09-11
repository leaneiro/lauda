import Foundation

/// Word count for the status bar and the reading time. Uses the system's word
/// boundaries, so languages written without spaces between words (Japanese,
/// Chinese) are counted by word too, and Markdown markers (#, -, **) don't
/// count as words.
enum WordCount {
    static func count(in text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }
}
