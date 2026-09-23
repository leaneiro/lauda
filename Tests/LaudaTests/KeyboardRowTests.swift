import Testing
@testable import Lauda

/// The cases of the Electron edition's keyboardRow tests, one for one.
struct KeyboardRowTests {
    @Test func movesToTheNeighbourWithTheArrows() {
        #expect(KeyboardRow.target(.next, current: 0, count: 3) == 1)
        #expect(KeyboardRow.target(.previous, current: 2, count: 3) == 1)
    }

    @Test func goesRoundFromOneEndToTheOther() {
        #expect(KeyboardRow.target(.next, current: 2, count: 3) == 0)
        #expect(KeyboardRow.target(.previous, current: 0, count: 3) == 2)
    }

    @Test func goesToTheEndsWithHomeAndEnd() {
        #expect(KeyboardRow.target(.first, current: 1, count: 3) == 0)
        #expect(KeyboardRow.target(.last, current: 1, count: 3) == 2)
    }

    @Test func startsAtAnEndWhenNothingHoldsYet() {
        #expect(KeyboardRow.target(.next, current: nil, count: 3) == 0)
        #expect(KeyboardRow.target(.previous, current: nil, count: 3) == 2)
    }

    @Test func movesNowhereInAnEmptyRow() {
        #expect(KeyboardRow.target(.next, current: 0, count: 0) == nil)
        #expect(KeyboardRow.target(.first, current: 0, count: 0) == nil)
    }
}
