import Foundation
import os

/// System log for the rare failures worth diagnosing; they show in Console
/// under the subsystem dev.leandro.markeditor. Messages leave out document
/// text and file names, since people may attach these logs to public bug
/// reports.
enum Log {
    private static let subsystem = "dev.leandro.markeditor"

    static let preview = Logger(subsystem: subsystem, category: "preview")
    static let export = Logger(subsystem: subsystem, category: "export")
    static let images = Logger(subsystem: subsystem, category: "images")
    static let documents = Logger(subsystem: subsystem, category: "documents")
}

extension Logger {
    /// A failed operation: the error's domain and code are public; its
    /// description, which can name a file, stays private.
    func failure(_ operation: String, _ error: Error) {
        let nsError = error as NSError
        self.error("""
        \(operation, privacy: .public) failed: \(nsError.domain, privacy: .public) \
        \(nsError.code, privacy: .public) \(nsError.localizedDescription, privacy: .private)
        """)
    }
}
