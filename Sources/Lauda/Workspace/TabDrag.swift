import CoreGraphics

/// A tab dragged along the strip to a new place among the others, as
/// browsers reorder tabs: it follows the pointer, held within the strip, and
/// the tabs it passes move aside to make room for it. Everything is measured
/// against where the tabs stood when the drag began, not where they are
/// moved to on the way. The Electron edition's tab-drag.ts has the same
/// rules, with the same cases in its tests, all but where the dragged tab is
/// drawn (`width`, `position`, `place`): that edition measures it on the
/// page.
struct TabDrag {
    /// The tab dragged, and where it was.
    let id: ObjectIdentifier
    let from: Int
    /// Every tab's edges when the drag began, the dragged one's included.
    private let lefts: [CGFloat]
    private let rights: [CGFloat]
    /// The room the tabs it passes make: its own width and the gap after it.
    private let room: CGFloat
    /// How far the pointer has gone since the press.
    var translation: CGFloat = 0
    /// A tab opened or closed on the way changes the places the drag
    /// measures against: it ends there, every tab back in its place.
    var isCancelled = false

    /// The tabs side by side, `spacing` apart, as wide as they are drawn.
    init(id: ObjectIdentifier, from: Int, widths: [CGFloat], spacing: CGFloat) {
        self.id = id
        self.from = from
        var lefts: [CGFloat] = []
        var left: CGFloat = 0
        for width in widths {
            lefts.append(left)
            left += width + spacing
        }
        self.lefts = lefts
        rights = zip(lefts, widths).map { $0 + $1 }
        room = widths[from] + spacing
    }

    /// How far the dragged tab has moved: with the pointer, but no further
    /// than the first tab's place on one side and the last one's on the other.
    var shift: CGFloat {
        min(max(translation, lefts[0] - lefts[from]), rights[rights.count - 1] - rights[from])
    }

    /// The place the dragged tab takes if it is let go now.
    var target: Int {
        let middles = zip(lefts, rights).map { ($0 + $1) / 2 }
        return Self.dropIndex(middles: middles, from: from, left: lefts[from] + shift, right: rights[from] + shift)
    }

    /// The dragged tab's width, and where its left edge stands, measured from
    /// the first tab's: now, and in the order it takes if let go now.
    var width: CGFloat { rights[from] - lefts[from] }
    var position: CGFloat { lefts[from] + shift }
    var place: CGFloat { target >= from ? rights[target] - width : lefts[target] }

    /// How far the tab at `index` stands aside for the dragged one.
    func roomOffset(of index: Int) -> CGFloat {
        Self.offset(of: index, from: from, to: target, room: room)
    }

    /// The dragged tab's new place: going right it passes each tab whose
    /// middle its right edge has crossed, going left each one whose middle
    /// its left edge has crossed. `middles` are every tab's, the dragged
    /// one's included, where they stood when the drag began; `left` and
    /// `right` are the dragged tab's edges now.
    static func dropIndex(middles: [CGFloat], from: Int, left: CGFloat, right: CGFloat) -> Int {
        let passedRight = middles.indices.filter { $0 > from && middles[$0] < right }.count
        let passedLeft = middles.indices.filter { $0 < from && middles[$0] > left }.count
        return from + passedRight - passedLeft
    }

    /// How far the tab at `index` moves aside while the one at `from` is
    /// dragged to `to`: the tabs it passes shift the other way by `room`.
    static func offset(of index: Int, from: Int, to: Int, room: CGFloat) -> CGFloat {
        if index == from { return 0 }
        if from < index && index <= to { return -room }
        if to <= index && index < from { return room }
        return 0
    }
}
