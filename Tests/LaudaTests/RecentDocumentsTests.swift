import Foundation
import Testing
@testable import Lauda

/// Own defaults suite and own folder per test, so order and parallelism
/// don't matter.
final class RecentDocumentsTests {
    private let defaults: UserDefaults = TestDefaults()
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try "x".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func mostRecentComesFirst() throws {
        RecentDocuments.note(try makeFile("a.md"), defaults: defaults)
        RecentDocuments.note(try makeFile("b.md"), defaults: defaults)
        #expect(RecentDocuments.storedURLs(defaults: defaults).map(\.lastPathComponent) == ["b.md", "a.md"])
    }

    @Test func reopeningMovesToFrontWithoutDuplicating() throws {
        let a = try makeFile("a.md")
        let b = try makeFile("b.md")
        RecentDocuments.note(a, defaults: defaults)
        RecentDocuments.note(b, defaults: defaults)
        RecentDocuments.note(a, defaults: defaults)
        #expect(RecentDocuments.storedURLs(defaults: defaults).map(\.lastPathComponent) == ["a.md", "b.md"])
    }

    @Test func listIsCappedAtTen() throws {
        for index in 1...12 {
            RecentDocuments.note(try makeFile("doc\(index).md"), defaults: defaults)
        }
        let names = RecentDocuments.storedURLs(defaults: defaults).map(\.lastPathComponent)
        #expect(names.count == 10)
        #expect(names.first == "doc12.md")
        #expect(!names.contains("doc1.md"))
        #expect(!names.contains("doc2.md"))
    }

    /// The File menu watches this number; a change that leaves it alone
    /// would leave Open Recent showing the old list.
    @Test func everyChangeMovesTheRevisionTheMenuWatches() throws {
        let start = defaults.integer(forKey: RecentDocuments.revisionKey)

        RecentDocuments.note(try makeFile("a.md"), defaults: defaults)
        let afterNote = defaults.integer(forKey: RecentDocuments.revisionKey)
        #expect(afterNote > start)

        RecentDocuments.clear(defaults: defaults)
        #expect(defaults.integer(forKey: RecentDocuments.revisionKey) > afterNote)
    }

    @Test func aFileThatIsGoneIsNotListedAndOneThatIsThereIs() throws {
        let kept = try makeFile("kept.md")
        let gone = try makeFile("gone.md")
        RecentDocuments.note(gone, defaults: defaults)
        RecentDocuments.note(kept, defaults: defaults)

        try FileManager.default.removeItem(at: gone)

        #expect(RecentDocuments.availableURLs(defaults: defaults).map(\.lastPathComponent) == ["kept.md"])
    }

    @Test func aFileThatFailedToOpenLeavesTheListWhenItIsGone() throws {
        let kept = try makeFile("kept.md")
        let gone = try makeFile("gone.md")
        RecentDocuments.note(gone, defaults: defaults)
        RecentDocuments.note(kept, defaults: defaults)
        try FileManager.default.removeItem(at: gone)
        let revision = defaults.integer(forKey: RecentDocuments.revisionKey)

        RecentDocuments.forgetIfDeleted(gone, defaults: defaults)

        #expect(RecentDocuments.storedURLs(defaults: defaults).map(\.lastPathComponent) == ["kept.md"])
        // The menu is built again without it.
        #expect(defaults.integer(forKey: RecentDocuments.revisionKey) > revision)
    }

    @Test func aFileThatIsThereStaysWhateverFailed() throws {
        let file = try makeFile("there.md")
        RecentDocuments.note(file, defaults: defaults)

        RecentDocuments.forgetIfDeleted(file, defaults: defaults)

        #expect(RecentDocuments.storedURLs(defaults: defaults).map(\.lastPathComponent) == ["there.md"])
    }

    /// A disk that is not connected takes the folder with it: the file is
    /// not listed meanwhile, and is not forgotten.
    @Test func aFileWhoseFolderIsGoneTooIsKeptForWhenItComesBack() throws {
        let folder = directory.appendingPathComponent("disk", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("away.md")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        RecentDocuments.note(file, defaults: defaults)
        let stored = defaults.array(forKey: "recentDocumentBookmarks")?.count

        try FileManager.default.removeItem(at: folder)
        RecentDocuments.forgetIfDeleted(file, defaults: defaults)

        #expect(RecentDocuments.availableURLs(defaults: defaults).isEmpty)
        #expect(defaults.array(forKey: "recentDocumentBookmarks")?.count == stored)
    }

    /// Coming to the front, the app has the menu built again, without the
    /// file deleted in the Finder meanwhile.
    @Test func refreshingMovesTheRevisionAndTheListLeavesOutWhatIsGone() throws {
        let gone = try makeFile("gone.md")
        RecentDocuments.note(gone, defaults: defaults)
        let revision = defaults.integer(forKey: RecentDocuments.revisionKey)
        try FileManager.default.removeItem(at: gone)

        RecentDocuments.refreshMenu(defaults: defaults)

        #expect(defaults.integer(forKey: RecentDocuments.revisionKey) > revision)
        #expect(RecentDocuments.availableURLs(defaults: defaults).isEmpty)
    }

    @Test func filesWithNamesOfTheirOwnShowOnlyTheName() {
        let urls = ["/a/notes/draft.md", "/a/notes/ideas.md"].map { URL(fileURLWithPath: $0) }
        #expect(RecentDocuments.menuTitles(for: urls) == ["draft.md", "ideas.md"])
    }

    @Test func filesThatShareANameShowTheFolderBeforeIt() {
        let urls = ["/a/notes/draft.md", "/a/book/draft.md", "/a/book/ideas.md"].map { URL(fileURLWithPath: $0) }
        #expect(RecentDocuments.menuTitles(for: urls) == ["…/notes/draft.md", "…/book/draft.md", "ideas.md"])
    }

    @Test func foldersThatShareANameTooShowOneMore() {
        let urls = ["/a/x/notes/draft.md", "/a/y/notes/draft.md"].map { URL(fileURLWithPath: $0) }
        #expect(RecentDocuments.menuTitles(for: urls) == ["…/x/notes/draft.md", "…/y/notes/draft.md"])
    }
}
