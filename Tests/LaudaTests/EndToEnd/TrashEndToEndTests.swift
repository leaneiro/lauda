import AppKit
import Testing
@testable import Lauda

/// The Trash rule (features/F01, TRASH-01) through the real window: the
/// workspace with its panes, far off every screen, a file moved as the
/// Finder moves it, and keys sent to the window as the keyboard sends them.
/// What a test of the document alone can't see is here: who has the
/// keyboard, what the editor's view takes, what a save writes. What only
/// the eye sees (the notice, the faded text) is in the audit's captures.
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
            let stage = try AuditStage(named: "e2e", into: scratch)
            try? FileManager.default.removeItem(at: scratch)
            self.stage = stage
            stage.workspace.viewMode = .split
            let trash = stage.folder.appendingPathComponent(".Trash", isDirectory: true)
            do {
                document = try stage.open("notes.md", text: text)
                home = try #require(document.fileURL)
                try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
            } catch {
                // Half a scene is still a window and a folder to take down.
                await stage.close()
                throw error
            }
            stage.resize(to: NSSize(width: 1100, height: 800))
            trashed = trash.appendingPathComponent(home.lastPathComponent)
            #expect(await stage.wait { editor != nil && keyboardIsInTheEditor })
        }

        /// Runs `body` on a scene and takes the scene down whatever
        /// happens in it: a window, documents and a folder left behind
        /// would be the next suite's to trip over.
        @MainActor static func run(_ body: (Scene) async throws -> Void) async throws {
            let scene = try await Scene()
            do {
                try await body(scene)
            } catch {
                await scene.stage.close()
                throw error
            }
            await scene.stage.close()
        }

        @MainActor var window: NSWindow? { stage.window }

        /// The editor of the document in front.
        @MainActor var editor: EditorTextView? {
            Self.editors(under: window?.contentView).first { !$0.isHiddenOrHasHiddenAncestor }
        }

        /// How many editors in the window take no text, hidden tabs' too.
        @MainActor var lockedEditors: Int {
            Self.editors(under: window?.contentView).filter { !$0.isEditable }.count
        }

        @MainActor var keyboardIsInTheEditor: Bool {
            window?.firstResponder is NSTextView
        }

        private static func editors(under view: NSView?) -> [EditorTextView] {
            guard let view else { return [] }
            return ((view as? EditorTextView).map { [$0] } ?? []) + view.subviews.flatMap { editors(under: $0) }
        }

        @MainActor func throwAway() async throws {
            try await Self.move(home, to: trashed)
            #expect(await stage.wait { document.isInTrash && editor?.isEditable == false })
        }

        @MainActor func putBack() async throws {
            try await Self.move(trashed, to: home)
            #expect(await stage.wait { !document.isInTrash && editor?.isEditable == true })
        }

        static func move(_ from: URL, to target: URL) async throws {
            try await FinderMove.move(from, to: target)
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

        /// A key typed and left unsaved, then the file thrown away: the
        /// edit the document keeps while the file is in the Trash.
        @MainActor func throwAwayWithAnEditKept() async throws {
            press("x", keyCode: TrashEndToEndTests.x)
            #expect(await stage.wait { document.isDocumentEdited })
            try await throwAway()
        }

        /// The question the window is asking, once it is up.
        @MainActor func sheet() async throws -> NSWindow {
            #expect(await stage.wait { window?.attachedSheet != nil })
            return try #require(window?.attachedSheet)
        }

        /// Answers the question as its first or second button would.
        @MainActor func answer(_ response: NSApplication.ModalResponse) async throws {
            let sheet = try await sheet()
            window?.endSheet(sheet, returnCode: response)
            #expect(await stage.wait { window?.attachedSheet == nil })
        }

        /// Answers a question that is followed by another one on the same window.
        @MainActor func answerAndWaitForTheNext(_ response: NSApplication.ModalResponse) async throws {
            let first = try await sheet()
            window?.endSheet(first, returnCode: response)
            #expect(await stage.wait { window?.attachedSheet != nil && window?.attachedSheet !== first })
        }

        @MainActor var isOpen: Bool {
            stage.workspace.documents.contains { $0 === document }
        }

        @MainActor func onDisk() -> String {
            (try? String(contentsOf: home, encoding: .utf8)) ?? ""
        }

        @MainActor func modified() throws -> Date {
            let url = document.isInTrash ? trashed : home
            return try #require(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        }
    }

    private static let x: UInt16 = 7

    private static func buttons(under view: NSView?) -> [NSButton] {
        guard let view else { return [] }
        return ((view as? NSButton).map { [$0] } ?? []) + view.subviews.flatMap { buttons(under: $0) }
    }

    /// Whether `text` is `original` with `key` typed once, wherever the
    /// caret was: where a document opens its caret is not this rule's.
    private static func typed(_ key: String, into original: String, gives text: String) -> Bool {
        text.count == original.count + key.count && text.replacingOccurrences(of: key, with: "") == original
    }

    @Test("a key typed in the window reaches the text while the file is where it was") func aKeyTypedInTheWindowReachesTheTextWhileTheFileIsWhereItWas() async throws {
        try await Scene.run { scene in

            scene.press("x", keyCode: Self.x)

            #expect(await scene.stage.wait { Self.typed("x", into: "draft", gives: scene.document.text) })
        }
    }

    @Test("TRASH-01.4 the editor gives up the keyboard and takes no text while the file is in the Trash") func theEditorGivesUpTheKeyboardAndTakesNoTextWhileTheFileIsInTheTrash() async throws {
        try await Scene.run { scene in
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
        }
    }

    @Test("TRASH-01.4 an edit made before the file went is not undone in the Trash") func anEditMadeBeforeTheFileWentIsNotUndoneInTheTrash() async throws {
        try await Scene.run { scene in
            scene.press("x", keyCode: Self.x)
            #expect(await scene.stage.wait { Self.typed("x", into: "draft", gives: scene.document.text) })
            try await scene.throwAway()
            let editor = try #require(scene.editor)

            editor.tryToPerform(Selector(("undo:")), with: nil)
            editor.undoManager?.undo()

            #expect(Self.typed("x", into: "draft", gives: scene.document.text))
        }
    }

    @Test("TRASH-01.4 saving writes nothing into the Trash") func savingWritesNothingIntoTheTrash() async throws {
        try await Scene.run { scene in
            try await scene.throwAway()
            let before = try scene.modified()

            scene.document.save(nil)
            try await Task.sleep(for: .seconds(1))

            #expect(try scene.modified() == before)
            #expect(try String(contentsOf: scene.trashed, encoding: .utf8) == "draft")
        }
    }

    @Test("TRASH-01.10 TRASH-01.11 an edit not yet saved stays out of the Trash and is saved once the file is back") func anEditNotYetSavedStaysOutOfTheTrashAndIsSavedOnceTheFileIsBack() async throws {
        try await Scene.run { scene in
            scene.press("x", keyCode: Self.x)
            #expect(await scene.stage.wait { scene.document.isDocumentEdited })
            try await scene.throwAway()

            await withCheckedContinuation { done in
                scene.document.autosave(withImplicitCancellability: false) { _ in done.resume() }
            }
            #expect(try String(contentsOf: scene.trashed, encoding: .utf8) == "draft")

            try await scene.putBack()
            #expect(Self.typed("x", into: "draft", gives: scene.document.text))
            // With nothing typed and nothing asked: the document saves by
            // itself what it had kept.
            #expect(await scene.stage.wait {
                Self.typed("x", into: "draft", gives: (try? String(contentsOf: scene.home, encoding: .utf8)) ?? "")
            })
            #expect(Self.typed("x", into: "draft", gives: scene.document.text))
        }
    }

    @Test("TRASH-01.4 the Format menu's commands change nothing while the file is in the Trash") func theFormatMenusCommandsChangeNothingWhileTheFileIsInTheTrash() async throws {
        try await Scene.run { scene in
            try await scene.throwAway()
            let editor = try #require(scene.editor)

            scene.document.editorActions.toggleBold()
            scene.document.editorActions.toggleItalic()
            scene.document.editorActions.insertLink()

            #expect(editor.string == "draft")
            #expect(scene.document.text == "draft")
        }
    }

    @Test("TRASH-01.4 a find bar that was open closes when the file goes to the Trash, and Find reaches nothing there") func aFindBarThatWasOpenClosesWhenTheFileGoesToTheTrash() async throws {
        try await Scene.run { scene in
            scene.document.findSession.open(in: .split)
            #expect(scene.document.findSession.isPresented)

            try await scene.throwAway()

            #expect(await scene.stage.wait { !scene.document.findSession.isPresented })
            // And the Find commands have nothing to open until it is back.
            #expect(scene.document.findSessionInReach == nil)
            #expect(await scene.stage.wait { !scene.keyboardIsInTheEditor })
        }
    }

    @Test("TRASH-01.4 the editor's own replace bar closes when the file goes to the Trash and opens again once it is back") func theEditorsOwnReplaceBarClosesWhenTheFileGoesToTheTrash() async throws {
        try await Scene.run { scene in
            scene.document.findSession.replace(in: .split)
            #expect(await scene.stage.wait { scene.editor?.enclosingScrollView?.isFindBarVisible == true })

            try await scene.throwAway()

            #expect(await scene.stage.wait { scene.editor?.enclosingScrollView?.isFindBarVisible == false })
            #expect(await scene.stage.wait { scene.window?.firstResponder === scene.window })

            // Hidden from outside the text finder, the bar still opens
            // again once the file is back.
            try await scene.putBack()
            scene.document.findSession.replace(in: .split)
            #expect(await scene.stage.wait { scene.editor?.enclosingScrollView?.isFindBarVisible == true })
        }
    }

    @Test("TRASH-01.2 a change of tab and back leaves the file's document locked, and Escape goes to the window, not to a pane") func aChangeOfTabAndBackLeavesTheFilesDocumentLocked() async throws {
        try await Scene.run { scene in
            try await scene.throwAway()
            #expect(await scene.stage.wait { !scene.keyboardIsInTheEditor })
            // Escape as it arrives with the notice in front: at whoever has
            // the keyboard, which is the window.
            #expect(scene.window?.firstResponder === scene.window)
            scene.window?.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: nil)
            #expect(scene.document.isInTrash)
            #expect(scene.editor?.isEditable == false)

            let other = try scene.stage.open("other.md", text: "other")
            #expect(await scene.stage.wait { scene.stage.workspace.selected === other && scene.keyboardIsInTheEditor })
            scene.stage.workspace.select(scene.document)

            #expect(await scene.stage.wait { scene.stage.workspace.selected === scene.document && scene.editor?.isEditable == false })
            #expect(scene.document.isInTrash)
            #expect(await scene.stage.wait { !scene.keyboardIsInTheEditor })
        }
    }

    @Test("TRASH-01.5 another file opens beside it and takes what is typed") func anotherFileOpensBesideItAndTakesWhatIsTyped() async throws {
        try await Scene.run { scene in
            try await scene.throwAway()

            let other = try scene.stage.open("other.md", text: "other")
            #expect(await scene.stage.wait { scene.stage.workspace.selected === other && scene.keyboardIsInTheEditor })
            scene.press("x", keyCode: Self.x)

            #expect(await scene.stage.wait { Self.typed("x", into: "other", gives: other.text) })
            #expect(scene.document.text == "draft")
        }
    }

    @Test("TRASH-01.5 a file in a tab behind goes to the Trash and the tab in front keeps the keyboard") func aFileInATabBehindGoesToTheTrashAndTheTabInFrontKeepsTheKeyboard() async throws {
        try await Scene.run { scene in
            let other = try scene.stage.open("other.md", text: "other")
            #expect(await scene.stage.wait { scene.stage.workspace.selected === other && scene.keyboardIsInTheEditor })
            let typing = scene.window?.firstResponder

            try await Scene.move(scene.home, to: scene.trashed)
            // Until the panes behind have heard of it, which is when they
            // would have taken the keyboard: their editor stops taking text.
            #expect(await scene.stage.wait { scene.document.isInTrash && scene.lockedEditors == 1 })

            #expect(scene.window?.firstResponder === typing)
            scene.press("x", keyCode: Self.x)
            #expect(await scene.stage.wait { Self.typed("x", into: "other", gives: other.text) })
        }
    }

    @Test("TRASH-01.6 put back, the file is read again and the window types into it") func putBackTheFileIsReadAgainAndTheWindowTypesIntoIt() async throws {
        try await Scene.run { scene in
            try await scene.throwAway()
            try Data("final".utf8).write(to: scene.trashed)

            try await scene.putBack()
            // The editor shows the text read a moment after the document
            // has it: a key pressed in between went into the text before
            // (seen on the CI's Apple silicon runner).
            #expect(await scene.stage.wait {
                scene.document.text == "final" && scene.editor?.string == "final" && scene.keyboardIsInTheEditor
            })
            scene.press("x", keyCode: Self.x)

            #expect(await scene.stage.wait { Self.typed("x", into: "final", gives: scene.document.text) })
        }
    }

    @Test("TRASH-01.12 closing with an edit kept while the file is in the Trash asks first, and Cancel keeps the tab and the edit") func closingWithAnEditKeptAsksFirstAndCancelKeepsTheTab() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()

            scene.stage.workspace.close(scene.document)
            try await scene.answer(.alertSecondButtonReturn)

            #expect(scene.isOpen)
            #expect(scene.document.isInTrash)
            #expect(Self.typed("x", into: "draft", gives: scene.document.text))
            #expect(try String(contentsOf: scene.trashed, encoding: .utf8) == "draft")
        }
    }

    @Test("TRASH-01.12 answering Close closes the tab and leaves the file in the Trash as it was") func answeringCloseClosesTheTabAndLeavesTheFileAsItWas() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()

            scene.stage.workspace.close(scene.document)
            try await scene.answer(.alertFirstButtonReturn)

            #expect(await scene.stage.wait { !scene.isOpen })
            #expect(try String(contentsOf: scene.trashed, encoding: .utf8) == "draft")
        }
    }

    @Test("TRASH-01.12 the question comes with the tab in front, when another one was") func theQuestionComesWithTheTabInFront() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()
            let other = try scene.stage.open("other.md", text: "other")
            #expect(await scene.stage.wait { scene.stage.workspace.selected === other })

            scene.stage.workspace.close(scene.document)
            _ = try await scene.sheet()

            #expect(scene.stage.workspace.selected === scene.document)
            try await scene.answer(.alertSecondButtonReturn)
            #expect(scene.isOpen)
        }
    }

    @Test("TRASH-01.5 closing with nothing unsaved asks nothing while the file is in the Trash") func closingWithNothingUnsavedAsksNothing() async throws {
        try await Scene.run { scene in
            try await scene.throwAway()

            scene.stage.workspace.close(scene.document)

            // Closed with nothing to answer: a question would have kept it.
            #expect(await scene.stage.wait { !scene.isOpen })
        }
    }

    @Test("TRASH-01.13 put back changed, with an edit kept here, the window asks and saves nothing until answered") func putBackChangedWithAnEditKeptTheWindowAsks() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()
            try Data("final".utf8).write(to: scene.trashed)

            try await scene.putBack()
            _ = try await scene.sheet()
            await withCheckedContinuation { done in
                scene.document.autosave(withImplicitCancellability: false) { _ in done.resume() }
            }

            #expect(scene.onDisk() == "final")
            #expect(Self.typed("x", into: "draft", gives: scene.document.text))
            try await scene.answer(.alertSecondButtonReturn)
        }
    }

    @Test("TRASH-01.13 answering Keep My Changes saves the text kept here over the file") func answeringKeepMyChangesSavesTheTextKeptHere() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()
            try Data("final".utf8).write(to: scene.trashed)

            try await scene.putBack()
            try await scene.answer(.alertFirstButtonReturn)

            #expect(await scene.stage.wait { Self.typed("x", into: "draft", gives: scene.onDisk()) })
            #expect(Self.typed("x", into: "draft", gives: scene.document.text))
            #expect(scene.window?.attachedSheet == nil)
        }
    }

    @Test("TRASH-01.13 answering Use the File reads the file and drops the edit kept here") func answeringUseTheFileReadsTheFile() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()
            try Data("final".utf8).write(to: scene.trashed)

            try await scene.putBack()
            try await scene.answer(.alertSecondButtonReturn)

            #expect(await scene.stage.wait { scene.document.text == "final" && !scene.document.isDocumentEdited })
            #expect(scene.onDisk() == "final")
        }
    }

    @Test("TRASH-01.12 quitting asks the same question, and Cancel keeps the app and the edit") func quittingAsksTheSameQuestionAndCancelKeepsTheApp() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()
            var mayQuit: Bool?

            scene.stage.workspace.askAboutEditsLostOnQuitting { mayQuit = $0 }
            try await scene.answer(.alertSecondButtonReturn)

            #expect(mayQuit == false)
            #expect(scene.isOpen)
            #expect(Self.typed("x", into: "draft", gives: scene.document.text))
        }
    }

    private static func words(in view: NSView) -> [String] {
        var found: [String] = []
        if let field = view as? NSTextField { found.append(field.stringValue) }
        if let button = view as? NSButton { found.append(button.title) }
        for child in view.subviews { found += words(in: child) }
        return found
    }

    @Test("TRASH-01.10 an edit not yet saved shows in the editor and stays out of the file in the Trash") func anEditNotYetSavedShowsInTheEditorAndStaysOutOfTheFile() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()

            #expect(Self.typed("x", into: "draft", gives: scene.editor?.string ?? ""))
            #expect(Self.typed("x", into: "draft", gives: scene.document.text))
            #expect(try String(contentsOf: scene.trashed, encoding: .utf8) == "draft")
        }
    }

    @Test("TRASH-01.10 a file saved before it went to the Trash keeps no edit") func aFileSavedBeforeItWentToTheTrashKeepsNoEdit() async throws {
        try await Scene.run { scene in
            scene.press("x", keyCode: Self.x)
            #expect(await scene.stage.wait { scene.document.isDocumentEdited })
            await withCheckedContinuation { done in
                scene.document.autosave(withImplicitCancellability: false) { _ in done.resume() }
            }
            #expect(await scene.stage.wait { !scene.document.isDocumentEdited })

            try await scene.throwAway()

            #expect(!scene.document.isDocumentEdited)
            scene.stage.workspace.close(scene.document)
            #expect(await scene.stage.wait { !scene.isOpen })
            #expect(scene.window?.attachedSheet == nil)
        }
    }

    @Test("TRASH-01.11 put back with no edit kept writes nothing to the file") func putBackWithNoEditKeptWritesNothingToTheFile() async throws {
        try await Scene.run { scene in
            try await scene.throwAway()
            let before = try scene.modified()

            try await scene.putBack()
            try await Task.sleep(for: .seconds(1))

            #expect(try scene.modified() == before)
            #expect(scene.onDisk() == "draft")
            #expect(scene.window?.attachedSheet == nil)
        }
    }

    @Test("TRASH-01.11 Cancel on the closing question and then putting the file back saves the edit without a question") func cancelThenPutBackSavesTheEdit() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()
            scene.stage.workspace.close(scene.document)
            try await scene.answer(.alertSecondButtonReturn)

            try await scene.putBack()

            #expect(await scene.stage.wait { Self.typed("x", into: "draft", gives: scene.onDisk()) })
            #expect(scene.window?.attachedSheet == nil)
            #expect(scene.isOpen)
        }
    }

    @Test("TRASH-01.12 the closing question has the title, the text and the two buttons") func theClosingQuestionHasTheTitleTheTextAndTheTwoButtons() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()

            scene.stage.workspace.close(scene.document)
            let words = Self.words(in: try await scene.sheet().contentView ?? NSView())

            #expect(words.contains("Close “notes.md” without saving?"))
            #expect(words.contains("The file is in the Trash, so your changes can't be saved. Put it back to keep them."))
            #expect(words.contains("Close"))
            #expect(words.contains("Cancel"))
            try await scene.answer(.alertSecondButtonReturn)
        }
    }

    @Test("TRASH-01.12 closing the whole window asks about the edit kept, and Cancel keeps it open") func closingTheWholeWindowAsksAboutTheEditKept() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()

            scene.stage.workspace.closeEveryTab()
            try await scene.answer(.alertSecondButtonReturn)

            #expect(scene.isOpen)
            #expect(scene.document.isInTrash)
            #expect(Self.typed("x", into: "draft", gives: scene.document.text))
        }
    }

    @Test("TRASH-01.12 closing the whole window and answering Close closes the document and leaves the file as it was") func closingTheWholeWindowAndAnsweringClose() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()

            scene.stage.workspace.closeEveryTab()
            try await scene.answer(.alertFirstButtonReturn)

            #expect(await scene.stage.wait { !scene.isOpen })
            #expect(try String(contentsOf: scene.trashed, encoding: .utf8) == "draft")
        }
    }

    @Test("TRASH-01.12 quitting with another tab in front brings the tab of the file in the Trash to the front") func quittingBringsTheTabToTheFront() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()
            let other = try scene.stage.open("other.md", text: "other")
            #expect(await scene.stage.wait { scene.stage.workspace.selected === other })
            var mayQuit: Bool?

            scene.stage.workspace.askAboutEditsLostOnQuitting { mayQuit = $0 }
            _ = try await scene.sheet()

            #expect(scene.stage.workspace.selected === scene.document)
            try await scene.answer(.alertSecondButtonReturn)
            #expect(mayQuit == false)
        }
    }

    @Test("TRASH-01.12 quitting with two documents holding an edit asks about each, and Cancel on the second stops the quit") func quittingWithTwoDocumentsAsksAboutEach() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()
            let second = try scene.stage.open("second.md", text: "second")
            second.edit("second kept")
            #expect(await scene.stage.wait { second.isDocumentEdited })
            let secondHome = try #require(second.fileURL)
            let secondTrashed = scene.trashed.deletingLastPathComponent().appendingPathComponent("second.md")
            try await Scene.move(secondHome, to: secondTrashed)
            #expect(await scene.stage.wait { second.isInTrash })
            var mayQuit: Bool?

            scene.stage.workspace.askAboutEditsLostOnQuitting { mayQuit = $0 }
            try await scene.answerAndWaitForTheNext(.alertFirstButtonReturn)
            try await scene.answer(.alertSecondButtonReturn)

            #expect(mayQuit == false)
            #expect(try String(contentsOf: secondTrashed, encoding: .utf8) == "second")
            #expect(try String(contentsOf: scene.trashed, encoding: .utf8) == "draft")
            #expect(scene.window?.attachedSheet == nil)
        }
    }

    @Test("TRASH-01.12 quitting with two documents holding an edit goes on once both are answered Close") func quittingWithTwoDocumentsGoesOnWhenBothAreClosed() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()
            let second = try scene.stage.open("second.md", text: "second")
            second.edit("second kept")
            #expect(await scene.stage.wait { second.isDocumentEdited })
            let secondHome = try #require(second.fileURL)
            try await Scene.move(secondHome, to: scene.trashed.deletingLastPathComponent().appendingPathComponent("second.md"))
            #expect(await scene.stage.wait { second.isInTrash })
            var mayQuit: Bool?

            scene.stage.workspace.askAboutEditsLostOnQuitting { mayQuit = $0 }
            try await scene.answerAndWaitForTheNext(.alertFirstButtonReturn)
            try await scene.answer(.alertFirstButtonReturn)

            #expect(mayQuit == true)
        }
    }

    @Test("TRASH-01.13 the question about a file changed in the Trash has the title, the text and the two buttons") func theQuestionAboutAChangedFileHasTheTitleTheTextAndTheTwoButtons() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()
            try Data("final".utf8).write(to: scene.trashed)

            try await scene.putBack()
            let words = Self.words(in: try await scene.sheet().contentView ?? NSView())

            #expect(words.contains("“notes.md” changed while it was in the Trash"))
            #expect(words.contains("Keep the changes you made here, or use the file as it is now?"))
            #expect(words.contains("Keep My Changes"))
            #expect(words.contains("Use the File"))
            #expect(!scene.document.isInTrash)
            #expect(scene.onDisk() == "final")
            try await scene.answer(.alertSecondButtonReturn)
        }
    }

    @Test("TRASH-01.13 put back changed with another tab in front brings the tab of the file to the front") func putBackChangedBringsTheTabToTheFront() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()
            try Data("final".utf8).write(to: scene.trashed)
            let other = try scene.stage.open("other.md", text: "other")
            #expect(await scene.stage.wait { scene.stage.workspace.selected === other })

            try await Scene.move(scene.trashed, to: scene.home)
            _ = try await scene.sheet()

            #expect(scene.stage.workspace.selected === scene.document)
            try await scene.answer(.alertSecondButtonReturn)
        }
    }

    @Test("TRASH-01.13 after Keep My Changes typing changes the text") func afterKeepMyChangesTypingChangesTheText() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()
            try Data("final".utf8).write(to: scene.trashed)
            try await scene.putBack()
            try await scene.answer(.alertFirstButtonReturn)
            #expect(await scene.stage.wait { scene.keyboardIsInTheEditor })
            let before = scene.document.text

            scene.press("y", keyCode: 16)

            #expect(await scene.stage.wait { Self.typed("y", into: before, gives: scene.document.text) })
        }
    }

    @Test("TRASH-01.13 after Use the File typing changes the text") func afterUseTheFileTypingChangesTheText() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()
            try Data("final".utf8).write(to: scene.trashed)
            try await scene.putBack()
            try await scene.answer(.alertSecondButtonReturn)
            // The editor shows the text read a moment after the document
            // has it: a key pressed in between went into the text before
            // (seen on the CI's Apple silicon runner).
            #expect(await scene.stage.wait {
                scene.document.text == "final" && scene.editor?.string == "final" && scene.keyboardIsInTheEditor
            })

            scene.press("y", keyCode: 16)

            #expect(await scene.stage.wait { Self.typed("y", into: "final", gives: scene.document.text) })
        }
    }

    @Test("TRASH-01.12 quitting goes on once the question is answered Close, and asks nothing with no edit kept") func quittingGoesOnOnceAnsweredClose() async throws {
        try await Scene.run { scene in
            try await scene.throwAway()
            var mayQuit: Bool?
            scene.stage.workspace.askAboutEditsLostOnQuitting { mayQuit = $0 }
            #expect(mayQuit == true)
            #expect(scene.window?.attachedSheet == nil)
        }
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()
            var mayQuit: Bool?

            scene.stage.workspace.askAboutEditsLostOnQuitting { mayQuit = $0 }
            try await scene.answer(.alertFirstButtonReturn)

            #expect(mayQuit == true)
            #expect(try String(contentsOf: scene.trashed, encoding: .utf8) == "draft")
        }
    }

    @Test("TRASH-01.12 closing again while the question is up asks only once") func closingAgainWhileTheQuestionIsUpAsksOnlyOnce() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()

            scene.stage.workspace.close(scene.document)
            _ = try await scene.sheet()
            scene.stage.workspace.close(scene.document)
            try await scene.answer(.alertSecondButtonReturn)

            // No second question waiting behind the first.
            try await Task.sleep(for: .milliseconds(300))
            #expect(scene.window?.attachedSheet == nil)
            #expect(scene.isOpen)
        }
    }

    @Test("TRASH-01.12 Return does not answer Close: the button that loses the edit has to be chosen") func returnDoesNotAnswerClose() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()

            scene.stage.workspace.close(scene.document)
            let sheet = try await scene.sheet()

            #expect(sheet.defaultButtonCell == nil)
            let buttons = Self.buttons(under: sheet.contentView)
            #expect(buttons.first { $0.title == "Close" }?.hasDestructiveAction == true)
            // Escape still means Cancel.
            #expect(buttons.first { $0.title == "Cancel" }?.keyEquivalent == "\u{1b}")
            try await scene.answer(.alertSecondButtonReturn)
        }
    }

    @Test("TRASH-01.13 while the question is up the document does not close and Save writes nothing") func whileTheQuestionIsUpTheDocumentDoesNotCloseAndSaveWritesNothing() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()
            try Data("final".utf8).write(to: scene.trashed)
            try await scene.putBack()
            _ = try await scene.sheet()

            scene.stage.workspace.close(scene.document)
            await withCheckedContinuation { done in
                scene.document.save(to: scene.home, ofType: "net.daringfireball.markdown", for: .saveOperation) { _ in done.resume() }
            }

            #expect(scene.isOpen)
            #expect(scene.onDisk() == "final")
            try await scene.answer(.alertFirstButtonReturn)
            #expect(await scene.stage.wait { Self.typed("x", into: "draft", gives: scene.onDisk()) })
        }
    }

    @Test("TRASH-01.13 Use the File reads the file where it is when answered, moved since the question") func useTheFileReadsTheFileWhereItIsWhenAnswered() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()
            try Data("final".utf8).write(to: scene.trashed)
            try await scene.putBack()
            _ = try await scene.sheet()
            let renamed = scene.home.deletingLastPathComponent().appendingPathComponent("renamed.md")
            try await Scene.move(scene.home, to: renamed)
            #expect(await scene.stage.wait { scene.document.fileURL?.lastPathComponent == "renamed.md" })

            try await scene.answer(.alertSecondButtonReturn)

            #expect(await scene.stage.wait { scene.document.text == "final" && !scene.document.isDocumentEdited })
        }
    }

    @Test("TRASH-01.13 thrown away again before the answer, the edit stays kept and nothing is written") func thrownAwayAgainBeforeTheAnswerTheEditStaysKept() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()
            try Data("final".utf8).write(to: scene.trashed)
            try await scene.putBack()
            _ = try await scene.sheet()
            try await Scene.move(scene.home, to: scene.trashed)
            #expect(await scene.stage.wait { scene.document.isInTrash })

            try await scene.answer(.alertSecondButtonReturn)

            #expect(Self.typed("x", into: "draft", gives: scene.document.text))
            #expect(scene.document.isDocumentEdited)
            #expect(try String(contentsOf: scene.trashed, encoding: .utf8) == "final")
        }
    }

    @Test("TRASH-01.14 the file deleted from the Trash with no edit kept closes the document without a question") func theFileDeletedFromTheTrashWithNoEditKeptClosesTheDocument() async throws {
        try await Scene.run { scene in
            let other = try scene.stage.open("other.md", text: "other")
            scene.stage.workspace.select(scene.document)
            try await Scene.move(scene.home, to: scene.trashed)
            #expect(await scene.stage.wait { scene.document.isInTrash })

            try FileManager.default.removeItem(at: scene.trashed)

            #expect(await scene.stage.wait { !scene.isOpen })
            #expect(scene.window?.attachedSheet == nil)
            #expect(scene.stage.workspace.selected === other)
        }
    }

    @Test("TRASH-01.15 the file deleted from the Trash with an edit kept leaves an untitled document that takes typing") func theFileDeletedFromTheTrashWithAnEditKeptLeavesAnUntitledDocument() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()

            try FileManager.default.removeItem(at: scene.trashed)

            #expect(await scene.stage.wait { !scene.document.isInTrash && scene.editor?.isEditable == true })
            #expect(scene.isOpen)
            #expect(scene.document.fileURL == nil)
            #expect(scene.document.title == "Untitled", "title is \(scene.document.title)")
            #expect(scene.document.isDocumentEdited)
            #expect(Self.typed("x", into: "draft", gives: scene.document.text))
            #expect(await scene.stage.wait { scene.keyboardIsInTheEditor })
            let kept = scene.document.text
            scene.press("x", keyCode: Self.x)
            // A second x beside the first: the text grows by the key.
            #expect(await scene.stage.wait { scene.document.text.count == kept.count + 1 })
            #expect(scene.document.text.filter { $0 == "x" }.count == 2)
            // Nothing came back to where the file was, in the Trash or out.
            #expect(!FileManager.default.fileExists(atPath: scene.trashed.path))
            #expect(!FileManager.default.fileExists(atPath: scene.home.path))
        }
    }

    @Test("TRASH-01.14 a file written again in the Trash, replaced and not deleted, keeps the document open") func aFileReplacedInTheTrashKeepsTheDocumentOpen() async throws {
        try await Scene.run { scene in
            try await scene.throwAway()

            try Data("final".utf8).write(to: scene.trashed, options: .atomic)
            try await Task.sleep(for: .milliseconds(300))

            #expect(scene.isOpen)
            #expect(scene.document.isInTrash)
            // The file written in its place is the one watched from here on.
            try FileManager.default.removeItem(at: scene.trashed)
            #expect(await scene.stage.wait { !scene.isOpen })
        }
    }

    @Test("TRASH-01.14 alone in the window, the document closes and takes the window with it") func aloneInTheWindowTheDocumentClosesAndTakesTheWindow() async throws {
        try await Scene.run { scene in
            try await scene.throwAway()

            try FileManager.default.removeItem(at: scene.trashed)

            #expect(await scene.stage.wait { !scene.isOpen && scene.window == nil })
        }
    }

    @Test("TRASH-01.16 the file deleted while the closing question is up answers it Cancel and leaves an untitled document") func theFileDeletedWhileTheClosingQuestionIsUpAnswersItCancel() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()
            scene.stage.workspace.close(scene.document)
            _ = try await scene.sheet()

            try FileManager.default.removeItem(at: scene.trashed)

            #expect(await scene.stage.wait { scene.window?.attachedSheet == nil && scene.document.fileURL == nil })
            #expect(scene.isOpen)
            #expect(scene.document.title == "Untitled")
            #expect(scene.document.isDocumentEdited)
            #expect(Self.typed("x", into: "draft", gives: scene.document.text))
        }
    }

    @Test("TRASH-01.16 the file deleted while quitting asks about it stops the quit") func theFileDeletedWhileQuittingAsksAboutItStopsTheQuit() async throws {
        try await Scene.run { scene in
            try await scene.throwAwayWithAnEditKept()
            var mayQuit: Bool?
            scene.stage.workspace.askAboutEditsLostOnQuitting { mayQuit = $0 }
            _ = try await scene.sheet()

            try FileManager.default.removeItem(at: scene.trashed)

            #expect(await scene.stage.wait { mayQuit != nil })
            #expect(mayQuit == false)
            #expect(scene.isOpen)
            #expect(scene.window?.attachedSheet == nil)
        }
    }
}
}
