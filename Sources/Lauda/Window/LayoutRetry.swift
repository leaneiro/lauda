import Foundation

/// Work that needs the window to have laid out, when there is no event to
/// wait for. A pane comes up before its scroll view has a size, and a
/// document opens before its panes exist; both are ready within a frame or
/// two, so the work is tried again shortly rather than waited on.
///
/// Two seconds of turns, at 25 ms each: enough for a window that opens with
/// the app on a cold launch, measured, and short enough that a pane which
/// never lays out stops asking instead of retrying for ever.
struct LayoutRetry {
    static let interval: TimeInterval = 0.025
    static let limit = 80

    private var attempts = 0

    /// Asks for `work` to run again shortly. False when the turns have run
    /// out, which is the caller's cue to give up.
    mutating func again(_ work: @escaping () -> Void) -> Bool {
        attempts += 1
        guard attempts < Self.limit else { return false }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.interval, execute: work)
        return true
    }

    mutating func startOver() {
        attempts = 0
    }
}
