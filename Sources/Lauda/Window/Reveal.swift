import SwiftUI

/// How a control comes and goes: fading, and growing from a little smaller,
/// over a moment. Out of view it takes no clicks; it stays in the view, so
/// its place is kept and nothing around it moves. The toolbar's text width
/// button comes with its mode, and the divider's chain with the pointer,
/// while there is something to scroll.
struct Reveal: ViewModifier {
    let isShown: Bool
    let duration: TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Small enough to read as arriving, not as a change of size.
    private static let hiddenScale: CGFloat = 0.8

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .scaleEffect(isShown ? 1 : Self.hiddenScale)
            .animation(reduceMotion ? nil : .easeInOut(duration: duration), value: isShown)
            .allowsHitTesting(isShown)
    }
}
