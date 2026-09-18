import AppKit
import SwiftUI

extension View {
    /// Runs an action on a click of the mouse's middle button (the wheel)
    /// inside a shape. SwiftUI has gestures for the other two buttons only.
    func onMiddleClick(
        in shape: some Shape, isEnabled: Bool = true, perform action: @escaping () -> Void
    ) -> some View {
        background {
            MiddleClickCatcher(shape: AnyShape(shape), isEnabled: isEnabled, action: action)
                .allowsHitTesting(false)
        }
    }
}

private struct MiddleClickCatcher: NSViewRepresentable {
    let shape: AnyShape
    let isEnabled: Bool
    let action: () -> Void

    func makeNSView(context: Context) -> MiddleClickView {
        MiddleClickView()
    }

    func updateNSView(_ view: MiddleClickView, context: Context) {
        view.shape = shape
        view.isEnabled = isEnabled
        view.action = action
    }

    static func dismantleNSView(_ view: MiddleClickView, coordinator: ()) {
        view.stopWatching()
    }
}

/// Takes the middle button's clicks that land in it. It watches the app's
/// events instead of taking part in hit testing: to be hit it would have to
/// sit in front of the SwiftUI view, in the way of its clicks, of the pointer
/// hovering over it and of its glass answering the pointer.
final class MiddleClickView: NSView {
    var shape = AnyShape(Rectangle())
    var isEnabled = true
    var action: () -> Void = {}

    private var click = ClickInPlace()
    private var monitor: Any?

    private static let middleButton = 2

    override init(frame: NSRect) {
        super.init(frame: frame)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .otherMouseUp]) { [weak self] event in
            guard let self else { return event }
            let isTaken = MainActor.assumeIsolated {
                self.takes(event.type, button: event.buttonNumber, at: event.locationInWindow, in: event.window)
            }
            return isTaken ? nil : event
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func stopWatching() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    /// The shape is SwiftUI's, which counts from the top.
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    /// Whether an event is part of a click here, which nothing else then
    /// gets. The button's number tells the wheel from a mouse's extra
    /// buttons, which are "other" buttons too.
    func takes(
        _ type: NSEvent.EventType, button: Int, at locationInWindow: NSPoint, in eventWindow: NSWindow?
    ) -> Bool {
        guard button == Self.middleButton else { return false }
        let isInside = canBeClicked(in: eventWindow) && contains(locationInWindow)
        switch type {
        case .otherMouseDown:
            return click.press(inside: isInside)
        case .otherMouseUp:
            let release = click.release(inside: isInside)
            if release.isClick {
                action()
            }
            return release.wasPressedHere
        default:
            return false
        }
    }

    /// A window under a sheet, or behind a modal one, takes no clicks. Its
    /// events being watched from outside would get around that.
    private func canBeClicked(in eventWindow: NSWindow?) -> Bool {
        guard isEnabled, let window, eventWindow === window, !isHiddenOrHasHiddenAncestor else { return false }
        guard window.attachedSheet == nil else { return false }
        return NSApp.modalWindow == nil || NSApp.modalWindow === window
    }

    private func contains(_ locationInWindow: NSPoint) -> Bool {
        let point = convert(locationInWindow, from: nil)
        return shape.path(in: bounds).contains(point)
    }
}

/// A button's click on one place: pressed there and let go there. A press
/// that wanders off before the button comes up is no click, and neither is a
/// release that began somewhere else.
struct ClickInPlace {
    private var isPressed = false

    /// A press; whether it is this place's.
    mutating func press(inside: Bool) -> Bool {
        isPressed = inside
        return inside
    }

    /// A release: whether it ends a press made here, and whether the two
    /// make a click.
    mutating func release(inside: Bool) -> (wasPressedHere: Bool, isClick: Bool) {
        defer { isPressed = false }
        return (isPressed, isPressed && inside)
    }
}
