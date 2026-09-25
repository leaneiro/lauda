import Foundation
import Testing
@testable import Lauda

@Suite struct TabListTests {
    private final class Doc {
        let name: String
        init(_ name: String) { self.name = name }
    }

    private func list(_ names: String...) -> (TabList<Doc>, [Doc]) {
        var tabs = TabList<Doc>()
        let docs = names.map(Doc.init)
        for doc in docs { tabs.add(doc) }
        return (tabs, docs)
    }

    @Test func aNewTabIsTheOneShowing() {
        let (tabs, docs) = list("a", "b")

        #expect(tabs.items.map(\.name) == ["a", "b"])
        #expect(tabs.selected === docs[1])
        #expect(tabs.selectedIndex == 1)
    }

    @Test func aMovedTabKeepsTheSelectionOnTheTabItWas() {
        var (tabs, docs) = list("a", "b", "c")

        tabs.move(docs[0], to: 2)
        #expect(tabs.items.map(\.name) == ["b", "c", "a"])
        #expect(tabs.selected === docs[2])

        tabs.move(docs[2], to: 0)
        #expect(tabs.items.map(\.name) == ["c", "b", "a"])

        // A place past the end is the end.
        tabs.move(docs[1], to: 9)
        #expect(tabs.items.map(\.name) == ["c", "a", "b"])
    }

    /// The crash: two tabs, the second showing, the first one closed. With
    /// the selection kept as a position, position 1 outlived a list of one.
    @Test func closingTheFirstTabWhileTheSecondShowsKeepsTheSecond() {
        var (tabs, docs) = list("a", "b")

        tabs.remove(docs[0])

        #expect(tabs.items.map(\.name) == ["b"])
        #expect(tabs.selected === docs[1])
        #expect(tabs.selectedIndex == 0, "the index follows the item, never past the end")
    }

    @Test func closingTheTabShowingHandsOverToTheOneThatTakesItsPlace() {
        var (tabs, docs) = list("a", "b", "c")
        tabs.select(docs[1])

        tabs.remove(docs[1])

        #expect(tabs.selected === docs[2])
    }

    @Test func closingTheLastTabWhileItShowsHandsOverToTheOneBefore() {
        var (tabs, docs) = list("a", "b")

        tabs.remove(docs[1])

        #expect(tabs.selected === docs[0])
    }

    @Test func closingATabThatIsNotShowingLeavesTheSelectionAlone() {
        var (tabs, docs) = list("a", "b", "c")
        tabs.select(docs[1])

        tabs.remove(docs[2])

        #expect(tabs.selected === docs[1])
        #expect(tabs.selectedIndex == 1)
    }

    @Test func closingTheOnlyTabLeavesNothingShowing() {
        var (tabs, docs) = list("a")

        tabs.remove(docs[0])

        #expect(tabs.items.isEmpty)
        #expect(tabs.selected == nil)
        #expect(tabs.selectedIndex == nil)
    }

    /// However tabs come and go, the selection is one of the items or nil.
    @Test func theSelectionIsAlwaysOneOfTheTabs() {
        var (tabs, docs) = list("a", "b", "c", "d")
        for doc in [docs[0], docs[3], docs[1], docs[2]] {
            tabs.remove(doc)
            if let selected = tabs.selected {
                #expect(tabs.contains(selected))
                #expect(tabs.selectedIndex != nil)
            } else {
                #expect(tabs.items.isEmpty)
            }
        }
    }

    @Test func selectingOrRemovingAStrangerChangesNothing() {
        var (tabs, docs) = list("a", "b")
        let stranger = Doc("x")

        tabs.select(stranger)
        tabs.remove(stranger)

        #expect(tabs.items.count == 2)
        #expect(tabs.selected === docs[1])
    }

    @Test func addingATabTwiceKeepsOneAndShowsIt() {
        var (tabs, docs) = list("a", "b")

        tabs.add(docs[0])

        #expect(tabs.items.count == 2)
        #expect(tabs.selected === docs[0])
    }
}
