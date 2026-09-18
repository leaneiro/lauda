import Testing
@testable import Lauda

/// A change of view mode animates unless it would stutter.
struct ModeChangeTests {
    private let short = 4_000
    private let long = ModeChange.longestTextRewrappedSmoothly + 1

    @Test(arguments: [ViewMode.editorOnly, .split, .previewOnly], [ViewMode.editorOnly, .split, .previewOnly])
    func aShortTextAnimatesEveryChange(from: ViewMode, to: ViewMode) {
        #expect(ModeChange.isSmooth(from: from, to: to, textBytes: short))
    }

    /// The editor wraps its text again on every frame while it changes
    /// width, which a long text can't do in time.
    @Test func aLongTextDoesNotAnimateTheEditorChangingWidth() {
        #expect(!ModeChange.isSmooth(from: .split, to: .editorOnly, textBytes: long))
        #expect(!ModeChange.isSmooth(from: .editorOnly, to: .split, textBytes: long))
    }

    /// The preview lays out off the main thread, and an editor that only
    /// comes or goes keeps its width.
    @Test func aLongTextStillAnimatesWhenTheEditorKeepsItsWidth() {
        #expect(ModeChange.isSmooth(from: .split, to: .previewOnly, textBytes: long))
        #expect(ModeChange.isSmooth(from: .previewOnly, to: .split, textBytes: long))
        #expect(ModeChange.isSmooth(from: .editorOnly, to: .previewOnly, textBytes: long))
        #expect(ModeChange.isSmooth(from: .previewOnly, to: .editorOnly, textBytes: long))
    }

    @Test func theFirstModeShownHasNothingToAnimateFrom() {
        #expect(ModeChange.isSmooth(from: nil, to: .split, textBytes: long))
    }
}
