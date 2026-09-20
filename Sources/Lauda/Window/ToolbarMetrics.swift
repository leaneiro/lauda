import CoreGraphics

/// The figures the title bar is laid out by, measured on the real toolbar:
/// 96 points before the first item, which is the window's own buttons and
/// the room after them, 8 between items and at the trailing edge, and 36 to
/// a side for a round button. They are kept here because two sides need
/// them: the controls, which draw at these sizes, and the tab strip, which
/// asks for the width that is left once they have their room.
enum ToolbarMetrics {
    static let leading: CGFloat = 96
    static let gap: CGFloat = 8
    static let buttonSide: CGFloat = 36
}
