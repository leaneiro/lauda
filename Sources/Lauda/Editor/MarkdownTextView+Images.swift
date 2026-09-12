import AppKit

// MARK: - Image insertion (drag & drop / paste)

extension MarkdownTextView.Coordinator {
    /// Imports image files into the document's folder and inserts the
    /// relative markdown at `index` (or the caret). Images that can't be
    /// copied are reported in an alert rather than dropped silently.
    func insertImageFiles(_ urls: [URL], at index: Int?) {
        guard let directory = documentDirectory() else { return }
        var paths: [String] = []
        var failure: Error?
        for url in urls {
            do {
                paths.append(try ImageImporter.importImage(from: url, into: directory))
            } catch {
                failure = failure ?? error
            }
        }
        if !paths.isEmpty {
            insertImageMarkdown(paths, at: index)
        }
        if let failure {
            showImageError(failure)
        }
    }

    /// Saves pasted raw image data (e.g. a screenshot) as PNG in the
    /// document's folder and inserts the markdown at the caret.
    func insertPastedImageData(_ data: Data) {
        guard let directory = documentDirectory() else { return }
        do {
            let name = try ImageImporter.saveImageData(data, in: directory)
            insertImageMarkdown([name], at: nil)
        } catch {
            showImageError(error)
        }
    }

    private func documentDirectory() -> URL? {
        if let fileURL = parent.fileURL {
            return fileURL.deletingLastPathComponent()
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Save the document first")
        alert.informativeText = String(localized: "Images are copied to the document's folder, so save the file before adding images.")
        present(alert)
        return nil
    }

    /// E.g. a read-only folder or a full disk; the system's message says which.
    private func showImageError(_ error: Error) {
        Log.images.failure("Adding an image", error)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Couldn't add the image to the document's folder")
        alert.informativeText = error.localizedDescription
        present(alert)
    }

    /// As a sheet on the editor's window, or app-modal when there is none.
    private func present(_ alert: NSAlert) {
        if let window = textView?.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func insertImageMarkdown(_ paths: [String], at index: Int?) {
        guard let textView else { return }
        let markdown = ImageImporter.markdown(forRelativePaths: paths)
        let range = index.map { NSRange(location: $0, length: 0) } ?? textView.selectedRange()
        replaceText(
            in: range,
            with: markdown,
            selecting: NSRange(location: range.location + (markdown as NSString).length, length: 0)
        )
    }
}
