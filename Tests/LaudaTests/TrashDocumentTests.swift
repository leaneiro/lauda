import AppKit
import Testing
@testable import Lauda

extension OpenDocumentsSuites {
@MainActor
@Suite(.serialized)
final class TrashDocumentTests {
    private let markdownType = "net.daringfireball.markdown"
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lauda-trash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Desk"), withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    private var trash: URL { root.appendingPathComponent(".Trash") }

    private func open(_ name: String, text: String = "draft") throws -> MarkdownDocument {
        let url = root.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        let document = try MarkdownDocument(contentsOf: url, ofType: markdownType)
        NSDocumentController.shared.addDocument(document)
        return document
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    private func move(_ from: URL, to directory: URL) throws -> URL {
        let target = directory.appendingPathComponent(from.lastPathComponent)
        try coordinatedMove(from, to: target)
        return target
    }

    /// The Finder moves files under a file coordinator, which is what tells a
    /// file presenter about it; a bare `moveItem` does not.
    private func coordinatedMove(_ from: URL, to target: URL) throws {
        var coordinationError: NSError?
        var moveError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(
            writingItemAt: from, options: .forMoving,
            writingItemAt: target, options: .forReplacing, error: &coordinationError
        ) { source, destination in
            do {
                try FileManager.default.moveItem(at: source, to: destination)
                coordinator.item(at: source, didMoveTo: destination)
            } catch { moveError = error }
        }
        if let error = coordinationError ?? moveError { throw error }
    }

    @Test("TRASH-01.4 a document whose file is in the Trash refuses typing") func aDocumentWhoseFileIsInTheTrashRefusesTyping() async throws {
        let document = try open("notes.md")
        let url = try #require(document.fileURL)
        let inTrash = try move(url, to: trash)
        #expect(await waitUntil { document.isInTrash })

        document.edit("x")

        #expect(document.text == "draft")
        #expect(try String(contentsOf: inTrash, encoding: .utf8) == "draft")
        document.close()
    }

    @Test("TRASH-01.5 other documents stay editable and the trashed one closes") func otherDocumentsStayEditableAndTheTrashedOneCloses() async throws {
        let notes = try open("notes.md")
        let other = try open("other.md")
        let third = try open("third.md")
        let url = try #require(notes.fileURL)
        _ = try move(url, to: trash)
        #expect(await waitUntil { notes.isInTrash })

        other.edit("x")
        third.edit("y")

        #expect(other.text == "x")
        #expect(third.text == "y")
        #expect(other.isInTrash == false)
        notes.close()
        other.close()
        third.close()
    }

    @Test("TRASH-01.6 a returned file is reread and accepts typing again") func aReturnedFileIsRereadAndAcceptsTypingAgain() async throws {
        let document = try open("notes.md")
        let url = try #require(document.fileURL)
        let inTrash = try move(url, to: trash)
        #expect(await waitUntil { document.isInTrash })
        try "final".write(to: inTrash, atomically: false, encoding: .utf8)

        _ = try move(inTrash, to: root)
        #expect(await waitUntil { !document.isInTrash })

        #expect(await waitUntil { document.text == "final" })
        document.edit("final x")
        #expect(document.text == "final x")
        document.close()
    }

    @Test("TRASH-01.6 a file dragged from the Trash to another folder is followed there") func aFileDraggedFromTheTrashToAnotherFolderIsFollowedThere() async throws {
        let document = try open("notes.md")
        let url = try #require(document.fileURL)
        let inTrash = try move(url, to: trash)
        #expect(await waitUntil { document.isInTrash })

        let desk = root.appendingPathComponent("Desk")
        let target = try move(inTrash, to: desk)
        #expect(await waitUntil { !document.isInTrash })

        document.edit("x")
        #expect(document.text == "x")
        #expect(document.fileURL?.resolvingSymlinksInPath() == target.resolvingSymlinksInPath())
        document.close()
    }

    @Test("TRASH-01.8 a file moved to another folder is followed without a warning") func aFileMovedToAnotherFolderIsFollowedWithoutAWarning() async throws {
        let document = try open("notes.md")
        let url = try #require(document.fileURL)
        let desk = root.appendingPathComponent("Desk")

        let target = try move(url, to: desk)

        #expect(await waitUntil {
            document.fileURL?.resolvingSymlinksInPath() == target.resolvingSymlinksInPath()
        })
        #expect(document.isInTrash == false)
        document.edit("x")
        #expect(document.text == "x")
        document.close()
    }

    @Test("TRASH-01.8 a renamed file is followed under its new name") func aRenamedFileIsFollowedUnderItsNewName() async throws {
        let document = try open("notes.md")
        let url = try #require(document.fileURL)
        let renamed = root.appendingPathComponent("ideas.md")

        try coordinatedMove(url, to: renamed)

        #expect(await waitUntil {
            document.fileURL?.resolvingSymlinksInPath() == renamed.resolvingSymlinksInPath()
        })
        #expect(document.isInTrash == false)
        #expect(document.displayName.hasPrefix("ideas"))
        document.edit("x")
        #expect(document.text == "x")
        document.close()
    }
}
}
