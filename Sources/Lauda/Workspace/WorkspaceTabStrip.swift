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
    /// The tab being dragged along the strip, if any.
    @State private var drag: TabDrag?
    /// The tab just let go, on its way from where it was dropped into its
    /// place in the new order.
    @State private var landing: Landing?
    /// Where each tab is laid out, in the gestures' terms: what a drag
    /// measures against, and where a click has to be let go.
    @State private var tabFrames: [ObjectIdentifier: CGRect] = [:]
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let height: CGFloat = 28
    private static let spacing: CGFloat = 6
    private static let minTabWidth: CGFloat = 120
    private static let maxTabWidth: CGFloat = 220
    /// How far the pointer goes before a press on a tab becomes a drag;
    /// less is still a click.
    private static let dragThreshold: CGFloat = 4

    /// How wide the view modes are in the toolbar: our own glass capsule
    /// where the system has Liquid Glass, a segmented control (measured)
    /// elsewhere.
    static var viewModesWidth: CGFloat {
        if #available(macOS 26.0, *) { GlassViewModePicker.width } else { 115 }
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
        let gap = ToolbarMetrics.gap
        let button = ToolbarMetrics.buttonSide
        let spare: CGFloat = 6
        var controls = gap + viewModesWidth + gap + button + gap
        if showsWidthButton {
            controls += button + gap
        }
        return max(windowWidth - ToolbarMetrics.leading - controls - spare, 240)
    }

    var body: some View {
        container
            .frame(width: width, height: Self.height, alignment: .leading)
            // The strip animates its own tabs. Done from the workspace, with
            // the whole change inside an animation, the window's update
            // sometimes stopped halfway (see Workspace.stack).
            .animation(motion, value: shownTabs.map(\.tabID))
            // The first tabs fade in rather than arrive: they are in the
            // strip from the start, because a toolbar leaves out for good
            // an item that holds nothing when it is made.
            .opacity(workspace.tabsAreIn ? 1 : 0)
            .scaleEffect(workspace.tabsAreIn ? 1 : 0.94, anchor: .leading)
            .allowsHitTesting(workspace.tabsAreIn)
            .animation(motion, value: workspace.tabsAreIn)
    }

    /// How the tabs move, or not with Reduce Motion.
    private var motion: Animation? {
        reduceMotion ? nil : .easeOut(duration: Workspace.tabAnimation)
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
        // The tabs are one stop for the keyboard, with Keyboard Navigation
        // on as for every control: the arrows move along them, selecting as
        // they go, Home and End go to the ends, and Return or Space goes
        // into the document. The Electron edition walks its tabs the same
        // way. The ring is the selected tab's, not the strip's. With no
        // tabs in view, the strip is no stop at all.
        .focusable(hasTabs, interactions: .activate)
        .focused($isFocused)
        .focusEffectDisabled()
        .onMoveCommand { direction in
            switch direction {
            case .left: workspace.selectTab(.previous, keyboard: .stays)
            case .right: workspace.selectTab(.next, keyboard: .stays)
            default: break
            }
        }
        .onKeyPress(keys: [.home, .end, .return, .space]) { press in
            switch press.key {
            case .home: workspace.selectTab(.first, keyboard: .stays)
            case .end: workspace.selectTab(.last, keyboard: .stays)
            default: _ = workspace.selected?.takeKeyboard(in: workspace.viewMode)
            }
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Open Documents")
        .accessibilityAddTraits(.isTabBar)
        .accessibilityHidden(!hasTabs)
        .onChange(of: shownTabs.map(\.tabID)) { _, ids in
            tabFrames = tabFrames.filter { ids.contains($0.key) }
            // A tab opened or closed during a drag ends it. A dragged tab
            // that closes takes its gesture with it, and nothing but this
            // is left to end its drag.
            guard let drag else { return }
            guard ids.contains(drag.id) else {
                self.drag = nil
                return
            }
            guard !drag.isCancelled else { return }
            withAnimation(motion) {
                self.drag?.isCancelled = true
                landing = Landing(id: drag.id, offset: drag.shift)
            }
        }
        // The tab let go slides into its place, still over the others, and
        // goes back among them once it is there. The glass of tabs is drawn
        // together, in their drawing order: a tab changing places in it
        // during an animation made its glass appear anew, from a speck.
        .onChange(of: landing) { _, landing in
            guard let landing, !landing.isSliding else { return }
            guard let motion, landing.offset != 0 else {
                withTransaction(Self.still) { self.landing = nil }
                return
            }
            withAnimation(motion) {
                self.landing = Landing(id: landing.id, offset: 0, isSliding: true)
            } completion: {
                guard self.landing?.id == landing.id else { return }
                withTransaction(Self.still) { self.landing = nil }
            }
        }
    }

    /// A change with nothing to animate, whatever the views ask for.
    private static var still: Transaction {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        return transaction
    }

    /// The drag under way, unless it was cancelled.
    private var activeDrag: TabDrag? {
        drag?.isCancelled == false ? drag : nil
    }

    /// Tabs in view: there are two documents or more, and they have come in.
    private var hasTabs: Bool {
        !shownTabs.isEmpty && workspace.tabsAreIn
    }

    private func tab(_ document: MarkdownDocument) -> some View {
        let id = document.tabID
        let isSelected = document === workspace.selected
        let isHovered = hovered == id
        let isDragged = activeDrag?.id == id
        let isLanding = landing?.id == id
        let roomOffset = shownTabs.firstIndex { $0 === document }.flatMap { activeDrag?.roomOffset(of: $0) } ?? 0
        let showsDot = document.isEdited && !isHovered
        return ZStack {
            Text(document.title)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? .primary : .secondary)
                // Room for the close button, mirrored so the name stays centred.
                .padding(.horizontal, 26)
                // What VoiceOver reads as the tab: its name, whether it is
                // the one showing, and choosing it; the close button beside
                // it says whether its text is saved.
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { workspace.select(document) }
                // The name takes the whole tab, and the clicks and drags
                // on it; not the close button's, which sits over it rather
                // than inside it.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Capsule())
                .gesture(pressOrDrag(document))
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
        .overlay {
            if isFocused && isSelected {
                Capsule()
                    .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                    .padding(-3)
            }
        }
        .contentShape(Capsule())
        // The wheel closes the tab it is clicked on, wherever on it.
        .onMiddleClick(in: Capsule(), isEnabled: workspace.tabsAreIn) { workspace.close(document) }
        .onHover { hovering in
            hovered = hovering ? id : (hovered == id ? nil : hovered)
        }
        .help(document.fileURL?.path ?? document.title)
        // The tabs a dragged one passes move aside for it, and it follows
        // the pointer, over them.
        .offset(x: roomOffset)
        .animation(motion, value: roomOffset)
        .offset(x: isDragged ? activeDrag?.shift ?? 0 : isLanding ? landing?.offset ?? 0 : 0)
        .zIndex(isDragged || isLanding ? 1 : 0)
        // Measured outside the shifts, which leave the tab's frame where
        // it is laid out.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { tabFrames[id] = $0 }
    }

    /// A click shows the tab. Moved sideways past a few points, the press
    /// becomes a drag: the tab shows and follows the pointer along the
    /// strip, and where it is let go becomes its place among the others, in
    /// the strip, the tab keys and the session.
    private func pressOrDrag(_ document: MarkdownDocument) -> some Gesture {
        // In the window's terms: the tab moves under the pointer as it is
        // dragged, and its own terms would move with it.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if drag?.id != document.tabID {
                    guard abs(value.translation.width) >= Self.dragThreshold,
                        let from = shownTabs.firstIndex(where: { $0 === document })
                    else { return }
                    workspace.select(document)
                    drag = TabDrag(
                        id: document.tabID, from: from,
                        widths: shownTabs.map { tabFrames[$0.tabID]?.width ?? Self.minTabWidth },
                        spacing: Self.spacing)
                }
                drag?.translation = value.translation.width
            }
            .onEnded { value in
                guard let drag, drag.id == document.tabID else {
                    // A click, when it is let go over the tab: pulled away
                    // first, it is no click, as with any button.
                    if drag != nil {
                        self.drag = nil
                    }
                    if tabFrames[document.tabID]?.contains(value.location) ?? true {
                        workspace.select(document)
                    }
                    return
                }
                guard !drag.isCancelled else {
                    self.drag = nil
                    return
                }
                // Nothing moves on screen here: the order changes under the
                // tabs, the others already stand in their new places, and
                // the dragged tab stays where it was let go, from where it
                // then slides into its own. Animated together, the new order
                // and the tabs' shifts ran on different clocks, and the tab
                // overshot its place.
                withTransaction(Self.still) {
                    if drag.target != drag.from {
                        workspace.moveTab(document, to: drag.target)
                    }
                    self.drag = nil
                    landing = Landing(id: drag.id, offset: drag.landing)
                }
            }
    }

    private struct Landing: Equatable {
        let id: ObjectIdentifier
        /// How far it stands from its place.
        var offset: CGFloat
        /// On its way: the slide into its place has begun.
        var isSliding = false
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
