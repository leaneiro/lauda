import Foundation
import Testing
@testable import Lauda

struct OpenPairsTests {
    @Test func aPairMovesWithTextTypedBeforeAndInsideIt() {
        var pairs = OpenPairs()
        pairs.opened(at: 4)
        pairs.textWillChange(in: NSRange(location: 5, length: 0), replacementLength: 3)
        #expect(pairs.innermost == .init(opener: 4, closer: 8))
        pairs.textWillChange(in: NSRange(location: 0, length: 0), replacementLength: 2)
        #expect(pairs.innermost == .init(opener: 6, closer: 10))
    }

    @Test func textAfterAPairLeavesItWhereItIs() {
        var pairs = OpenPairs()
        pairs.opened(at: 4)
        pairs.textWillChange(in: NSRange(location: 6, length: 0), replacementLength: 3)
        #expect(pairs.innermost == .init(opener: 4, closer: 5))
    }

    @Test(arguments: [NSRange(location: 4, length: 1), NSRange(location: 5, length: 1), NSRange(location: 2, length: 6)])
    func anEditTakingEitherCharacterEndsThePair(range: NSRange) {
        var pairs = OpenPairs()
        pairs.opened(at: 4)
        pairs.textWillChange(in: range, replacementLength: 0)
        #expect(pairs.innermost == nil)
    }

    @Test func aCaretOutsideThePairEndsIt() {
        var pairs = OpenPairs()
        pairs.opened(at: 4)
        pairs.selectionDidChange(to: NSRange(location: 5, length: 0))
        #expect(pairs.innermost != nil)
        pairs.selectionDidChange(to: NSRange(location: 4, length: 0))
        #expect(pairs.innermost == nil)

        pairs.opened(at: 4)
        pairs.selectionDidChange(to: NSRange(location: 6, length: 0))
        #expect(pairs.innermost == nil)
    }

    @Test func leavingAnInnerPairKeepsTheOuterOne() {
        var pairs = OpenPairs()
        pairs.opened(at: 0)
        pairs.textWillChange(in: NSRange(location: 1, length: 0), replacementLength: 2)
        pairs.opened(at: 1)
        #expect(pairs.innermost == .init(opener: 1, closer: 2))
        pairs.selectionDidChange(to: NSRange(location: 3, length: 0))
        #expect(pairs.innermost == .init(opener: 0, closer: 3))
    }
}
