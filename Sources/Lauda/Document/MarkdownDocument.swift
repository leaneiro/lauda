import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.markdown, .plainText] }
    static var writableContentTypes: [UTType] { [.markdown, .plainText] }

    var text: String

    /// Tells this document apart from others with the same text. SwiftUI
    /// copies the struct around; the copies keep it.
    let id = UUID()

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = try Self.decode(data)
    }

    /// Strict UTF-8 with Latin-1 fallback — never lossy, so a save can't
    /// silently corrupt a file that came in another encoding.
    static func decode(_ data: Data) throws -> String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let latin1 = String(data: data, encoding: .isoLatin1) {
            Log.documents.notice("Opened a file that isn't valid UTF-8 as Latin-1")
            return latin1
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let save = DocumentSave(documentID: id, text: text)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .markdownDocumentDidSave, object: save)
        }
        return FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// What a save wrote, so only that document's window updates its status.
struct DocumentSave {
    let documentID: UUID
    let text: String
}

extension Notification.Name {
    /// Posted whenever a document's bytes are written (save or autosave),
    /// with a `DocumentSave` as the object, so the status bar of that
    /// document's window can show a friendly "Saved" state.
    static let markdownDocumentDidSave = Notification.Name("markdownDocumentDidSave")
}
