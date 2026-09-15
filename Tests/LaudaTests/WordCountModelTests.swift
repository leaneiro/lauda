import Foundation
import Testing
@testable import Lauda

/// Stands in for the word count's pause, so a test decides when each wait ends.
@MainActor
private final class PauseGate {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var requested: [Duration] = []

    var isHolding: Bool { !waiting.isEmpty }

    func wait(_ duration: Duration) async {
        requested.append(duration)
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        let continuations = waiting
        waiting.removeAll()
        continuations.forEach { $0.resume() }
    }

    /// Yields until the model is inside its pause.
    func untilHolding() async {
        while !isHolding {
            await Task.yield()
        }
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WordCountModelTests {
    @Test func theFirstCountRunsWithoutWaiting() async {
        let gate = PauseGate()
        let model = WordCountModel(sleep: { await gate.wait($0) })
        await model.update(for: "one two three")
        #expect(model.wordCount == 3)
        #expect(gate.requested.isEmpty)
    }

    @Test func laterCountsWaitForAPauseInTyping() async {
        let gate = PauseGate()
        let model = WordCountModel(pause: .milliseconds(300), sleep: { await gate.wait($0) })
        await model.update(for: "one")

        let typing = Task { await model.update(for: "one two") }
        await gate.untilHolding()
        #expect(gate.requested == [.milliseconds(300)])
        #expect(model.wordCount == 1, "the old count stays up while waiting")

        gate.release()
        await typing.value
        #expect(model.wordCount == 2)
    }

    /// SwiftUI cancels the running update when the text changes again; its count must not win.
    @Test func aCountSupersededByANewerEditIsNeverShown() async {
        let gate = PauseGate()
        let model = WordCountModel(sleep: { await gate.wait($0) })
        await model.update(for: "one")

        let stale = Task { await model.update(for: "one two three four") }
        await gate.untilHolding()
        stale.cancel()
        gate.release()
        await stale.value
        #expect(model.wordCount == 1)

        let fresh = Task { await model.update(for: "one two") }
        await gate.untilHolding()
        gate.release()
        await fresh.value
        #expect(model.wordCount == 2)
    }

    @Test func theDefaultCounterUnderstandsLanguagesWithoutSpaces() async {
        let model = WordCountModel()
        await model.update(for: "今日は良い天気です。")
        #expect((model.wordCount ?? 0) > 2)
    }
}
