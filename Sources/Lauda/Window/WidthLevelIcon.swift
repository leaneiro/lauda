import SwiftUI

/// Toolbar glyph for the preview width level: a page outline whose inner
/// "text column" grows with the level, animating between states so the
/// cycle is visible at a glance.
struct WidthLevelIcon: View {
    let level: PreviewWidth

    private var columnWidth: CGFloat {
        switch level {
        case .normal: return 6
        case .medium: return 10
        case .wide: return 14
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3.5)
                .strokeBorder(.secondary, lineWidth: 1.2)
                .frame(width: 19, height: 14)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(.secondary)
                .frame(width: columnWidth, height: 8)
        }
        .frame(width: 22, height: 16)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: level)
        .contentShape(Rectangle())
    }
}
