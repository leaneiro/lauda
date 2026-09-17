import AppKit
import Testing
@testable import Lauda

@MainActor
@Suite struct MarkdownDocumentTests {
    private let markdownType = "net.daringfireball.markdown"

    @Test func readingAFileSetsTheTextAndWhatTheFileHolds() throws {
        let document = MarkdownDocument()

        try document.read(from: Data("# Olá".utf8), ofType: markdownType)

        #expect(document.text == "# Olá")
        #expect(document.savedText == "# Olá")
        #expect(document.isEdited == false)
    }

    /// Typing has to reach NSDocument, or nothing would ever autosave.
    @Test func typingMarksTheDocumentEdited() throws {
        let document = MarkdownDocument()
        try document.read(from: Data("a".utf8), ofType: markdownType)

        document.edit("a mais")

        #expect(document.text == "a mais")
        #expect(document.isDocumentEdited)
        #expect(document.isEdited, "the tab strip's copy of the flag follows")
        #expect(document.savedText == "a", "the file still holds what it held")
    }

    /// SwiftUI writes a binding back even when nothing changed; that must
    /// not dirty the document.
    @Test func settingTheSameTextChangesNothing() throws {
        let document = MarkdownDocument()
        try document.read(from: Data("a".utf8), ofType: markdownType)

        document.edit("a")

        #expect(document.isDocumentEdited == false)
    }

    @Test func whatIsWrittenIsTheTextAsUTF8() throws {
        let document = MarkdownDocument()
        document.edit("Café, naïve façade!")

        let data = try document.data(ofType: markdownType)

        #expect(String(data: data, encoding: .utf8) == "Café, naïve façade!")
    }

    @Test func aLatin1FileOpensWithoutLosingCharacters() throws {
        let document = MarkdownDocument()
        let latin1 = try #require("Café".data(using: .isoLatin1))

        try document.read(from: latin1, ofType: markdownType)

        #expect(document.text == "Café")
    }

    /// A tab comes back the way it was left, so what belongs to a document
    /// lives with it.
    @Test func eachDocumentKeepsItsOwnPaneState() {
        let first = MarkdownDocument()
        let second = MarkdownDocument()

        first.scrollSync.fraction = 0.5
        first.findSession.query = "procurado"

        #expect(second.scrollSync.fraction == 0)
        #expect(second.findSession.query.isEmpty)
        #expect(first.findSession !== second.findSession)
    }

    /// NSDocument's name isn't observable; the tab strip reads this copy.
    @Test func theTabTitleFollowsTheDocumentsName() {
        let document = MarkdownDocument()

        document.displayName = "Welcome"

        #expect(document.title == "Welcome")
    }
}
