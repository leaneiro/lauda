import Foundation
import Testing
@testable import MarkEditor

/// Own defaults suite and own folder per test, so order and parallelism
/// don't matter.
final class RecentDocumentsTests {
    private let suiteName = "RecentDocumentsTests-\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let directory: URL

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
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
}
