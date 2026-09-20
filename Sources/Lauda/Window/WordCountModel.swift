import Foundation
import Observation

/// Keeps a document's counts current. Counting walks the whole text, which
/// is slow for long Japanese or Chinese documents, and characters are
/// counted by grapheme cluster, which walks it as well, so both run off the
/// main thread and, while typing, wait for a pause first. The counts when
/// the window opens run right away, and counts that a newer edit superseded
/// are never shown.
@MainActor
@Observable
final class WordCountModel {
    /// Words in the document; nil until the first count finishes.
    private(set) var wordCount: Int?
    /// Characters in the document, as the reader sees them (one per grapheme
    /// cluster, so an emoji or an accented letter counts once).
    private(set) var characterCount: Int?

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
        let counts = await Task.detached(priority: .userInitiated) {
            (words: count(text), characters: text.count)
        }.value
        if !Task.isCancelled {
            wordCount = counts.words
            characterCount = counts.characters
        }
    }
}
