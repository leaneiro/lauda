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
    /// The outline's headings, read when the popover opens rather than held
    /// here: the text changes on every keystroke, and a toolbar that reads it
    /// is rebuilt on every keystroke with it (WindowExporter reads its
    /// document the same way).
    let outlineItems: () -> [OutlineItem]
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
            outlineItem(placement: .primaryAction)
        } else {
            viewModeItem(placement: .principal)
            widthItem(placement: .automatic)
            outlineItem(placement: .automatic)
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
            .withoutItemBackground()
        } else {
            ToolbarItem(placement: placement) { widthButton }
        }
    }

    /// The strip spans the title bar but must not look like it: recent
    /// systems wrap every toolbar item in one glass capsule, and the tabs
    /// want a capsule each. Hiding the item's own background leaves theirs.
    private var tabsItem: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            WorkspaceTabStrip(workspace: workspace, width: tabStripWidth)
        }
        .withoutItemBackground()
    }

    /// The three view modes: a capsule of our own glass where the system has
    /// Liquid Glass (see GlassToolbarControls), the segmented control, which
    /// is what looks native, before it.
    @ToolbarContentBuilder
    private func viewModeItem(placement: ToolbarItemPlacement) -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: placement) {
                GlassViewModePicker(viewMode: $viewMode)
            }
            .withoutItemBackground()
        } else {
            ToolbarItem(placement: placement) { viewModePicker }
        }
    }

    @ToolbarContentBuilder
    private func outlineItem(placement: ToolbarItemPlacement) -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: placement) {
                GlassToolbarButton {
                    outlinePresented.toggle()
                } icon: {
                    Image(systemName: "list.bullet")
                        .font(ToolbarIcon.font)
                        .foregroundStyle(ToolbarIcon.ink)
                }
                .help("Document outline")
                .accessibilityLabel("Outline")
                .popover(isPresented: $outlinePresented, arrowEdge: .bottom) { outlinePopover }
            }
            .withoutItemBackground()
        } else {
            ToolbarItem(placement: placement) { outlineButton }
        }
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

    /// What the outline button shows, from either toolbar.
    private var outlinePopover: some View {
        OutlinePopover(items: outlineItems(), onSelect: onSelectHeading)
    }

    private var outlineButton: some View {
        Button {
            outlinePresented.toggle()
        } label: {
            Label("Outline", systemImage: "list.bullet")
        }
        .help("Document outline")
        .popover(isPresented: $outlinePresented, arrowEdge: .bottom) { outlinePopover }
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

    var body: some View {
        GlassToolbarButton(action: action) {
            WidthLevelIcon(level: level)
        }
        .modifier(Reveal(isShown: isShown, duration: ModeChange.duration))
        .accessibilityHidden(!isShown)
        .help("Text width: \(level.label). Next: \(level.next.label)")
        .accessibilityLabel("Text width: \(level.label)")
    }
}

extension ToolbarContent {
    /// Hides the glass the system draws around a toolbar item, where it
    /// draws one, so what is inside keeps its own shapes: the tabs are a
    /// capsule each, and our controls bring their own.
    @ToolbarContentBuilder
    func withoutItemBackground() -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
