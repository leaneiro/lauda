import AppKit
import Testing
@testable import Lauda

private final class FakeEditor: EditorFinding {
    var counts: (current: Int, total: Int) = (0, 0)
    private(set) var calls: [String] = []
    private(set) var countsHandler: ((Int, Int) -> Void)?

    func findUpdate(_ query: String) -> (current: Int, total: Int) {
        calls.append("update \(query)")
        return counts
    }

    func findStep(forward: Bool) -> (current: Int, total: Int) {
        calls.append(forward ? "next" : "previous")
        return counts
    }

    func findClear() { calls.append("clear") }

    func performFind(_ action: NSTextFinder.Action) {
        calls.append(action == .showReplaceInterface ? "replace bar" : "other action")
    }

    func setFindCountsHandler(_ handler: @escaping (Int, Int) -> Void) {
        countsHandler = handler
    }
}

private final class FakePreview: PreviewFinding {
    var counts = (current: 0, total: 0)
    private(set) var calls: [String] = []

    func find(_ query: String, forward: Bool, restart: Bool, completion: @escaping (Int, Int) -> Void) {
        calls.append("find \(query) \(forward ? "next" : "previous")\(restart ? " from top" : "")")
        completion(counts.current, counts.total)
    }

    func clearFind() { calls.append("clear") }
}

/// Lets everything already queued on the main queue run.
@MainActor
private func drainMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}

@MainActor
struct FindSessionTests {
    private let editor = FakeEditor()
    private let preview = FakePreview()
    private let session: FindSession

    init() {
        session = FindSession(editor: editor, preview: preview)
    }

    @Test(arguments: [ViewMode.editorOnly, .split])
    func withTheEditorVisibleTheEditorSearches(mode: ViewMode) {
        editor.counts = (1, 3)
        session.open(in: mode)
        session.query = "cat"
        session.search(in: mode)
        #expect(editor.calls == ["update cat"])
        #expect(preview.calls.isEmpty)
        #expect(session.current == 1)
        #expect(session.total == 3)
    }

    @Test func inPreviewOnlyModeThePreviewSearches() {
        preview.counts = (2, 4)
        session.open(in: .previewOnly)
        session.query = "cat"
        session.search(in: .previewOnly)
        #expect(preview.calls == ["find cat next from top"])
        #expect(editor.calls.isEmpty)
        #expect(session.current == 2)
        #expect(session.total == 4)
    }

    @Test func clearingTheQueryResetsCountsAndHighlights() {
        editor.counts = (1, 3)
        session.open(in: .split)
        session.query = "cat"
        session.search(in: .split)
        session.query = ""
        session.search(in: .split)
        #expect(session.current == 0)
        #expect(session.total == 0)
        #expect(editor.calls == ["update cat", "clear"])
        #expect(preview.calls == ["clear"])
    }

    @Test func nothingIsSearchedWhileTheBarIsClosed() {
        session.query = "cat"
        session.search(in: .split)
        #expect(editor.calls.isEmpty)
        #expect(preview.calls.isEmpty)
    }

    @Test func openingSearchesAgainForAQueryAlreadyTyped() {
        session.query = "cat"
        session.open(in: .split)
        #expect(session.isPresented)
        #expect(editor.calls == ["update cat"])
    }

    @Test func steppingWithNothingToStepThroughOpensTheBar() {
        session.step(forward: true, in: .split)
        #expect(session.isPresented)
        #expect(editor.calls.isEmpty)
    }

    @Test func stepsGoThroughTheVisiblePane() {
        session.open(in: .split)
        session.query = "cat"
        session.step(forward: true, in: .split)
        session.step(forward: false, in: .split)
        #expect(editor.calls == ["next", "previous"])

        session.step(forward: true, in: .previewOnly)
        session.step(forward: false, in: .previewOnly)
        #expect(preview.calls == ["find cat next", "find cat previous"])
    }

    @Test func replaceClosesTheBarForTheEditorsReplaceInterface() {
        session.open(in: .split)
        session.replace(in: .split)
        #expect(!session.isPresented)
        #expect(editor.calls == ["clear", "replace bar"])
        #expect(preview.calls == ["clear"])
    }

    @Test func replaceInPreviewOnlyModeOpensTheFindBar() {
        session.replace(in: .previewOnly)
        #expect(session.isPresented)
        #expect(editor.calls.isEmpty)
    }

    @Test func closingResetsEverything() {
        editor.counts = (1, 3)
        session.open(in: .split)
        session.query = "cat"
        session.search(in: .split)
        session.close()
        #expect(!session.isPresented)
        #expect(session.current == 0)
        #expect(session.total == 0)
        #expect(editor.calls.last == "clear")
        #expect(preview.calls == ["clear"])
    }

    /// Typing in the editor changes the matches; the editor reports new counts later.
    @Test func countsTheEditorReportsLaterReachTheBar() async {
        session.open(in: .split)
        editor.countsHandler?(4, 9)
        await drainMainQueue()
        #expect(session.current == 4)
        #expect(session.total == 9)
    }

    @Test func switchingModesRestartsAnOpenSearchInTheNewPane() async {
        session.open(in: .split)
        session.query = "cat"
        session.search(in: .split)
        session.modeChanged(to: .previewOnly)
        #expect(editor.calls == ["update cat", "clear"])
        #expect(preview.calls == ["clear"])
        await drainMainQueue()
        #expect(preview.calls == ["clear", "find cat next from top"])
    }

    @Test func switchingModesWithTheBarClosedDoesNothing() async {
        session.modeChanged(to: .previewOnly)
        await drainMainQueue()
        #expect(editor.calls.isEmpty)
        #expect(preview.calls.isEmpty)
    }
}
