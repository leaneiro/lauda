import SwiftUI
import AppKit

/// Draggable pane divider. The stored fraction survives view-mode switches
/// (⌘1/⌘2/⌘3), so split view always comes back where the user left it.
/// Under the pointer it shows the chain that parts the panes' scrolling.
struct SplitDivider: View {
    @Binding var fraction: Double
    /// Whether the panes scroll together; the chain flips it.
    @Binding var scrollsLinked: Bool
    let totalWidth: CGFloat
    let minPaneWidth: CGFloat

    /// Where the pointer is: on the divider, or on the chain, which takes
    /// it from the divider.
    @State private var isHovered = false
    @State private var isChainHovered = false

    static let thickness: CGFloat = 1
    private static let hitAreaWidth: CGFloat = 11
    /// How long the chain takes to appear or go: quick, so it is there by
    /// the time the pointer comes to rest on the divider.
    private static let revealDuration: TimeInterval = 0.15

    static func clamp(_ fraction: Double, totalWidth: CGFloat, minPaneWidth: CGFloat) -> Double {
        guard totalWidth > minPaneWidth * 2 else { return 0.5 }
        let minFraction = minPaneWidth / totalWidth
        return min(max(fraction, minFraction), 1 - minFraction)
    }

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: Self.thickness)
            .frame(maxHeight: .infinity)
            .overlay {
                Color.clear
                    .frame(width: Self.hitAreaWidth)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        isHovered = hovering
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("split"))
                            .onChanged { value in
                                fraction = Self.clamp(
                                    value.location.x / totalWidth,
                                    totalWidth: totalWidth,
                                    minPaneWidth: minPaneWidth
                                )
                            }
                    )
            }
            .overlay {
                ScrollLinkButton(linked: $scrollsLinked)
                    .onHover { isChainHovered = $0 }
                    .modifier(Reveal(isShown: showsChain, duration: Self.revealDuration))
            }
            // A divider that goes with its mode while the pointer is on it
            // would leave the resize cursor behind.
            .onDisappear {
                if isHovered { NSCursor.pop() }
            }
    }

    /// The chain shows while the pointer is on the divider or on the chain
    /// itself; the pointer reaches the chain through the divider, since out
    /// of view it takes no clicks. VoiceOver reaches it either way.
    private var showsChain: Bool { isHovered || isChainHovered }
}

/// The chain in the middle of the divider: closed while the panes scroll
/// together, open while each scrolls on its own.
private struct ScrollLinkButton: View {
    @Binding var linked: Bool

    private static let side: CGFloat = 28

    var body: some View {
        Button {
            linked.toggle()
        } label: {
            ChainIcon(linked: linked)
                .frame(width: Self.side, height: Self.side)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(RoundPlate())
        .help(title)
        .accessibilityLabel(title)
    }

    /// What a click does, which is what the tip and VoiceOver say.
    private var title: LocalizedStringKey {
        linked ? "Scroll the panes separately" : "Scroll the panes together"
    }
}

/// The round glass of a toolbar button where the system has glass, and a
/// plain disc where it hasn't (macOS 14 and 15).
private struct RoundPlate: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .background {
                    Circle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                }
                .overlay {
                    Circle().strokeBorder(Color(nsColor: .separatorColor))
                }
        }
    }
}
