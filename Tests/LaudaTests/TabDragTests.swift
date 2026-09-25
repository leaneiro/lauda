import AppKit
import Testing
@testable import Lauda

/// Dragging a tab to a new place. The Electron edition's tabDrag.test.ts
/// has the same cases, all but where the dragged tab is drawn, which that
/// edition measures on the page, and the workspace's, which its end-to-end
/// drag test covers.
@MainActor @Suite struct TabDragTests {
    private final class Tab {}

    // Four tabs 100 wide, side by side from 0: middles at 50, 150, 250, 350.
    private let middles: [CGFloat] = [50, 150, 250, 350]

    @Test func aTabPassesAnotherOnceItsLeadingEdgeCrossesThatTabsMiddle() {
        // The first tab, dragged right.
        #expect(TabDrag.dropIndex(middles: middles, from: 0, left: 40, right: 140) == 0)
        #expect(TabDrag.dropIndex(middles: middles, from: 0, left: 60, right: 160) == 1)
        #expect(TabDrag.dropIndex(middles: middles, from: 0, left: 300, right: 400) == 3)
        // The last tab, dragged left.
        #expect(TabDrag.dropIndex(middles: middles, from: 3, left: 260, right: 360) == 3)
        #expect(TabDrag.dropIndex(middles: middles, from: 3, left: 240, right: 340) == 2)
        #expect(TabDrag.dropIndex(middles: middles, from: 3, left: 0, right: 100) == 0)
    }

    @Test func theWidestTabStillReachesTheEnd() {
        // Widths 200, 100, 100: held within the strip, the first tab's right
        // edge gets to 400, past the last tab's middle.
        #expect(TabDrag.dropIndex(middles: [100, 250, 350], from: 0, left: 200, right: 400) == 2)
    }

    @Test func theTabsItPassesMoveAsideTheOtherWay() {
        // From the first place to the third: the two it passes move left.
        #expect((0..<4).map { TabDrag.offset(of: $0, from: 0, to: 2, room: 100) } == [0, -100, -100, 0])
        // From the last place to the first: the others move right.
        #expect((0..<4).map { TabDrag.offset(of: $0, from: 3, to: 0, room: 100) } == [100, 100, 100, 0])
        // Back where it started: nothing moves.
        #expect((0..<4).map { TabDrag.offset(of: $0, from: 1, to: 1, room: 100) } == [0, 0, 0, 0])
    }

    /// The drag as the strip runs it, from the tabs' widths and the gap
    /// between them.
    @Test func aDraggedTabFollowsThePointerWithinTheStrip() {
        var drag = TabDrag(id: ObjectIdentifier(Tab()), from: 0, widths: [100, 100, 100, 100], spacing: 6)

        // Past the second tab's middle (156), not yet the third's (262).
        drag.translation = 60
        #expect(drag.shift == 60)
        #expect(drag.target == 1)
        #expect((0..<4).map(drag.roomOffset(of:)) == [0, -106, 0, 0])

        // Far past the end, it stops at the last tab's place.
        drag.translation = 1000
        #expect(drag.shift == 318)
        #expect(drag.target == 3)
        #expect((0..<4).map(drag.roomOffset(of:)) == [0, -106, -106, -106])

        // And never goes before the first.
        drag.translation = -50
        #expect(drag.shift == 0)
        #expect(drag.target == 0)
    }

    /// Where the dragged tab is drawn, measured from the first tab's left
    /// edge: where it stands, and the place it lands in, going right or
    /// left, or back in its own.
    @Test func aDraggedTabKnowsWhereItStandsAndWhereItLands() {
        let widths: [CGFloat] = [100, 100, 100, 100]
        var right = TabDrag(id: ObjectIdentifier(Tab()), from: 0, widths: widths, spacing: 6)
        #expect(right.width == 100)
        right.translation = 60
        // At 60, its place in the new order is the second, at 106.
        #expect(right.position == 60)
        #expect(right.place == 106)
        right.translation = 1000
        #expect(right.position == 318)
        #expect(right.place == 318)

        var left = TabDrag(id: ObjectIdentifier(Tab()), from: 3, widths: widths, spacing: 6)
        left.translation = -250
        // From 318 to 68: past the third and second tabs' middles.
        #expect(left.target == 1)
        #expect(left.position == 68)
        #expect(left.place == 106)

        var back = TabDrag(id: ObjectIdentifier(Tab()), from: 1, widths: widths, spacing: 6)
        back.translation = 30
        #expect(back.target == 1)
        #expect(back.position == 136)
        #expect(back.place == 106)
    }

    /// A tab dropped in a new place: the order the strip shows, the tab keys
    /// walk and the next launch opens.
    @Test func aDroppedTabKeepsItsPlace() throws {
        _ = NSApplication.shared
        let defaults = TestDefaults()
        let workspace = Workspace(defaults: defaults, showsWindow: false)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lauda-order-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var documents: [MarkdownDocument] = []
        for name in ["a.md", "b.md", "c.md"] {
            let url = folder.appendingPathComponent(name)
            try Data("# \(name)".utf8).write(to: url)
            let document = try MarkdownDocument(contentsOf: url, ofType: "net.daringfireball.markdown")
            workspace.add(document)
            documents.append(document)
        }
        workspace.select(documents[0])

        workspace.moveTab(documents[0], to: 2)

        #expect(workspace.documents.map { $0.fileURL?.lastPathComponent } == ["b.md", "c.md", "a.md"])
        #expect(workspace.selected === documents[0])
        let stored = OpenSession.stored(defaults: defaults)
        #expect(stored.urls.map(\.lastPathComponent) == ["b.md", "c.md", "a.md"])
        #expect(stored.selected?.lastPathComponent == "a.md")
        workspace.selectTab(.first)
        #expect(workspace.selected === documents[1])
    }
}
