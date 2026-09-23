/// Where the keyboard goes when a tab is chosen: into the document's panes
/// (a click, the menu, VoiceOver), or nowhere, left where it is (the tabs
/// walked with the arrows, which keep the keyboard on them). The Electron
/// edition's Workspace takes the same choice.
enum KeyboardAfterChoice {
    case follows, stays
}

/// Walking a row of choices from the keyboard, as the tab strip is walked.
enum KeyboardRow {
    /// The keys that move along a row.
    enum Key {
        case previous, next, first, last
    }

    /// Where a key moves along a row of `count` choices: the arrows to the
    /// neighbour, round from one end to the other, Home and End to the ends,
    /// as tab lists are walked. `current` is the choice that holds, nil for
    /// none yet; nil comes back for a row with nothing in it. The Electron
    /// edition walks its rows by the same rule (src/shared/keyboard-row.ts),
    /// with the same tests.
    static func target(_ key: Key, current: Int?, count: Int) -> Int? {
        guard count > 0 else { return nil }
        switch key {
        case .previous:
            guard let current, current > 0 else { return count - 1 }
            return current - 1
        case .next:
            guard let current, current < count - 1 else { return 0 }
            return current + 1
        case .first:
            return 0
        case .last:
            return count - 1
        }
    }
}
