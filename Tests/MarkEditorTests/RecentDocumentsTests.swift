import XCTest
@testable import MarkEditor

final class RecentDocumentsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var directory: URL!

    override func setUpWithError() throws {
        defaults = UserDefaults(suiteName: "RecentDocumentsTests")!
        defaults.removePersistentDomain(forName: "RecentDocumentsTests")
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: "RecentDocumentsTests")
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try "x".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testMostRecentComesFirst() throws {
        let a = try makeFile("a.md")
        let b = try makeFile("b.md")
        RecentDocuments.note(a, defaults: defaults)
        RecentDocuments.note(b, defaults: defaults)
        XCTAssertEqual(RecentDocuments.storedURLs(defaults: defaults).map(\.lastPathComponent), ["b.md", "a.md"])
    }

    func testReopeningMovesToFrontWithoutDuplicating() throws {
        let a = try makeFile("a.md")
        let b = try makeFile("b.md")
        RecentDocuments.note(a, defaults: defaults)
        RecentDocuments.note(b, defaults: defaults)
        RecentDocuments.note(a, defaults: defaults)
        XCTAssertEqual(RecentDocuments.storedURLs(defaults: defaults).map(\.lastPathComponent), ["a.md", "b.md"])
    }

    func testListIsCappedAtTen() throws {
        for index in 1...12 {
            RecentDocuments.note(try makeFile("doc\(index).md"), defaults: defaults)
        }
        let names = RecentDocuments.storedURLs(defaults: defaults).map(\.lastPathComponent)
        XCTAssertEqual(names.count, 10)
        XCTAssertEqual(names.first, "doc12.md")
        XCTAssertFalse(names.contains("doc1.md"))
        XCTAssertFalse(names.contains("doc2.md"))
    }
}
