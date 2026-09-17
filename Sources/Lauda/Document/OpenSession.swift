import Foundation

/// The files that were open, and which tab was in front, so the next launch
/// brings them back. SwiftUI's document scenes did this through window
/// restoration; with one window of our own it is a list of bookmarks, kept
/// the way the recent documents are.
enum OpenSession {
    struct Contents: Equatable {
        /// In tab order.
        var urls: [URL] = []
        var selected: URL?
    }

    private static let key = "openSessionBookmarks"
    private static let selectedKey = "openSessionSelected"

    static func store(_ contents: Contents, defaults: UserDefaults = .standard) {
        let bookmarks = contents.urls.compactMap { url -> Data? in
            do {
                return try url.bookmarkData()
            } catch {
                Log.documents.failure("Remembering an open document", error)
                return nil
            }
        }
        defaults.set(bookmarks, forKey: key)
        if let selected = contents.selected, let index = contents.urls.firstIndex(of: selected) {
            defaults.set(index, forKey: selectedKey)
        } else {
            defaults.removeObject(forKey: selectedKey)
        }
    }

    /// The last session, without the files that no longer exist.
    static func stored(defaults: UserDefaults = .standard, fileManager: FileManager = .default) -> Contents {
        let bookmarks = defaults.array(forKey: key) as? [Data] ?? []
        let urls = bookmarks.map { data -> URL? in
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { return nil }
            return fileManager.fileExists(atPath: url.path) ? url : nil
        }
        var contents = Contents(urls: urls.compactMap { $0 })
        if let index = defaults.object(forKey: selectedKey) as? Int, urls.indices.contains(index) {
            contents.selected = urls[index]
        }
        return contents
    }
}
