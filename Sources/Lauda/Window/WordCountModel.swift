import Foundation
import Observation

/// Keeps a document's word count current. Counting walks the whole text,
/// which is slow for long Japanese or Chinese documents, so it runs off the
/// main thread and, while typing, waits for a pause first. The count when the
/// window opens runs right away, and a count that a newer edit superseded is
/// never shown.
@MainActor
@Observable
final class WordCountModel {
    /// Words in the document; nil until the first count finishes.
    private(set) var wordCount: Int?

    private let pause: Duration
    private let sleep: @Sendable (Duration) async -> Void
    private let count: @Sendable (String) -> Int

    init(
        pause: Duration = .milliseconds(300),
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        count: @escaping @Sendable (String) -> Int = { WordCount.count(in: $0) }
    ) {
        self.pause = pause
        self.sleep = sleep
        self.count = count
    }

    /// Counts `text`. Call it from `.task(id: text)`, so SwiftUI cancels the
    /// previous call as soon as the text changes again.
    func update(for text: String) async {
        if wordCount != nil {
            await sleep(pause)
            if Task.isCancelled { return }
        }
        let count = self.count
        let result = await Task.detached(priority: .userInitiated) { count(text) }.value
        if !Task.isCancelled {
            wordCount = result
        }
    }
}
