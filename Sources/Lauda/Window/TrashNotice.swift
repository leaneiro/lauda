import AppKit
import SwiftUI

/// Over a document whose file is in the Trash: the text fades into the
/// background, as a tab not showing does, and a card in front says why it
/// takes no edits. It stays until the file is put back; the rest of the
/// window (the tabs, the menus, other documents) goes on as usual.
struct TrashNotice: View {
    let fileURL: URL?

    var body: some View {
        ZStack {
            // The panes' own paper, laid over them half see-through: the
            // text is still there, faded behind, and the clicks and the
            // scrolling stop here.
            Color(nsColor: .textBackgroundColor)
                .opacity(0.6)
                .contentShape(Rectangle())
            card
        }
    }

    private var card: some View {
        VStack(spacing: 6) {
            Image(systemName: "trash")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
            Text("This file is in the Trash")
                .font(.headline)
            Text("Put it back to keep editing.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let fileURL {
                Button("Show in Trash") {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
                .controlSize(.large)
                .padding(.top, 12)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 36)
        .padding(.vertical, 28)
        .modifier(NoticeCard())
        .accessibilityElement(children: .contain)
    }
}

/// Glass where the system has it, as the toolbar and the tabs; a material
/// card where it doesn't.
private struct NoticeCard: ViewModifier {
    private static let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: Self.shape)
        } else {
            content
                .background(.regularMaterial, in: Self.shape)
                .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
        }
    }
}
