import AppKit
import SwiftUI
import WebKit
@testable import Lauda

/// The interface audit (Scripts/ui-audit.sh): the real workspace window,
/// with documents made up for it, walked through its screens and captured
/// as the window server draws it. The end-to-end tests stand on the same
/// stage, without the captures. Nothing of it shows: the window lives far
/// off every screen, takes no mouse and no keyboard from whoever is at the
/// Mac, and the files are in a temporary folder.
enum UIAudit {
    private static let environment = ProcessInfo.processInfo.environment

    /// Where the captures go. The audit only runs when this is set, so an
    /// ordinary `swift test` passes it by.
    static let outputFolder: URL? = environment["UI_AUDIT_OUT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    static var isRequested: Bool { outputFolder != nil }

    static let appearances: [(name: String, appearance: NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
    static let sizes: [NSSize] = [NSSize(width: 1440, height: 900), NSSize(width: 1100, height: 800)]

    static let offscreen = NSPoint(x: -20_000, y: -20_000)

    /// AppKit brings a titled window back onto a screen when it is shown,
    /// and the workspace places its window from a saved frame or centres
    /// it. For the process running the tests, from the first stage on and
    /// for every window after it, both leave a window where it is put, so
    /// the stage's never shows on the screen, not even for a frame.
    /// The app's code is untouched, which also lets the same audit run on an
    /// older commit to make the baseline.
    @MainActor static func keepWindowsOffscreen() {
        guard !windowsAreKeptOffscreen else { return }
        windowsAreKeptOffscreen = true
        if let constrain = class_getInstanceMethod(NSWindow.self, NSSelectorFromString("constrainFrameRect:toScreen:")) {
            let asGiven: @convention(block) (NSWindow, NSRect, NSScreen?) -> NSRect = { _, frame, _ in frame }
            method_setImplementation(constrain, imp_implementationWithBlock(asGiven))
        }
        if let named = class_getInstanceMethod(NSWindow.self, NSSelectorFromString("setFrameUsingName:")) {
            let offscreen: @convention(block) (NSWindow, NSString) -> Bool = { window, _ in
                window.setFrameOrigin(UIAudit.offscreen)
                return true
            }
            method_setImplementation(named, imp_implementationWithBlock(offscreen))
        }
    }
    @MainActor private static var windowsAreKeptOffscreen = false
}

/// One run of the screens: a workspace of its own, in one appearance and
/// one window size, with its files in a folder that goes when it ends.
@MainActor
final class AuditStage {
    let workspace: Workspace
    let folder: URL
    private let output: URL
    private var notes: [String] = []

    /// `appearance` is the whole process's while the stage stands, so only
    /// the audit, which runs alone, asks for one.
    init(named name: String, appearance: NSAppearance.Name? = nil, into output: URL) throws {
        _ = NSApplication.shared
        UIAudit.keepWindowsOffscreen()
        if let appearance {
            NSApp.appearance = NSAppearance(named: appearance)
        }
        workspace = Workspace(defaults: TestDefaults(), showsWindow: true)
        MarkdownDocument.host = workspace
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lauda-ui-audit-\(UUID().uuidString)")
        self.output = output.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: self.output, withIntermediateDirectories: true)
    }

    var window: NSWindow? { workspace.window }

    func open(_ name: String, text: String) throws -> MarkdownDocument {
        let url = folder.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        let document = try MarkdownDocument(contentsOf: url, ofType: "net.daringfireball.markdown")
        show(document)
        return document
    }

    func openUntitled() -> MarkdownDocument {
        let document = MarkdownDocument()
        show(document)
        return document
    }

    private func show(_ document: MarkdownDocument) {
        // In the controller's list, as an open document is: that is what
        // makes it a presenter of its file, which hears of a move.
        NSDocumentController.shared.addDocument(document)
        workspace.add(document)
        // The frame is the audit's to decide, and nothing of it is kept in
        // the preferences of the process running the tests.
        window?.setFrameAutosaveName("")
    }

    func resize(to size: NSSize) {
        window?.setContentSize(size)
        window?.setFrameOrigin(UIAudit.offscreen)
    }

    /// Something worth reading beside the next capture, such as a step that
    /// did not happen.
    func note(_ line: String) {
        notes.append(line)
    }

    /// Waits for `condition`, for as long as something that depends on the
    /// system (a file presenter hearing of a move) may take.
    func wait(upTo seconds: Double = 5, for condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    // MARK: - Capturing

    /// The picture of the window once it has stopped changing, and beside
    /// it the layout in words: where each toolbar control is, what the
    /// title bar shows, who has the keyboard.
    func capture(_ name: String) async {
        guard let window else {
            note("no window to capture")
            write(layoutNotes(), as: name)
            return
        }
        keepPagesDrawing(in: window)
        layOutEveryEditorInFull(in: window)
        // Past a change of layout and of the tabs, which take 0.2 s each
        // and can follow one another.
        try? await Task.sleep(for: .milliseconds(700))
        _ = await wait(upTo: 5) { !self.pages(in: window).contains(where: \.isLoading) }

        // Settled is the same picture several times running, for longer than
        // an overlay scroller stays up after it flashes: caught while one
        // fades, two runs of the same screen would differ.
        var last = picture(of: window)
        var sameInARow = 0
        for _ in 0..<Self.settlingTries where sameInARow < Self.sameToSettle {
            try? await Task.sleep(for: .milliseconds(300))
            let next = picture(of: window)
            if let last, let next, Self.bytes(of: last) == Self.bytes(of: next) {
                sameInARow += 1
            } else {
                sameInARow = 0
            }
            last = next
        }
        let settled = sameInARow >= Self.sameToSettle
        if !settled {
            note("the picture never stopped changing")
        }
        if let last {
            Self.write(last, to: output.appendingPathComponent(name + ".png"))
        } else {
            note("the window server gave no picture (a locked screen gives none)")
        }
        write(layoutNotes(), as: name)
    }

    private static let sameToSettle = 3
    private static let settlingTries = 30

    private func write(_ text: String, as name: String) {
        try? Data(text.utf8).write(to: output.appendingPathComponent(name + ".txt"))
        notes = []
    }

    /// The window as the window server composes it, glass and web content
    /// included; what the views can draw of themselves leaves both out. The
    /// function left the SDK but not the system, and a process may always
    /// capture its own windows.
    private func picture(of window: NSWindow) -> CGImage? {
        typealias WindowCapture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let capture = unsafeBitCast(symbol, to: WindowCapture.self)
        let onlyThisWindow: UInt32 = 1 << 3
        let withoutShadowAtNominalBounds: UInt32 = (1 << 0) | (1 << 3)
        return capture(.null, onlyThisWindow, UInt32(window.windowNumber), withoutShadowAtNominalBounds)?
            .takeRetainedValue()
    }

    private static func bytes(of image: CGImage) -> Data? {
        image.dataProvider?.data as Data?
    }

    private static func write(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    private func pages(in window: NSWindow) -> [WKWebView] {
        Self.views(under: window.contentView, as: WKWebView.self)
    }

    /// Off screen WebKit takes a page for hidden and soon stops drawing it.
    private func keepPagesDrawing(in window: NSWindow) {
        for page in pages(in: window) {
            page.keepRunningOffscreen()
        }
    }

    /// The editor lays its text out as it goes, and until it is done the
    /// scroller's knob is a guess that differs from run to run.
    private func layOutEveryEditorInFull(in window: NSWindow) {
        for editor in Self.views(under: window.contentView, as: NSTextView.self) {
            if let container = editor.textContainer {
                editor.layoutManager?.ensureLayout(for: container)
            }
        }
    }

    private static func views<Kind: NSView>(under view: NSView?, as kind: Kind.Type) -> [Kind] {
        guard let view else { return [] }
        return ((view as? Kind).map { [$0] } ?? []) + view.subviews.flatMap { views(under: $0, as: kind) }
    }

    // MARK: - The layout in words

    private func layoutNotes() -> String {
        var lines = notes.map { "note: \($0)" }
        guard let window else { return lines.joined(separator: "\n") + "\n" }
        let content = window.contentLayoutRect.size
        lines.append("window: frame \(Int(window.frame.width))x\(Int(window.frame.height)), below the bar \(Int(content.width))x\(Int(content.height))")
        lines.append("title: \"\(window.title)\" \(window.titleVisibility == .visible ? "visible" : "hidden")")
        lines.append("tabs: \(workspace.documents.count) document(s), selected \(workspace.selectedIndex.map(String.init) ?? "none")")
        lines.append("keyboard: \(window.firstResponder.map { String(describing: type(of: $0)) } ?? "nobody")")
        for (index, item) in (window.toolbar?.items ?? []).enumerated() {
            guard let view = item.view else {
                lines.append("toolbar \(index): no view")
                continue
            }
            lines.append("toolbar \(index): \(Self.rounded(view.convert(view.bounds, to: nil)))\(view.isHiddenOrHasHiddenAncestor ? " hidden" : "")")
        }
        for editor in Self.views(under: window.contentView, as: NSTextView.self) where !editor.isHiddenOrHasHiddenAncestor {
            lines.append(
                "editor: \(Self.rounded(editor.enclosingScrollView.map { $0.convert($0.bounds, to: nil) } ?? .zero))"
                    + " editable \(editor.isEditable) selectable \(editor.isSelectable)")
        }
        for page in pages(in: window) where !page.isHiddenOrHasHiddenAncestor {
            lines.append("preview: \(Self.rounded(page.convert(page.bounds, to: nil)))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func rounded(_ rect: NSRect) -> String {
        "x \(Int(rect.minX.rounded())) y \(Int(rect.minY.rounded())) w \(Int(rect.width.rounded())) h \(Int(rect.height.rounded()))"
    }

    // MARK: - Leaving

    /// Every document closes without a question (none was edited), the
    /// window goes with the last one, and the files go too.
    func close() async {
        for document in workspace.documents {
            document.close()
        }
        try? await Task.sleep(for: .seconds(Workspace.tabAnimation + 0.3))
        MarkdownDocument.host = nil
        NSApp.appearance = nil
        try? FileManager.default.removeItem(at: folder)
    }
}
