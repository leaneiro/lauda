import SwiftUI

// The toolbar's controls, drawing their own Liquid Glass. The glass a toolbar
// gives its items is a still plate, with a grey highlight under the pointer;
// the tabs beside them are drawn with the interactive kind, which answers the
// pointer and gives under a click. Side by side the two felt like different
// materials, so the controls use the tabs' glass. Their sizes are the ones
// measured on the system's own buttons, which they stand in for.

/// A round toolbar button.
@available(macOS 26.0, *)
struct GlassToolbarButton<Icon: View>: View {
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    /// A toolbar button's size.
    static var side: CGFloat { 36 }

    var body: some View {
        Button(action: action) {
            icon()
                .frame(width: Self.side, height: Self.side)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }
}

/// The three view modes in one capsule, the one showing marked by a quiet
/// pill, which is also what the pointer brings up over the others.
@available(macOS 26.0, *)
struct GlassViewModePicker: View {
    @Binding var viewMode: ViewMode

    @State private var hovered: ViewMode?

    /// One mode's share of the capsule, and the pill inside it.
    private static let cell = CGSize(width: 46, height: 36)
    private static let pill = CGSize(width: 40, height: 28)

    /// The capsule's width, which the tab strip's arithmetic needs.
    static var width: CGFloat { cell.width * 3 }

    var body: some View {
        HStack(spacing: 0) {
            button(.editorOnly, "Editor Only", systemImage: "doc.plaintext")
            button(.split, "Editor and Preview", systemImage: "rectangle.split.2x1")
            button(.previewOnly, "Preview Only", systemImage: "doc.richtext")
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func button(_ mode: ViewMode, _ title: LocalizedStringKey, systemImage: String) -> some View {
        let isShowing = viewMode == mode
        return Button {
            viewMode = mode
        } label: {
            Image(systemName: systemImage)
                .font(ToolbarIcon.font)
                .foregroundStyle(ToolbarIcon.ink)
                .frame(width: Self.cell.width, height: Self.cell.height)
                .background {
                    Capsule()
                        .fill(Color.primary.opacity(isShowing ? 0.1 : hovered == mode ? 0.05 : 0))
                        .frame(width: Self.pill.width, height: Self.pill.height)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isOver in
            hovered = isOver ? mode : (hovered == mode ? nil : hovered)
        }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isShowing ? .isSelected : [])
    }
}

/// How the system draws a toolbar button's symbol, measured against its own
/// buttons at four times their size.
enum ToolbarIcon {
    static let font = Font.system(size: 17, weight: .medium)
    /// On glass the `.primary` style is drawn vibrant, a full black where
    /// the system's symbols are the label colour's softer one, and the label
    /// colour itself comes out paler than it is; this lands on the system's.
    static let ink = Color.primary.opacity(0.85)
}
