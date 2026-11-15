import AppKit
import Testing
@testable import Lauda

/// The Trash rule (features/F01, TRASH-01) through the real window: the
/// workspace with its panes, far off every screen, a file moved as the
/// Finder moves it, and keys sent to the window as the keyboard sends them.
/// What a test of the document alone can't see is here: who has the
/// keyboard, what the editor's view takes, what a save writes.
extension OpenDocumentsSuites {
@MainActor
@Suite(.serialized, .enabled(if: TestMachine.drawsWithMetal))
struct TrashEndToEndTests {
    /// The app with one file open and, for most tests, that file in the
    /// Trash: a folder named as the Trash is, inside the stage's own.
    private struct Scene {
        let stage: AuditStage
        let document: MarkdownDocument
        let home: URL
        let trashed: URL

        @MainActor init(text: String = "draft") async throws {
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("lauda-e2e-\(UUID().uuidString)")
            stage = try AuditStage(named: "e2e", appearance: .aqua, into: scratch)
            stage.workspace.viewMode = .split
            document = try stage.open("notes.md", text: text)
            stage.resize(to: NSSize(width: 1100, height: 800))
            home = try #require(document.fileURL)
            let trash = stage.folder.appendingPathComponent(".Trash", isDirectory: true)
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
            trashed = trash.appendingPathComponent(home.lastPathComponent)
            try? FileManager.default.removeItem(at: scratch)
            #expect(await stage.wait { editor != nil && keyboardIsInTheEditor })
        }

        @MainActor var window: NSWindow? { stage.window }

        /// The editor of the document in front.
        @MainActor var editor: EditorTextView? {
            Self.editors(under: window?.contentView).first { !$0.isHiddenOrHasHiddenAncestor }
        }

        @MainActor var keyboardIsInTheEditor: Bool {
            window?.firstResponder is NSTextView
        }

        private static func editors(under view: NSView?) -> [EditorTextView] {
            guard let view else { return [] }
            return ((view as? EditorTextView).map { [$0] } ?? []) + view.subviews.flatMap { editors(under: $0) }
        }

        @MainActor func throwAway() async throws {
            try Self.move(home, to: trashed)
            #expect(await stage.wait { document.isInTrash && editor?.isEditable == false })
        }

        @MainActor func putBack() async throws {
            try Self.move(trashed, to: home)
            #expect(await stage.wait { !document.isInTrash && editor?.isEditable == true })
        }

        /// The Finder moves files under a file coordinator, which is what
        /// tells an open document about it; a bare move does not.
        private static func move(_ from: URL, to target: URL) throws {
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
                } catch {
                    moveError = error
                }
            }
            if let error = coordinationError ?? moveError { throw error }
        }

