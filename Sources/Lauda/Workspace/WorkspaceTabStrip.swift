import SwiftUI

// SPIKE: the open documents in the title bar. Each tab is a capsule of its
// own, as wide as its name asks for between a minimum (so short names still
// make tabs of one size) and a maximum (so a long name truncates instead of
// taking the bar). They line up from the leading edge; the rest stays empty.
struct WorkspaceTabStrip: View {
    let workspace: Workspace
    /// The room the title bar has; the tabs don't fill it, but the item
    /// keeps it so the controls after it land at the trailing edge.
    let width: CGFloat

    @State private var hovered: ObjectIdentifier?

    private static let height: CGFloat = 28
    private static let spacing: CGFloat = 6
    private static let minTabWidth: CGFloat = 120
    private static let maxTabWidth: CGFloat = 220

    var body: some View {
        container
            .frame(width: width, height: Self.height, alignment: .leading)
    }

    /// Glass shapes that sit close to each other render as one pass, and
    /// blend when a tab comes or goes.
    @ViewBuilder
    private var container: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: Self.spacing) { row }
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: Self.spacing) {
            ForEach(workspace.documents, id: \.tabID) { document in
                tab(document)
                    .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .leading)))
            }
            Spacer(minLength: 0)
        }
    }

    private func tab(_ document: MarkdownNSDocument) -> some View {
        let id = document.tabID
        let isSelected = document === workspace.selected
        let isHovered = hovered == id
        let showsDot = document.isEdited && !isHovered
        return ZStack {
            Text(document.displayName ?? "")
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? .primary : .secondary)
                // Room for the close button, mirrored so the name stays centred.
                .padding(.horizontal, 26)
            HStack {
                Button {
                    workspace.close(document)
                } label: {
                    Image(systemName: showsDot ? "circle.fill" : "xmark")
                        .font(.system(size: showsDot ? 7 : 8, weight: .bold))
                        .foregroundStyle(showsDot ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isHovered || isSelected || showsDot ? 1 : 0)
                Spacer(minLength: 0)
            }
            .padding(.leading, 7)
        }
        .frame(minWidth: Self.minTabWidth, maxWidth: Self.maxTabWidth)
        .frame(height: Self.height)
        .modifier(TabCapsule(isSelected: isSelected))
        .contentShape(Capsule())
        .onTapGesture { workspace.select(document) }
        .onHover { hovering in
            hovered = hovering ? id : (hovered == id ? nil : hovered)
        }
        .help(document.fileURL?.path ?? document.displayName ?? "")
    }
}

/// A tab's own capsule: glass where the system has it, a quiet fill where it
/// doesn't. The one showing is the more solid of the two.
private struct TabCapsule: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(isSelected ? .regular.interactive() : .clear.interactive(), in: .capsule)
        } else {
            content.background(
                Capsule().fill(isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quaternary.opacity(0.35)))
            )
        }
    }
}
