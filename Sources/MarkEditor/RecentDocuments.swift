import AppKit

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
    }

    private static func canonicalPath(of url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
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

/// Owns the "Abrir Recente" submenu, building it from our store: AppKit's
/// built-in one can't be customized (it shows a lone "Limpar Menu" even when
/// empty). Re-attaches whenever the menu bar starts tracking, because SwiftUI
/// may rebuild the main menu at any time.
final class RecentMenuController: NSObject, NSMenuDelegate {
    static let shared = RecentMenuController()
    private let menu = NSMenu()

    func install() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(menuDidBeginTracking(_:)),
            name: NSMenu.didBeginTrackingNotification, object: nil)
        attach()
    }

    @objc private func menuDidBeginTracking(_ notification: Notification) {
        guard (notification.object as? NSMenu) === NSApp.mainMenu else { return }
        attach()
    }

    private func attach() {
        guard let recentItem = NSApp.mainMenu?.items
            .compactMap(\.submenu)
            .flatMap(\.items)
            .first(where: { $0.title.contains("Recente") || $0.title.contains("Recent") })
        else { return }
        if recentItem.submenu !== menu {
            menu.title = recentItem.title
            menu.delegate = self
            recentItem.submenu = menu
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = RecentDocuments.storedURLs()
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        guard !urls.isEmpty else {
            menu.addItem(NSMenuItem(title: "Nenhum documento recente", action: nil, keyEquivalent: ""))
            return
        }
        for url in urls {
            let item = NSMenuItem(
                title: url.lastPathComponent,
                action: #selector(openRecent(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = url
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Limpar Menu", action: #selector(clearMenu(_:)), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    @objc private func clearMenu(_ sender: Any?) {
        RecentDocuments.clear()
        NSDocumentController.shared.clearRecentDocuments(nil)
    }

}
