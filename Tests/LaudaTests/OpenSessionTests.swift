import Foundation
import Testing
@testable import Lauda

@Suite struct OpenSessionTests {
    /// Defaults and a folder that belong to one test.
    private struct Sandbox {
        let defaults: UserDefaults
        let folder: URL
        private let suite: String

        init() throws {
            suite = "lauda-session-\(UUID().uuidString)"
            defaults = try #require(UserDefaults(suiteName: suite))
            folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        func file(_ name: String) throws -> URL {
            let url = folder.appendingPathComponent(name)
            try Data("# \(name)".utf8).write(to: url)
            return url
        }

        func cleanUp() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func names(_ urls: [URL]) -> [String] {
        urls.map(\.lastPathComponent)
    }

    @Test func theOpenFilesComeBackInTabOrder() throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        let files = [try sandbox.file("b.md"), try sandbox.file("a.md"), try sandbox.file("c.md")]

        OpenSession.store(.init(urls: files, selected: files[1]), defaults: sandbox.defaults)

        let session = OpenSession.stored(defaults: sandbox.defaults)
        #expect(names(session.urls) == ["b.md", "a.md", "c.md"])
        #expect(session.selected?.lastPathComponent == "a.md", "the tab that was in front comes back in front")
    }

    /// A file deleted between sessions must not come back as an error.
    @Test func aFileThatIsGoneIsLeftOut() throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        let kept = try sandbox.file("kept.md")
        let gone = try sandbox.file("gone.md")
        OpenSession.store(.init(urls: [kept, gone], selected: gone), defaults: sandbox.defaults)

        try FileManager.default.removeItem(at: gone)

        let session = OpenSession.stored(defaults: sandbox.defaults)
        #expect(names(session.urls) == ["kept.md"])
        #expect(session.selected == nil, "nor can a file that is gone be the front tab")
    }

    /// The front tab is remembered by position, which must still point at
    /// the right file once a missing one before it is left out.
    @Test func theFrontTabIsStillTheRightFileWhenOneBeforeItIsGone() throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        let gone = try sandbox.file("gone.md")
        let front = try sandbox.file("front.md")
        OpenSession.store(.init(urls: [gone, front], selected: front), defaults: sandbox.defaults)

        try FileManager.default.removeItem(at: gone)

        #expect(OpenSession.stored(defaults: sandbox.defaults).selected?.lastPathComponent == "front.md")
    }

    @Test func closingEverythingLeavesNothingToComeBackTo() throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        OpenSession.store(.init(urls: [try sandbox.file("a.md")]), defaults: sandbox.defaults)

        OpenSession.store(.init(), defaults: sandbox.defaults)

        #expect(OpenSession.stored(defaults: sandbox.defaults) == .init())
    }

    @Test func aFirstLaunchHasNoSession() throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }

        #expect(OpenSession.stored(defaults: sandbox.defaults) == .init())
    }
}
