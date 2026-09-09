import AppKit
import SwiftUI

/// UserDefaults-backed persistence for the "Open Recent" menu. macOS keys
/// the system list to the app's exact code signature, so every rebuilt
/// (re-signed) binary — including real app updates — starts with an empty
/// menu. We keep our own bookmark list, keyed by bundle id, and re-seed the
/// document controller at launch, which also repopulates the menu.
enum RecentDocuments {
    private static let key = "recentDocumentBookmarks"
    private static let limit = 10

    static func note(_ url: URL, defaults: UserDefaults = .standard) {
        // Bookmarks resolve to canonical paths (e.g. /private/var vs /var),
        // so dedupe must compare canonical forms.
        let canonical = canonicalPath(of: url)
        var urls = storedURLs(defaults: defaults).filter { canonicalPath(of: $0) != canonical }
        urls.insert(url, at: 0)
        let bookmarks = urls.prefix(limit).compactMap { try? $0.bookmarkData() }
        defaults.set(bookmarks, forKey: key)
        RecentDocumentsModel.shared.refresh(from: defaults)
    }

    private static func canonicalPath(of url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
        RecentDocumentsModel.shared.refresh(from: defaults)
    }

    static func storedURLs(defaults: UserDefaults = .standard) -> [URL] {
        let bookmarks = defaults.array(forKey: key) as? [Data] ?? []
        return bookmarks.compactMap { data in
            var isStale = false
            return try? URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        }
    }

    static func contains(_ url: URL, defaults: UserDefaults = .standard) -> Bool {
        let canonical = canonicalPath(of: url)
        return storedURLs(defaults: defaults).contains { canonicalPath(of: $0) == canonical }
    }

    /// Makes the system list mirror ours — oldest first, so the most recent
    /// ends on top. Our store is the single source of truth because AppKit
    /// re-adds documents on window close/quit even after "Limpar Menu".
    static func resyncSystemList(defaults: UserDefaults = .standard) {
        NSDocumentController.shared.clearRecentDocuments(nil)
        for url in storedURLs(defaults: defaults).reversed()
        where FileManager.default.fileExists(atPath: url.path) {
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        }
    }
}

/// Observable mirror of the persisted list, driving the SwiftUI menu.
final class RecentDocumentsModel: ObservableObject {
    static let shared = RecentDocumentsModel()
    @Published var urls: [URL] = RecentDocuments.storedURLs()

    func refresh(from defaults: UserDefaults = .standard) {
        let update = { self.urls = RecentDocuments.storedURLs(defaults: defaults) }
        if Thread.isMainThread { update() } else { DispatchQueue.main.async(execute: update) }
    }
}

/// Replaces the automatic Novo/Abrir/Abrir Recente block of the File menu
/// with SwiftUI-owned commands, so the recents submenu can come from our
/// store (the AppKit-managed one can't be customized, and swapping its
/// submenu from outside made SwiftUI drop the item on menu rebuilds).
struct FileCommands: Commands {
    @ObservedObject private var recents = RecentDocumentsModel.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Novo") {
                NSDocumentController.shared.newDocument(nil)
            }
            .keyboardShortcut("n")

            Button("Abrir…") {
                NSDocumentController.shared.openDocument(nil)
            }
            .keyboardShortcut("o")

            Menu("Abrir Recente") {
                let urls = recents.urls.filter { FileManager.default.fileExists(atPath: $0.path) }
                if urls.isEmpty {
                    Button("Nenhum documento recente") {}
                        .disabled(true)
                } else {
                    ForEach(urls, id: \.path) { url in
                        Button {
                            NSDocumentController.shared
                                .openDocument(withContentsOf: url, display: true) { _, _, _ in }
                        } label: {
                            Label {
                                Text(url.lastPathComponent)
                            } icon: {
                                Image(nsImage: Self.icon(for: url))
                            }
                        }
                    }
                    Divider()
                    Button("Limpar Menu") {
                        RecentDocuments.clear()
                        NSDocumentController.shared.clearRecentDocuments(nil)
                    }
                }
            }
        }
    }

    private static func icon(for url: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}
