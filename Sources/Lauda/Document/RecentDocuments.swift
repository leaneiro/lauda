import AppKit

/// UserDefaults-backed persistence for the "Open Recent" menu. macOS keys
/// the system list to the app's exact code signature, so every rebuilt
/// (re-signed) binary — including real app updates — starts with an empty
/// menu. We keep our own bookmark list, keyed by bundle id, and re-seed the
/// document controller at launch, which also repopulates the menu.
enum RecentDocuments {
    private static let key = "recentDocumentBookmarks"
    private static let limit = 10

    /// Bumped on every change. SwiftUI builds a menu once and only rebuilds
    /// it for state it can see, so the File menu watches this number to keep
    /// Open Recent current.
    static let revisionKey = "recentDocumentsRevision"

    private static func bumpRevision(_ defaults: UserDefaults) {
        defaults.set(defaults.integer(forKey: revisionKey) + 1, forKey: revisionKey)
    }

    static func note(_ url: URL, defaults: UserDefaults = .standard) {
        // Bookmarks resolve to canonical paths (e.g. /private/var vs /var),
        // so dedupe must compare canonical forms.
        let canonical = url.canonicalPath
        var urls = storedURLs(defaults: defaults).filter { $0.canonicalPath != canonical }
        urls.insert(url, at: 0)
        let bookmarks = urls.prefix(limit).compactMap { Bookmarks.data(for: $0, remembering: "Remembering a recent document") }
        defaults.set(bookmarks, forKey: key)
        bumpRevision(defaults)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
        bumpRevision(defaults)
    }

    static func storedURLs(defaults: UserDefaults = .standard) -> [URL] {
        let bookmarks = defaults.array(forKey: key) as? [Data] ?? []
        return bookmarks.compactMap { Bookmarks.url(from: $0) }
    }

    /// Has the File menu build Open Recent again. A file deleted in the
    /// Finder changes nothing here, so the menu built before went on
    /// showing it; the app coming to the front is when that may have
    /// happened.
    static func refreshMenu(defaults: UserDefaults = .standard) {
        bumpRevision(defaults)
    }

    /// What Open Recent lists: the files that are there now. One on a disk
    /// that is not connected stays in the store and comes back with it.
    static func availableURLs(defaults: UserDefaults = .standard, fileManager: FileManager = .default) -> [URL] {
        storedURLs(defaults: defaults).filter { fileManager.fileExists(atPath: $0.path) }
    }

    /// A file that failed to open because it is gone for good (its folder
    /// is there and the file is not) is not offered again. Its bookmark
    /// goes if it still resolves, and the menu, built once and kept until
    /// the revision moves, is built again: a bookmark that stopped
    /// resolving (measured: a deleted file's does) was already off the
    /// list, and only an old menu still showed it. With the folder gone
    /// too (a disk not connected) nothing changes. The other bookmarks are
    /// kept as they are, not made again.
    static func forgetIfDeleted(_ url: URL, defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        guard !fileManager.fileExists(atPath: url.path),
            fileManager.fileExists(atPath: url.deletingLastPathComponent().path)
        else { return }
        let canonical = url.canonicalPath
        let bookmarks = defaults.array(forKey: key) as? [Data] ?? []
        let kept = bookmarks.filter { Bookmarks.url(from: $0)?.canonicalPath != canonical }
        if kept.count != bookmarks.count {
            defaults.set(kept, forKey: key)
        }
        bumpRevision(defaults)
    }

    static func contains(_ url: URL, defaults: UserDefaults = .standard) -> Bool {
        let canonical = url.canonicalPath
        return storedURLs(defaults: defaults).contains { $0.canonicalPath == canonical }
    }

    /// Makes the system list mirror ours — oldest first, so the most recent
    /// ends on top. Our store is the single source of truth because AppKit
    /// re-adds documents on window close/quit even after "Clear Menu".
    static func resyncSystemList(defaults: UserDefaults = .standard) {
        NSDocumentController.shared.clearRecentDocuments(nil)
        for url in storedURLs(defaults: defaults).reversed()
        where FileManager.default.fileExists(atPath: url.path) {
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        }
    }
}
