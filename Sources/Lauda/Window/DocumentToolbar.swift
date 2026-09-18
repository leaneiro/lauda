import SwiftUI

/// The window's toolbar: the view mode picker, in preview-only mode the text
/// width button, and the outline, which is always the last one so it stays
/// put when the width button comes and goes. With two or more documents
/// open, the tabs take the title's place and the controls line up on the
/// right; a single document keeps the picker in the middle, as always.
struct DocumentToolbar: ToolbarContent {
    let workspace: Workspace
    @Binding var viewMode: ViewMode
    @Binding var outlinePresented: Bool
    /// The document's text; headings are only read when the outline opens.
    let text: String
    let previewWidth: PreviewWidth
    let onSelectHeading: (OutlineItem) -> Void
    let onCycleWidth: () -> Void
    /// Room the title bar has for the tabs, which the window works out.
    let tabStripWidth: CGFloat

    var body: some ToolbarContent {
        if workspace.showsTabs {
            tabsItem
            // primaryAction is the trailing edge on macOS. Left automatic,
            // these pile up right after the tabs once nothing sits in the
            // middle to push them across.
            viewModeItem(placement: .primaryAction)
            widthItem(placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) { outlineButton }
        } else {
            viewModeItem(placement: .principal)
            widthItem(placement: .automatic)
            ToolbarItem(placement: .automatic) { outlineButton }
        }
    }

    /// Whether the text width button keeps its place in the toolbar while it
    /// is out of sight. A toolbar puts an item in and takes it out at once,
    /// with nothing in between, so where the button can draw its own glass
    /// the item stays and the button comes and goes inside it.
    static var keepsWidthButtonPlace: Bool {
        if #available(macOS 26.0, *) { true } else { false }
    }

    @ToolbarContentBuilder
    private func widthItem(placement: ToolbarItemPlacement) -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: placement) {
                FadingWidthButton(isShown: viewMode == .previewOnly, level: previewWidth, action: onCycleWidth)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: placement) { widthButton }
        }
    }

    /// The strip spans the title bar but must not look like it: recent
    /// systems wrap every toolbar item in one glass capsule, and the tabs
    /// want a capsule each. Hiding the item's own background leaves theirs.
    @ToolbarContentBuilder
    private var tabsItem: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .navigation) {
                WorkspaceTabStrip(workspace: workspace, width: tabStripWidth)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) {
                WorkspaceTabStrip(workspace: workspace, width: tabStripWidth)
            }
        }
    }

    /// The three view modes. Where the system has Liquid Glass they are three
    /// toolbar buttons sharing one capsule, which light up and give under
    /// the pointer like the buttons beside them; a segmented control sits in
    /// the same capsule but stays flat. Earlier systems keep the segmented
    /// control, which is what looks native there.
    @ToolbarContentBuilder
    private func viewModeItem(placement: ToolbarItemPlacement) -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItemGroup(placement: placement) {
                viewModeButton(.editorOnly, "Editor Only", systemImage: "doc.plaintext")
                viewModeButton(.split, "Editor and Preview", systemImage: "rectangle.split.2x1")
                viewModeButton(.previewOnly, "Preview Only", systemImage: "doc.richtext")
            }
        } else {
            ToolbarItem(placement: placement) { viewModePicker }
        }
    }

    /// One mode's button, with a quiet pill behind the mode that is showing.
    /// A toggle would say the same, but the system fills one that is on with
    /// the accent colour and turns its icon white, which is loud up here; a
    /// grey tint only leaves that white icon unreadable.
    private func viewModeButton(_ mode: ViewMode, _ title: LocalizedStringKey, systemImage: String) -> some View {
        let isShowing = viewMode == mode
        return Button {
            viewMode = mode
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 30, height: 26)
                .background(Color.primary.opacity(isShowing ? 0.1 : 0), in: Capsule())
        }
        .help(title)
        .accessibilityAddTraits(isShowing ? .isSelected : [])
    }

    private var viewModePicker: some View {
        Picker("View Mode", selection: $viewMode) {
            Label("Editor Only", systemImage: "doc.plaintext")
                .tag(ViewMode.editorOnly)
            Label("Editor and Preview", systemImage: "rectangle.split.2x1")
                .tag(ViewMode.split)
            Label("Preview Only", systemImage: "doc.richtext")
                .tag(ViewMode.previewOnly)
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
    }

    private var outlineButton: some View {
        Button {
            outlinePresented.toggle()
        } label: {
            Label("Outline", systemImage: "list.bullet")
        }
        .help("Document outline")
        .popover(isPresented: $outlinePresented, arrowEdge: .bottom) {
            OutlinePopover(items: Outline.items(in: text), onSelect: onSelectHeading)
        }
    }

    @ViewBuilder
    private var widthButton: some View {
        if viewMode == .previewOnly {
            Button(action: onCycleWidth) {
                WidthLevelIcon(level: previewWidth)
            }
            .help("Text width: \(previewWidth.label). Next: \(previewWidth.next.label)")
            .accessibilityLabel("Text width: \(previewWidth.label)")
        }
    }
}

/// The text width button in a place of its own, fading in with preview-only
/// mode and out with it, in step with the panes. It draws the glass the
/// toolbar would have drawn, because that one can't fade.
@available(macOS 26.0, *)
private struct FadingWidthButton: View {
    let isShown: Bool
    let level: PreviewWidth
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A toolbar button's size.
    private static let side: CGFloat = 36

    var body: some View {
        Button(action: action) {
            WidthLevelIcon(level: level)
                .frame(width: Self.side, height: Self.side)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .opacity(isShown ? 1 : 0)
        .scaleEffect(isShown ? 1 : 0.8)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isShown)
        .allowsHitTesting(isShown)
        .accessibilityHidden(!isShown)
        .help("Text width: \(level.label). Next: \(level.next.label)")
        .accessibilityLabel("Text width: \(level.label)")
    }
}
