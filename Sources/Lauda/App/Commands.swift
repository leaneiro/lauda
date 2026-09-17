import SwiftUI

// Every command acts on the document showing in the workspace window. There
// is one window and one place to ask, so the commands ask it directly rather
// than through focused values, which only SwiftUI's own scenes can publish.

/// The File menu a document scene used to bring: New, Open, Open Recent,
/// Close, Save and what macOS offers for a document's file.
struct FileCommands: Commands {
    private var workspace: Workspace { .shared }

    /// A menu is built once, and only state SwiftUI can see brings it back;
    /// an observable object doesn't count here, stored defaults do.
    @AppStorage(RecentDocuments.revisionKey) private var recentsRevision = 0

    private var recents: [URL] {
        _ = recentsRevision
        return RecentDocuments.storedURLs()
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") { NSDocumentController.shared.newDocument(nil) }
                .keyboardShortcut("n")
            Button("Open…") { DocumentOpenPanel.run() }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(recents, id: \.self) { url in
                    Button(url.lastPathComponent) { DocumentOpenPanel.open([url]) }
                }
                if !recents.isEmpty {
                    Divider()
                }
                Button("Clear Menu") { workspace.clearRecents() }
            }
        }
        CommandGroup(replacing: .saveItem) {
            Button("Close") { workspace.closeSelected() }
                .keyboardShortcut("w")
            Divider()
            Button("Save") { workspace.selected?.save(nil) }
                .keyboardShortcut("s")
            Button("Duplicate") { workspace.selected?.duplicate(nil) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Rename…") { workspace.selected?.rename(nil) }
            Button("Move To…") { workspace.selected?.move(nil) }
            Divider()
            Button("Revert to Saved") { workspace.selected?.revertToSaved(nil) }
            Button("Browse All Versions…") { workspace.selected?.browseVersions(nil) }
        }
    }
}

/// Moving between the open documents, where macOS keeps its own tab commands.
struct TabCommands: Commands {
    private var workspace: Workspace { .shared }

    var body: some Commands {
        CommandGroup(before: .windowList) {
            Button("Show Next Tab") { workspace.selectNext() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Show Previous Tab") { workspace.selectPrevious() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Divider()
        }
    }
}

struct ExportCommands: Commands {
    private var workspace: Workspace { .shared }

    private var export: ExportActions? {
        guard let document = workspace.selected else { return nil }
        return WindowExporter(
            markdown: { document.text },
            fileURL: document.fileURL,
            window: workspace.windowReference
        ).actions
    }

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Export as PDF…") { export?.exportPDF() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Export as HTML…") { export?.exportHTML() }
                .keyboardShortcut("e", modifiers: [.command, .option, .shift])
        }
    }
}

struct FindCommands: Commands {
    private var workspace: Workspace { .shared }

    private var session: FindSession? { workspace.selected?.findSession }

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find…") { session?.open(in: workspace.viewMode) }
                .keyboardShortcut("f")
            Button("Find Next") { session?.step(forward: true, in: workspace.viewMode) }
                .keyboardShortcut("g")
            Button("Find Previous") { session?.step(forward: false, in: workspace.viewMode) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button("Find and Replace…") { session?.replace(in: workspace.viewMode) }
                .keyboardShortcut("f", modifiers: [.command, .option])
        }
    }
}

struct FormatCommands: Commands {
    private var workspace: Workspace { .shared }

    private var editor: EditorActions? { workspace.selected?.editorActions }

    var body: some Commands {
        CommandMenu("Format") {
            Button("Bold") { editor?.toggleBold() }
                .keyboardShortcut("b")
            Button("Italic") { editor?.toggleItalic() }
                .keyboardShortcut("i")
            Divider()
            Button("Add Link") { editor?.insertLink() }
                .keyboardShortcut("k")
        }
    }
}

struct ViewModeCommands: Commands {
    private var workspace: Workspace { .shared }

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Editor Only") { workspace.viewMode = .editorOnly }
                .keyboardShortcut("1", modifiers: .command)
            Button("Editor and Preview") { workspace.viewMode = .split }
                .keyboardShortcut("2", modifiers: .command)
            Button("Preview Only") { workspace.viewMode = .previewOnly }
                .keyboardShortcut("3", modifiers: .command)
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
