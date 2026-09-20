import AppKit
import Testing
@testable import Lauda

/// A key the editor claims never reaches the menus: the text view answers it
/// first and says it is spoken for, so the menu item never runs, however well
/// its shortcut is declared. The Electron edition lost ⌘U that way, to the
/// editor's own undo of a selection.
@MainActor
@Suite(.serialized)
struct MenuShortcutTests {
    /// A shortcut as the menus declare it.
    private struct Shortcut {
        let key: String
        let modifiers: NSEvent.ModifierFlags
        let line: Int

        var description: String {
            var text = ""
            if modifiers.contains(.control) { text += "⌃" }
            if modifiers.contains(.option) { text += "⌥" }
            if modifiers.contains(.shift) { text += "⇧" }
            if modifiers.contains(.command) { text += "⌘" }
            return text + key.uppercased()
        }

        /// The event the system sends for it: the shifted character is what
        /// the key types, and the plain one is what a menu matches on.
        var event: NSEvent? {
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                characters: modifiers.contains(.shift) ? key.uppercased() : key,
                charactersIgnoringModifiers: key, isARepeat: false, keyCode: 0
            )
        }
    }

    /// Read from the source that declares them, so a shortcut added tomorrow
    /// is covered the day it is written.
    private static func declaredShortcuts() throws -> [Shortcut] {
        let commands = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Lauda/App/Commands.swift")
        let source = try String(contentsOf: commands, encoding: .utf8)
        let pattern = #"\.keyboardShortcut\("(.)"(?:, modifiers: ([^)]*))?\)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let text = source as NSString
        return regex.matches(in: source, range: NSRange(location: 0, length: text.length)).map { match in
            let key = text.substring(with: match.range(at: 1))
            let written = match.range(at: 2).location == NSNotFound ? "" : text.substring(with: match.range(at: 2))
            // Without modifiers SwiftUI means ⌘ alone.
            var modifiers: NSEvent.ModifierFlags = written.isEmpty ? [.command] : []
            if written.contains(".command") { modifiers.insert(.command) }
            if written.contains(".shift") { modifiers.insert(.shift) }
            if written.contains(".option") { modifiers.insert(.option) }
            if written.contains(".control") { modifiers.insert(.control) }
            let line = text.substring(to: match.range.location).components(separatedBy: "\n").count
            return Shortcut(key: key, modifiers: modifiers, line: line)
        }
    }

    /// The editor as the window holds it, focused, the way it is when the
    /// reader presses a shortcut while writing.
    private func makeEditor() -> (EditorTextView, NSWindow) {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 400, height: 300),
            styleMask: [.borderless], backing: .buffered, defer: false)
        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        textView.string = "one two three"
        window.contentView?.addSubview(textView)
        window.makeFirstResponder(textView)
        return (textView, window)
    }

    @Test func theEditorLeavesEveryMenuShortcutToTheMenus() throws {
        let shortcuts = try Self.declaredShortcuts()
        #expect(shortcuts.count >= 20, "read \(shortcuts.count) shortcuts from Commands.swift")
        let (_, window) = makeEditor()

        for shortcut in shortcuts {
            let event = try #require(shortcut.event)
            #expect(
                !window.performKeyEquivalent(with: event),
                "the editor claims \(shortcut.description) (Commands.swift:\(shortcut.line)), so its menu item never runs"
            )
        }
    }

    /// The ones the Format menu writes with, named here so the reading of
    /// Commands.swift can't quietly come back empty.
    @Test func theFormatMenuKeepsItsFour() throws {
        let shortcuts = try Self.declaredShortcuts()
        let described = Set(shortcuts.map(\.description))
        for expected in ["⌘B", "⌘I", "⌘U", "⇧⌘X", "⌘K"] {
            #expect(described.contains(expected), "\(expected) is gone from the menus: \(described.sorted())")
        }
    }
}
