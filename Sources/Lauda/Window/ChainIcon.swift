import SwiftUI

/// Two links of a chain on the diagonal, drawn as the system's link symbol
/// draws them, since the system has no open chain to pair with its closed
/// one: hooked into each other while the panes scroll together, each link
/// passing over the other at one crossing and under it at the other; a
/// little apart while they don't; and one state eases into the other.
struct ChainIcon: View {
    let linked: Bool

    var body: some View {
        Color.clear
            .frame(width: ChainDrawing.side, height: ChainDrawing.side)
            .modifier(ChainDrawing(openness: linked ? 0 : 1))
            // The ink's softness goes on the whole drawing: drawn with it,
            // the links would darken where they cross.
            .opacity(ToolbarIcon.inkOpacity)
            .animation(ToolbarIcon.stateChange, value: linked)
    }
}

/// The chain at a point between hooked (0) and apart (1), which a change
/// between them animates through.
private struct ChainDrawing: ViewModifier, Animatable {
    var openness: Double

    var animatableData: Double {
        get { openness }
        set { openness = newValue }
    }

    /// The system's link symbol at 17 pt, measured at 12x: links 11.7 by 8
    /// outside with a 2.25 stroke, their centres 6.7 apart along the
    /// diagonal; here a tenth larger, since the disc is smaller than a
    /// toolbar button but the chain is all it holds.
    private static let scale: CGFloat = 1.1
    private static let length = 11.7 * scale
    private static let width = 8 * scale
    private static let stroke = 2.25 * scale
    private static let hooked = 6.7 * scale
    /// Between the links' ends once apart: enough to read as a gap, and
    /// still well inside the disc.
    private static let gap: CGFloat = 2
    /// How much of the link underneath is cut away on each side of the one
    /// passing over it, wherever the two come that close on that side of
    /// the diagonal: at the crossing, and along the inside of the tip that
    /// sits in the other link's loop.
    private static let cut: CGFloat = 1.5 * scale
    /// Room for the chain apart, with its ends clear of this frame's edge.
    static let side: CGFloat = 30

    func body(content: Content) -> some View {
        content.overlay {
            Canvas { context, size in
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                let axis = CGPoint(x: 1 / sqrt(2), y: -1 / sqrt(2))
                let across = CGPoint(x: 1 / sqrt(2), y: 1 / sqrt(2))
                let distance = Self.hooked + (Self.length + Self.gap - Self.hooked) * openness
                let lower = Self.link(at: -distance / 2, from: centre, along: axis)
                let upper = Self.link(at: distance / 2, from: centre, along: axis)
                let ink = GraphicsContext.Shading.color(.primary)
                // Erasing takes the source's alpha, and the label colour is
                // not quite opaque: an opaque colour erases whole.
                let eraser = GraphicsContext.Shading.color(.black)
                // The two sides of the diagonal, one for each crossing.
                let far = size.width + size.height
                func side(_ sign: CGFloat) -> Path {
                    let point = { (along: CGFloat, over: CGFloat) in
                        CGPoint(x: centre.x + axis.x * along + across.x * over, y: centre.y + axis.y * along + across.y * over)
                    }
                    var path = Path()
                    path.move(to: point(-far, 0))
                    path.addLine(to: point(far, 0))
                    path.addLine(to: point(far, sign * far))
                    path.addLine(to: point(-far, sign * far))
                    path.closeSubpath()
                    return path
                }
                // The cut closes as the links come apart.
                let halo = Self.stroke + 2 * Self.cut * (1 - openness)

                // The lower link, then the upper one over it on one side of
                // the diagonal (the lower is cut around it there), then the
                // lower one over the upper on the other side.
                context.stroke(lower, with: ink, lineWidth: Self.stroke)
                var oneSide = context
                oneSide.clip(to: side(-1))
                oneSide.blendMode = .destinationOut
                oneSide.stroke(upper, with: eraser, lineWidth: halo)
                context.stroke(upper, with: ink, lineWidth: Self.stroke)
                var otherSide = context
                otherSide.clip(to: side(1))
                otherSide.blendMode = .destinationOut
                otherSide.stroke(lower, with: eraser, lineWidth: halo)
                otherSide.blendMode = .normal
                otherSide.stroke(lower, with: ink, lineWidth: Self.stroke)
            }
        }
    }

    /// One link: a ring along the diagonal, its centre `distance` from
    /// `centre`, drawn on the middle of its stroke so that its outside is
    /// `length` by `width`.
    private static func link(at distance: CGFloat, from centre: CGPoint, along axis: CGPoint) -> Path {
        let at = CGPoint(x: centre.x + axis.x * distance, y: centre.y + axis.y * distance)
        let rect = CGRect(x: -(length - stroke) / 2, y: -(width - stroke) / 2, width: length - stroke, height: width - stroke)
        return Path(roundedRect: rect, cornerRadius: (width - stroke) / 2)
            .applying(CGAffineTransform(translationX: at.x, y: at.y).rotated(by: -.pi / 4))
    }
}
