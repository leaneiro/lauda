import AppKit

/// Exports one window's document, with the save panel as a sheet on that
/// window. Menu commands reach it through `ExportActions`.
struct WindowExporter {
    /// Read when an export starts, so it gets the text as it is right then.
    let markdown: () -> String
    let fileURL: URL?
    /// The window is only known once the view is on screen, so it's read
    /// when an export starts too.
    let window: WindowReference

    /// The name the save panel suggests: the document's, or "Untitled".
    var title: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? String(localized: "Untitled")
    }

    /// Where images with relative paths in the document are found.
    var baseDirectory: URL? {
        fileURL?.deletingLastPathComponent()
    }

    var actions: ExportActions {
        ExportActions(exportHTML: exportHTML, exportPDF: exportPDF)
    }

    func exportHTML() {
        DocumentExporter.promptAndExportHTML(
            markdown: markdown(),
            title: title,
            baseDirectory: baseDirectory,
            window: window.window
        )
    }

    func exportPDF() {
        DocumentExporter.promptAndExportPDF(
            markdown: markdown(),
            title: title,
            baseDirectory: baseDirectory,
            window: window.window
        )
    }
}
