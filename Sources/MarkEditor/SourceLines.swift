import Foundation

/// Source-line arithmetic shared by the editor and the renderer. Lines split
/// on "\n" only, matching the line numbers the Markdown parser reports.
enum SourceLines {
    /// Number of lines: newlines + 1 (a trailing newline opens an empty line).
    static func count(in text: String) -> Int {
        text.utf8.reduce(1) { $1 == 0x0A ? $0 + 1 : $0 }
    }

    /// UTF-16 offsets where each line starts.
    static func starts(in text: String) -> [Int] {
        var starts = [0]
        var offset = 0
        for unit in text.utf16 {
            offset += 1
            if unit == 0x0A { starts.append(offset) }
        }
        return starts
    }

    /// Index of the line containing `offset`, given `starts(in:)`.
    static func line(containing offset: Int, starts: [Int]) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }
}
