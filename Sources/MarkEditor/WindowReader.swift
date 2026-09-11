import SwiftUI

/// Holds, weakly, the window a SwiftUI view lives in, for AppKit calls that
/// need one (sheets). Filled in by `WindowReader`.
final class WindowReference {
    weak var window: NSWindow?
}

/// An invisible view that records its window in a `WindowReference`.
struct WindowReader: NSViewRepresentable {
    let reference: WindowReference

    func makeNSView(context: Context) -> ReaderView {
        ReaderView(reference: reference)
    }

    func updateNSView(_ view: ReaderView, context: Context) {}

    final class ReaderView: NSView {
        private let reference: WindowReference

        init(reference: WindowReference) {
            self.reference = reference
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reference.window = window
        }
    }
}
