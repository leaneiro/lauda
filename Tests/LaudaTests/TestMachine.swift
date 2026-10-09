import Metal

/// What the machine running the tests can do.
enum TestMachine {
    /// Whether this machine draws through Metal. SwiftUI's Canvas does, and
    /// so does WebKit once a page counts as in view; on a virtual machine
    /// whose GPU has no architecture (GitHub's Intel runners) loading a
    /// Metal library stops the whole test process with an assertion,
    /// "Target device architecture is nil". Tests that need drawing are
    /// skipped there, and the page's visibility switch stays off.
    static let drawsWithMetal: Bool = {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("TestMachine: no Metal device")
            return false
        }
        let architecture = device.architecture.name
        print("TestMachine: Metal device \"\(device.name)\", architecture \"\(architecture)\"")
        return !architecture.isEmpty
    }()
}
