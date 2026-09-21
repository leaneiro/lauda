import AppKit

/// File > Open. App-modal on purpose: a panel that isn't modal slips behind
/// the window at the first click and is then hard to find again.
enum DocumentOpenPanel {
    @MainActor
    static func run() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = MarkdownDocument.readableContentTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        open(panel.urls)
    }

    /// Opens the files one after another, so their tabs keep this order
    /// whatever each one takes to read.
    @MainActor
    static func open(_ urls: [URL], then completion: @escaping @MainActor () -> Void = {}) {
        guard let url = urls.first else {
            completion()
            return
        }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error {
                Log.documents.failure("Opening a document", error)
                NSApp.presentError(error)
            }
            open(Array(urls.dropFirst()), then: completion)
        }
    }
}
