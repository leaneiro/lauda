import SwiftUI

struct ExportCommands: Commands {
    @FocusedValue(\.exportActions) private var exportActions

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Export as PDF…") { exportActions?.exportPDF() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(exportActions == nil)
            Button("Export as HTML…") { exportActions?.exportHTML() }
                .keyboardShortcut("e", modifiers: [.command, .option, .shift])
                .disabled(exportActions == nil)
        }
    }
}

struct FindCommands: Commands {
    @FocusedValue(\.findActions) private var findActions

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find…") { findActions?.find() }
                .keyboardShortcut("f")
                .disabled(findActions == nil)
            Button("Find Next") { findActions?.findNext() }
                .keyboardShortcut("g")
                .disabled(findActions == nil)
            Button("Find Previous") { findActions?.findPrevious() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(findActions == nil)
            Button("Find and Replace…") { findActions?.replace() }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(findActions == nil)
        }
    }
}

struct FormatCommands: Commands {
    @FocusedValue(\.editorActions) private var editorActions

    var body: some Commands {
        CommandMenu("Format") {
            Button("Bold") { editorActions?.toggleBold() }
                .keyboardShortcut("b")
                .disabled(editorActions == nil)
            Button("Italic") { editorActions?.toggleItalic() }
                .keyboardShortcut("i")
                .disabled(editorActions == nil)
            Divider()
            Button("Add Link") { editorActions?.insertLink() }
                .keyboardShortcut("k")
                .disabled(editorActions == nil)
        }
    }
}

struct ViewModeCommands: Commands {
    @FocusedBinding(\.viewMode) private var viewMode: ViewMode?

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Editor Only") { viewMode = .editorOnly }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(viewMode == nil)
            Button("Editor and Preview") { viewMode = .split }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(viewMode == nil)
            Button("Preview Only") { viewMode = .previewOnly }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(viewMode == nil)
            Divider()
        }
    }
}

struct HelpCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Welcome Guide") { WelcomeGuide.open() }
        }
    }
}
