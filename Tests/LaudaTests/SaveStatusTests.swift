import Foundation
import Testing
@testable import Lauda

struct SaveStatusTests {
    private let file = URL(fileURLWithPath: "/tmp/notes.md")
    private let savedAt = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aNewDocumentIsNotSavedYet() {
        let status = SaveStatus(text: "draft", fileURL: nil, lastSavedText: nil, lastSaveDate: nil)
        #expect(status == .notSavedYet)
    }

    /// The save notification can arrive before the window learns the file's URL.
    @Test func aFirstSaveCountsBeforeTheFileURLArrives() {
        let status = SaveStatus(text: "draft", fileURL: nil, lastSavedText: "draft", lastSaveDate: savedAt)
        #expect(status == .saved(date: savedAt))
    }

    @Test func aFileOpenedFromDiskIsSavedWithoutATime() {
        let status = SaveStatus(text: "notes", fileURL: file, lastSavedText: "notes", lastSaveDate: nil)
        #expect(status == .saved(date: nil))
    }

    @Test func textThatDiffersFromTheLastSaveIsEditing() {
        let status = SaveStatus(text: "notes!", fileURL: file, lastSavedText: "notes", lastSaveDate: savedAt)
        #expect(status == .editing)
    }

    /// With a URL but no save seen yet (not opened from disk), the text can't match anything.
    @Test func aFileWithoutAKnownSavedTextIsEditing() {
        let status = SaveStatus(text: "notes", fileURL: file, lastSavedText: nil, lastSaveDate: nil)
        #expect(status == .editing)
    }

    @Test func labelsAndIcons() {
        #expect(SaveStatus.notSavedYet.label == "Not saved yet")
        #expect(SaveStatus.saved(date: nil).label == "Saved")
        #expect(SaveStatus.saved(date: savedAt).label.hasPrefix("Saved · "))
        #expect(SaveStatus.editing.label == "Editing…")
        #expect(SaveStatus.notSavedYet.icon == "circle.dotted")
        #expect(SaveStatus.saved(date: nil).icon == "checkmark.circle.fill")
        #expect(SaveStatus.editing.icon == "ellipsis.circle.fill")
    }
}
