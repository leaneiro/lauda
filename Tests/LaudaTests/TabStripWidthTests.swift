import Foundation
import Testing
@testable import Lauda

/// The strip's width is what carries the toolbar's controls to the trailing
/// edge, so it is worked out rather than left to the toolbar.
@Suite struct TabStripWidthTests {
    @Test func theStripTakesWhatTheControlsLeave() {
        // 1200 - 96 before the first item - (8 + 115 + 8 + 36 + 8) of controls
        // - 6 spare, without which the toolbar overflows the controls.
        #expect(WorkspaceTabStrip.width(in: 1200, showsWidthButton: false) == 923)
    }

    /// Preview-only mode brings the text width button, which needs its room
    /// or the controls run past the window's edge.
    @Test func theWidthButtonTakesItsShare() {
        let without = WorkspaceTabStrip.width(in: 1200, showsWidthButton: false)
        let with = WorkspaceTabStrip.width(in: 1200, showsWidthButton: true)

        #expect(without - with == 44)
    }

    @Test func aWiderWindowGivesTheTabsTheDifference() {
        let narrow = WorkspaceTabStrip.width(in: 1000, showsWidthButton: false)
        let wide = WorkspaceTabStrip.width(in: 1400, showsWidthButton: false)

        #expect(wide - narrow == 400)
    }

    @Test func aVeryNarrowWindowStillLeavesAStrip() {
        #expect(WorkspaceTabStrip.width(in: 300, showsWidthButton: true) == 240)
    }
}
