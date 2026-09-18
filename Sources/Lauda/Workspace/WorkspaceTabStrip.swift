import SwiftUI

/// The open documents, in the title bar where the title used to be. Shown
/// with two or more documents; a lone document keeps its title.
///
/// Each tab is a capsule of its own, as wide as its name asks for between a
/// minimum (so short names still make tabs of one size) and a maximum (so a
/// long name truncates instead of taking the bar). They line up from the
/// leading edge; the rest of the bar stays empty.
struct WorkspaceTabStrip: View {
    let workspace: Workspace
    /// The room the title bar has. The tabs don't fill it, but the item
    /// keeps it so the controls after it land at the trailing edge.
    let width: CGFloat

    @State private var hovered: ObjectIdentifier?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let height: CGFloat = 28
    private static let spacing: CGFloat = 6
    private static let minTabWidth: CGFloat = 120
    private static let maxTabWidth: CGFloat = 220

    /// How wide the view modes are in the toolbar: three glass buttons in one
    /// capsule where the system has them, a segmented control elsewhere.
    /// Measured.
    static var viewModesWidth: CGFloat {
        if #available(macOS 26.0, *) { 138 } else { 115 }
    }

    /// What the title bar has left for the tabs once the window's own
    /// buttons on one side and the controls on the other have their room.
    ///
    /// A toolbar lays its items out one after another and never grows one
    /// past the width it asks for, so it is this width that carries the
    /// controls to the trailing edge. The figures are measured: 96 points
    /// before the first item, the view modes, buttons of 36, and 8 between
    /// items and at the edge. An exact fit is too tight, and the toolbar then
    /// moves the controls into its overflow menu; four spare points were
    /// enough when measured, six leaves room for a width that isn't whole.
    static func width(in windowWidth: CGFloat, showsWidthButton: Bool) -> CGFloat {
        let leading: CGFloat = 96
        let gap: CGFloat = 8
        let spare: CGFloat = 6
        var controls = gap + viewModesWidth + gap + 36 + gap
        if showsWidthButton {
            controls += 36 + gap
        }
        return max(windowWidth - leading - controls - spare, 240)
    }

    var body: some View {
        container
            .frame(width: width, height: Self.height, alignment: .leading)
            // The strip animates its own tabs. Done from the workspace, with
            // the whole change inside an animation, the window's update
            // sometimes stopped halfway (see Workspace.stack).
            .animation(reduceMotion ? nil : .easeOut(duration: Workspace.tabAnimation), value: shownTabs.map(\.tabID))
            // The first tabs fade in rather than arrive: they are in the
            // strip from the start, because a toolbar leaves out for good
            // an item that holds nothing when it is made.
            .opacity(workspace.tabsAreIn ? 1 : 0)
            .scaleEffect(workspace.tabsAreIn ? 1 : 0.94, anchor: .leading)
            .allowsHitTesting(workspace.tabsAreIn)
            .animation(reduceMotion ? nil : .easeOut(duration: Workspace.tabAnimation), value: workspace.tabsAreIn)
    }

    /// A lone document has a title, not a tab: on the way from two documents
    /// to one both tabs go, and the title bar changes once they have.
    private var shownTabs: [MarkdownDocument] {
        workspace.documents.count >= 2 ? workspace.documents : []
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
            ForEach(shownTabs, id: \.tabID) { document in
                tab(document)
                    .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .leading)))
            }
            Spacer(minLength: 0)
        }
    }

    private func tab(_ document: MarkdownDocument) -> some View {
        let id = document.tabID
        let isSelected = document === workspace.selected
        let isHovered = hovered == id
        let showsDot = document.isEdited && !isHovered
        return ZStack {
            Text(document.title)
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
                .accessibilityLabel(document.isEdited ? "Close \(document.title), unsaved" : "Close \(document.title)")
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
        .help(document.fileURL?.path ?? document.title)
    }
}

extension MarkdownDocument {
    /// A document is its own tab; two documents are never the same one.
    var tabID: ObjectIdentifier { ObjectIdentifier(self) }
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
