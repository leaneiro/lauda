import AppKit
import SwiftUI
import Testing
@testable import Lauda

/// The wheel clicked on a tab closes it: pressed and let go inside the tab's
/// shape, in a window that is taking clicks.
@MainActor
@Suite(.serialized)
struct MiddleClickTests {
    private static let middle = 2
    private static let size = NSSize(width: 120, height: 28)

    /// A capsule the size of a tab, in a window of its own.
    private func makeView(onClick: @escaping () -> Void) -> (MiddleClickView, NSWindow) {
        _ = NSApplication.shared
        let view = MiddleClickView(frame: NSRect(origin: NSPoint(x: 40, y: 10), size: Self.size))
        view.shape = AnyShape(Capsule())
        view.action = onClick
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 300, height: 60),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView?.addSubview(view)
        return (view, window)
    }

    /// A point of the view as events carry it, which is in the window's terms.
    private func location(_ x: CGFloat, _ y: CGFloat, in view: MiddleClickView) -> NSPoint {
        view.convert(NSPoint(x: x, y: y), to: nil)
    }

    @Test func aClickInsideRunsTheAction() {
        var clicks = 0
        let (view, window) = makeView { clicks += 1 }
        let centre = location(60, 14, in: view)

        #expect(view.takes(.otherMouseDown, button: Self.middle, at: centre, in: window))
        #expect(clicks == 0)
        #expect(view.takes(.otherMouseUp, button: Self.middle, at: centre, in: window))
        #expect(clicks == 1)
    }

    @Test func aPressThatLeavesBeforeTheButtonComesUpIsNoClick() {
        var clicks = 0
        let (view, window) = makeView { clicks += 1 }

        #expect(view.takes(.otherMouseDown, button: Self.middle, at: location(60, 14, in: view), in: window))
        // The release still ends a press made here, so it is taken too.
        #expect(view.takes(.otherMouseUp, button: Self.middle, at: location(200, 14, in: view), in: window))
        #expect(clicks == 0)
    }

    @Test func aReleaseThatBeganSomewhereElseIsNoClick() {
        var clicks = 0
        let (view, window) = makeView { clicks += 1 }

        #expect(!view.takes(.otherMouseDown, button: Self.middle, at: location(200, 14, in: view), in: window))
        #expect(!view.takes(.otherMouseUp, button: Self.middle, at: location(60, 14, in: view), in: window))
        #expect(clicks == 0)
    }

    /// The corners of the frame are outside a capsule, top and bottom alike.
    @Test(arguments: [CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 27), CGPoint(x: 119, y: 1), CGPoint(x: 119, y: 27)])
    func theShapeDecidesWhatIsInside(corner: CGPoint) {
        var clicks = 0
        let (view, window) = makeView { clicks += 1 }
        let point = location(corner.x, corner.y, in: view)

        #expect(!view.takes(.otherMouseDown, button: Self.middle, at: point, in: window))
        #expect(!view.takes(.otherMouseUp, button: Self.middle, at: point, in: window))
        #expect(clicks == 0)
    }

    @Test func theRoundedEndsAreInside() {
        var clicks = 0
        let (view, window) = makeView { clicks += 1 }
        let end = location(3, 14, in: view)

        #expect(view.takes(.otherMouseDown, button: Self.middle, at: end, in: window))
        #expect(view.takes(.otherMouseUp, button: Self.middle, at: end, in: window))
        #expect(clicks == 1)
    }

    /// A mouse's extra buttons are "other" buttons as well.
    @Test(arguments: [0, 1, 3, 4])
    func onlyTheMiddleButtonCounts(button: Int) {
        var clicks = 0
        let (view, window) = makeView { clicks += 1 }
        let centre = location(60, 14, in: view)

        #expect(!view.takes(.otherMouseDown, button: button, at: centre, in: window))
        #expect(!view.takes(.otherMouseUp, button: button, at: centre, in: window))
        #expect(clicks == 0)
    }

    @Test func aClickInAnotherWindowIsNotThisOnes() {
        var clicks = 0
        let (view, window) = makeView { clicks += 1 }
        let (_, other) = makeView {}
        let centre = location(60, 14, in: view)

        #expect(!view.takes(.otherMouseDown, button: Self.middle, at: centre, in: other))
        #expect(!view.takes(.otherMouseUp, button: Self.middle, at: centre, in: other))
        #expect(!view.takes(.otherMouseDown, button: Self.middle, at: centre, in: nil))
        #expect(clicks == 0)
        _ = window
    }

    @Test func nothingIsTakenWhileDisabled() {
        var clicks = 0
        let (view, window) = makeView { clicks += 1 }
        view.isEnabled = false
        let centre = location(60, 14, in: view)

        #expect(!view.takes(.otherMouseDown, button: Self.middle, at: centre, in: window))
        #expect(!view.takes(.otherMouseUp, button: Self.middle, at: centre, in: window))
        #expect(clicks == 0)
    }

    @Test func nothingIsTakenWhileHiddenOrOutOfAWindow() {
        var clicks = 0
        let (view, window) = makeView { clicks += 1 }
        let centre = location(60, 14, in: view)

        view.superview?.isHidden = true
        #expect(!view.takes(.otherMouseDown, button: Self.middle, at: centre, in: window))
        view.superview?.isHidden = false

        view.removeFromSuperview()
        #expect(!view.takes(.otherMouseDown, button: Self.middle, at: centre, in: window))
        #expect(clicks == 0)
    }

    /// A sheet keeps its window's clicks away from what is under it.
    @Test func nothingIsTakenUnderASheet() {
        var clicks = 0
        let (view, window) = makeView { clicks += 1 }
        let centre = location(60, 14, in: view)
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.orderFrontRegardless()
        window.beginSheet(sheet)
        defer { window.endSheet(sheet) }

        #expect(window.attachedSheet === sheet)
        #expect(!view.takes(.otherMouseDown, button: Self.middle, at: centre, in: window))
        #expect(!view.takes(.otherMouseUp, button: Self.middle, at: centre, in: window))
        #expect(clicks == 0)
    }

    @Test func itStaysOutOfHitTesting() {
        let (view, _) = makeView {}
        #expect(view.hitTest(NSPoint(x: 100, y: 24)) == nil)
    }

    // MARK: - Press and release

    @Test func pressAndReleaseInsideMakeAClick() {
        var click = ClickInPlace()
        let isTaken = click.press(inside: true)
        let release = click.release(inside: true)
        #expect(isTaken)
        #expect(release.wasPressedHere && release.isClick)
    }

    @Test func aPressIsGoodForOneReleaseOnly() {
        var click = ClickInPlace()
        _ = click.press(inside: true)
        _ = click.release(inside: true)
        let second = click.release(inside: true)
        #expect(!second.wasPressedHere && !second.isClick)
    }

    @Test func aPressOutsideForgetsAnUnfinishedOneInside() {
        var click = ClickInPlace()
        _ = click.press(inside: true)
        let isTaken = click.press(inside: false)
        let release = click.release(inside: true)
        #expect(!isTaken)
        #expect(!release.wasPressedHere && !release.isClick)
    }
}
