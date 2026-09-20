import Foundation

extension URL {
    /// The one form of a file's URL: the path standardized and its symlinks
    /// resolved, in that order, so a "." or a ".." is gone before the links
    /// under it are followed. Two URLs for the same file then compare equal,
    /// which is what tells an open document from a second copy of it and
    /// keeps a recent file from being listed twice (/var and /private/var).
    var canonical: URL {
        standardizedFileURL.resolvingSymlinksInPath()
    }

    var canonicalPath: String {
        canonical.path
    }
}

/// Files remembered across launches, as bookmarks rather than paths, so a
/// file that moves is still found. Both the recent files and the documents
/// left open are stored this way.
enum Bookmarks {
    /// What to store for `url`, or nothing, with the failure logged as
    /// `remembering` describes it ("Remembering a recent document").
    static func data(for url: URL, remembering: String) -> Data? {
        do {
            return try url.bookmarkData()
        } catch {
            Log.documents.failure(remembering, error)
            return nil
        }
    }

    /// The file a bookmark points at. With `existingOnly`, a file that is no
    /// longer there resolves to nothing, which is how a session drops what
    /// has been deleted since.
    static func url(from data: Data, existingOnly: Bool = false, fileManager: FileManager = .default) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        guard !existingOnly || fileManager.fileExists(atPath: url.path) else { return nil }
        return url
    }
}
