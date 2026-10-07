import Testing
@testable import Lauda

/// Which pane a published position moves, with the panes scrolling together
/// or apart (the chain on the divider).
struct ScrollLinkTests {
    private func position(from source: ScrollSync.Source) -> ScrollSync {
        ScrollSync(line: 12, fraction: 0.3, source: source)
    }

    @Test func togetherEachPaneFollowsTheOther() {
        #expect(position(from: .editor).movesPreview(linked: true))
        #expect(position(from: .preview).movesEditor(linked: true))
    }

    @Test func apartNeitherPaneFollowsTheOther() {
        #expect(!position(from: .editor).movesPreview(linked: false))
        #expect(!position(from: .preview).movesEditor(linked: false))
    }

    @Test(arguments: [true, false])
    func aJumpMovesBothPanes(linked: Bool) {
        #expect(position(from: .navigation).movesEditor(linked: linked))
        #expect(position(from: .navigation).movesPreview(linked: linked))
    }

    @Test(arguments: [true, false])
    func aPaneNeverFollowsItself(linked: Bool) {
        #expect(!position(from: .editor).movesEditor(linked: linked))
        #expect(!position(from: .preview).movesPreview(linked: linked))
    }
}
