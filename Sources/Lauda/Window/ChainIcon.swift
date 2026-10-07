import SwiftUI

/// Two links of a chain on the diagonal, as in the system's link symbol:
/// interlocked while the panes scroll together, pulled apart while each
/// scrolls on its own. Drawn here because the system has no open chain to
/// pair with its closed one, and so that one state animates into the other.
struct ChainIcon: View {
    let linked: Bool

    /// How far each link sits from the centre, along the diagonal: close
    /// enough to overlap, or clear of the other with a gap between, and
    /// still inside the button's disc.
    private var spread: CGFloat { linked ? 3.2 : 5.6 }

    var body: some View {
        ZStack {
            link.offset(x: -spread, y: spread)
            link.offset(x: spread, y: -spread)
        }
        .frame(width: 30, height: 30)
        .animation(ToolbarIcon.stateChange, value: linked)
    }

    private var link: some View {
        Capsule()
            .strokeBorder(ToolbarIcon.ink, lineWidth: 1.9)
            .frame(width: 14, height: 7.5)
            .rotationEffect(.degrees(-45))
    }
}
