import SwiftUI
import Markdown

/// A heading in the document outline.
struct OutlineItem: Identifiable, Equatable {
    let id: Int
    let level: Int
    let title: String
    /// 0-based source line, the same numbering scroll sync uses.
    let line: Int
}

enum Outline {
    static func items(in markdown: String) -> [OutlineItem] {
        var collector = HeadingCollector()
        collector.visit(Document(parsing: markdown))
        return collector.items
    }

    private struct HeadingCollector: MarkupWalker {
        var items: [OutlineItem] = []

        mutating func visitHeading(_ heading: Heading) {
            let title = heading.plainText.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty, let range = heading.range else { return }
            items.append(OutlineItem(
                id: items.count,
                level: heading.level,
                title: title,
                line: range.lowerBound.line - 1
            ))
        }
    }
}

/// Toolbar popover listing the headings; picking one scrolls both panes to it.
struct OutlinePopover: View {
    let items: [OutlineItem]
    var onSelect: (OutlineItem) -> Void

    private static let rowHeight: CGFloat = 26
    private static let maxHeight: CGFloat = 420

    var body: some View {
        if items.isEmpty {
            Text("Nenhum título no documento")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        } else {
            let minLevel = items.map(\.level).min() ?? 1
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        OutlineRow(item: item, indent: item.level - minLevel) {
                            onSelect(item)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(width: 300)
            .frame(height: min(CGFloat(items.count) * Self.rowHeight + 12, Self.maxHeight))
        }
    }
}

private struct OutlineRow: View {
    let item: OutlineItem
    let indent: Int
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(item.title)
                .font(item.level == 1 ? Font.body.weight(.semibold) : Font.body)
                .foregroundStyle(textStyle)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, CGFloat(indent) * 14)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hovering ? Color(nsColor: .controlAccentColor) : Color.clear)
                )
                .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(item.title)
    }

    /// Hover mirrors a native menu highlight: accent fill, menu-selection text.
    private var textStyle: AnyShapeStyle {
        if hovering {
            return AnyShapeStyle(Color(nsColor: .selectedMenuItemTextColor))
        }
        return AnyShapeStyle(.primary)
    }
}
