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
            ToolbarItem(placement: .primaryAction) { viewModePicker }
            widthItem(placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) { outlineButton }
        } else {
            ToolbarItem(placement: .principal) { viewModePicker }
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
