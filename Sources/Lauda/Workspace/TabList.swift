import Foundation

/// The open tabs and the one showing. The selection is the item itself, not
/// its position: a list that shrinks can then never leave the selection
/// pointing past its end, which is what crashed the app when the first tab
/// was closed with the second one showing. Each change is one mutation, so
/// nothing reading in between sees half of it.
struct TabList<Item: AnyObject> {
    private(set) var items: [Item] = []
    private(set) var selected: Item?

    var selectedIndex: Int? {
        guard let selected else { return nil }
        return items.firstIndex { $0 === selected }
    }

    func contains(_ item: Item) -> Bool {
        items.contains { $0 === item }
    }

    /// A new tab opens at the end and is the one showing.
    mutating func add(_ item: Item) {
        if !contains(item) {
            items.append(item)
        }
        selected = item
    }

    mutating func select(_ item: Item) {
        guard contains(item) else { return }
        selected = item
    }

    /// Removes a tab. If it was the one showing, the tab that slides into
    /// its place takes over, or the one before it when it was the last.
    mutating func remove(_ item: Item) {
        guard let index = items.firstIndex(where: { $0 === item }) else { return }
        items.remove(at: index)
        guard selected === item else { return }
        selected = items.isEmpty ? nil : items[Swift.min(index, items.count - 1)]
    }
}
