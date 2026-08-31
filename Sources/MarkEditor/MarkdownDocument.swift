import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.markdown, .plainText] }
    static var writableContentTypes: [UTType] { [.markdown, .plainText] }

    var text: String

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
            return latin1
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let savedText = text
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .markdownDocumentDidSave,
                object: nil,
                userInfo: ["text": savedText]
            )
        }
        return FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

extension Notification.Name {
    /// Posted whenever a document's bytes are written (save or autosave), so
    /// the status bar can show a friendly "Salvo" state.
    static let markdownDocumentDidSave = Notification.Name("markdownDocumentDidSave")
}