        /// A key pressed, sent to the window as the keyboard's are. Only
        /// while a text view has the keyboard: a key nobody takes makes the
        /// Mac beep.
        @MainActor func press(_ character: String, keyCode: UInt16) {
            guard let window, keyboardIsInTheEditor,
                let event = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: character,
                    charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode)
            else { return }
            window.sendEvent(event)
        }

        @MainActor func modified() throws -> Date {
            let url = document.isInTrash ? trashed : home
            return try #require(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        }
    }

    private static let x: UInt16 = 7

    /// Whether `text` is `original` with `key` typed once, wherever the
    /// caret was: where a document opens its caret is not this rule's.
    private static func typed(_ key: String, into original: String, gives text: String) -> Bool {
        text.count == original.count + key.count && text.replacingOccurrences(of: key, with: "") == original
    }

    @Test("a key typed in the window reaches the text while the file is where it was") func aKeyTypedInTheWindowReachesTheTextWhileTheFileIsWhereItWas() async throws {
        let scene = try await Scene()

        scene.press("x", keyCode: Self.x)

        #expect(await scene.stage.wait { Self.typed("x", into: "draft", gives: scene.document.text) })
        await scene.stage.close()
    }

    @Test("TRASH-01.4 the editor gives up the keyboard and takes no text while the file is in the Trash") func theEditorGivesUpTheKeyboardAndTakesNoTextWhileTheFileIsInTheTrash() async throws {
        let scene = try await Scene()
        try await scene.throwAway()
        let editor = try #require(scene.editor)

        #expect(await scene.stage.wait { !scene.keyboardIsInTheEditor })
        // What a key ends in, what Delete does and what Edit > Undo sends,
        // given to the editor all the same.
        editor.insertText("x", replacementRange: NSRange(location: 0, length: 0))
        editor.tryToPerform(#selector(NSText.delete(_:)), with: nil)
        editor.tryToPerform(Selector(("undo:")), with: nil)

        #expect(editor.string == "draft")
        #expect(scene.document.text == "draft")
        #expect(!scene.document.isDocumentEdited)
        #expect(try String(contentsOf: scene.trashed, encoding: .utf8) == "draft")
        await scene.stage.close()
    }

    @Test("TRASH-01.4 an edit made before the file went is not undone in the Trash") func anEditMadeBeforeTheFileWentIsNotUndoneInTheTrash() async throws {
        let scene = try await Scene()
        scene.press("x", keyCode: Self.x)
        #expect(await scene.stage.wait { Self.typed("x", into: "draft", gives: scene.document.text) })
        try await scene.throwAway()
        let editor = try #require(scene.editor)

        editor.tryToPerform(Selector(("undo:")), with: nil)
        editor.undoManager?.undo()

        #expect(Self.typed("x", into: "draft", gives: scene.document.text))
        await scene.stage.close()
    }

    @Test("TRASH-01.4 saving writes nothing into the Trash") func savingWritesNothingIntoTheTrash() async throws {
        let scene = try await Scene()
        try await scene.throwAway()
        let before = try scene.modified()

        scene.document.save(nil)
        try await Task.sleep(for: .seconds(1))

        #expect(try scene.modified() == before)
        #expect(try String(contentsOf: scene.trashed, encoding: .utf8) == "draft")
        await scene.stage.close()
    }

    @Test("TRASH-01.4 an edit not yet saved stays out of the Trash and is saved once the file is back") func anEditNotYetSavedStaysOutOfTheTrashAndIsSavedOnceTheFileIsBack() async throws {
        let scene = try await Scene()
        scene.press("x", keyCode: Self.x)
        #expect(await scene.stage.wait { scene.document.isDocumentEdited })
        try await scene.throwAway()

        await withCheckedContinuation { done in
            scene.document.autosave(withImplicitCancellability: false) { _ in done.resume() }
        }
        #expect(try String(contentsOf: scene.trashed, encoding: .utf8) == "draft")

        try await scene.putBack()
        await withCheckedContinuation { done in
            scene.document.autosave(withImplicitCancellability: false) { _ in done.resume() }
        }
        #expect(Self.typed("x", into: "draft", gives: scene.document.text))
        #expect(try String(contentsOf: scene.home, encoding: .utf8) == scene.document.text)
        await scene.stage.close()
    }

    @Test("TRASH-01.4 the Format menu's commands change nothing while the file is in the Trash") func theFormatMenusCommandsChangeNothingWhileTheFileIsInTheTrash() async throws {
        let scene = try await Scene()
        try await scene.throwAway()
        let editor = try #require(scene.editor)

        scene.document.editorActions.toggleBold()
        scene.document.editorActions.toggleItalic()
        scene.document.editorActions.insertLink()

        #expect(editor.string == "draft")
        #expect(scene.document.text == "draft")
        await scene.stage.close()
    }

    @Test("TRASH-01.4 a find bar that was open closes when the file goes to the Trash") func aFindBarThatWasOpenClosesWhenTheFileGoesToTheTrash() async throws {
        let scene = try await Scene()
        scene.document.findSession.open(in: .split)
        #expect(scene.document.findSession.isPresented)

        try await scene.throwAway()

        #expect(await scene.stage.wait { !scene.document.findSession.isPresented })
        #expect(await scene.stage.wait { !scene.keyboardIsInTheEditor })
        await scene.stage.close()
    }

    @Test("TRASH-01.2 Escape and a change of tab and back leave the file's document locked") func escapeAndAChangeOfTabAndBackLeaveTheFilesDocumentLocked() async throws {
        let scene = try await Scene()
        try await scene.throwAway()
        let other = try scene.stage.open("other.md", text: "other")
        #expect(await scene.stage.wait { scene.stage.workspace.selected === other && scene.keyboardIsInTheEditor })

        scene.window?.firstResponder?.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: nil)
        scene.stage.workspace.select(scene.document)

        #expect(await scene.stage.wait { scene.stage.workspace.selected === scene.document && scene.editor?.isEditable == false })
        #expect(scene.document.isInTrash)
        #expect(await scene.stage.wait { !scene.keyboardIsInTheEditor })
        await scene.stage.close()
    }

    @Test("TRASH-01.5 another file opens beside it and takes what is typed") func anotherFileOpensBesideItAndTakesWhatIsTyped() async throws {
        let scene = try await Scene()
        try await scene.throwAway()

        let other = try scene.stage.open("other.md", text: "other")
        #expect(await scene.stage.wait { scene.stage.workspace.selected === other && scene.keyboardIsInTheEditor })
        scene.press("x", keyCode: Self.x)

        #expect(await scene.stage.wait { Self.typed("x", into: "other", gives: other.text) })
        #expect(scene.document.text == "draft")
        await scene.stage.close()
    }

    @Test("TRASH-01.6 put back, the file is read again and the window types into it") func putBackTheFileIsReadAgainAndTheWindowTypesIntoIt() async throws {
        let scene = try await Scene()
        try await scene.throwAway()
        try Data("final".utf8).write(to: scene.trashed)

        try await scene.putBack()
        #expect(await scene.stage.wait { scene.document.text == "final" && scene.keyboardIsInTheEditor })
        scene.press("x", keyCode: Self.x)

        #expect(await scene.stage.wait { Self.typed("x", into: "final", gives: scene.document.text) })
        await scene.stage.close()
    }
}
}
