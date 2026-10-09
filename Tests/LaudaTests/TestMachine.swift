import Metal

/// What the machine running the tests can do.
enum TestMachine {
    /// Whether SwiftUI can draw here: it draws through Metal, and on a
    /// virtual machine without a real GPU (GitHub's Intel runners) loading
    /// a Metal library stops the whole test process with an assertion,
    /// "Target device architecture is nil". Tests that host SwiftUI views
    /// in a window are skipped there.
    static let drawsWithMetal: Bool = {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        if #available(macOS 14.0, *) {
            return !device.architecture.name.isEmpty && !device.name.contains("Paravirtual")
        }
        return !device.name.contains("Paravirtual")
    }()
}
