import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Lauda

/// Walks the app's screens and captures each one (see AuditStage). It is
/// not a test of anything by itself: the captures are compared with the
/// baseline's by Scripts/ui-audit.sh, and read by whoever audits.
///
/// The steps use only what the app has had for long, so the same file runs
/// on the baseline commit: a screen whose feature the baseline lacks comes
/// out there as the baseline behaves, and the comparison shows the feature.
@MainActor
@Suite(.serialized, .enabled(if: UIAudit.isRequested && TestMachine.drawsWithMetal))
struct UIAuditTests {
    @Test func walkTheScreens() async throws {
        let output = try #require(UIAudit.outputFolder)
        for (appearanceName, appearance) in UIAudit.appearances {
            for size in UIAudit.sizes {
                let name = "\(appearanceName)-\(Int(size.width))x\(Int(size.height))"
                let stage = try AuditStage(named: name, appearance: appearance, into: output)
                try await walk(stage, size: size)
                await stage.close()
            }
        }
    }

    private func walk(_ stage: AuditStage, size: NSSize) async throws {
        let workspace = stage.workspace
        workspace.viewMode = .split

        let notes = try stage.open("field-notes.md", text: AuditDocuments.notes)
        stage.resize(to: size)
        await stage.capture("01-one-document-split")

        workspace.viewMode = .editorOnly
        await stage.capture("02-one-document-editor")

        workspace.viewMode = .previewOnly
        await stage.capture("03-one-document-preview")

        workspace.viewMode = .split
        notes.findSession.query = "the"
        notes.findSession.open(in: workspace.viewMode)
        await stage.capture("04-find-bar")
        notes.findSession.close()

        let ideas = try stage.open("ideas.md", text: AuditDocuments.ideas)
        await stage.capture("05-two-tabs")

        let more = [
            try stage.open(AuditDocuments.longName, text: AuditDocuments.short),
            try stage.open("short.md", text: AuditDocuments.short),
            stage.openUntitled(),
        ]
        await stage.capture("06-five-tabs-untitled-in-front")

        workspace.select(notes)
        workspace.viewMode = .previewOnly
        await stage.capture("07-five-tabs-preview")

        workspace.viewMode = .split
        for document in more {
            document.close()
        }
        await stage.capture("08-back-to-two-tabs")

        // A folder named as the Trash is, inside the audit's own: the real
        // Trash is never touched, and the app tells one by its name too.
        let trash = stage.folder.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let home = try #require(notes.fileURL)
        let trashed = trash.appendingPathComponent(home.lastPathComponent)
        try FileManager.default.moveItem(at: home, to: trashed)
        if await !stage.wait(for: { notes.fileURL?.path.contains("/.Trash/") == true }) {
            stage.note("the document never heard that its file went to the Trash")
        }
        await stage.capture("09-file-in-trash")

        workspace.select(ideas)
        await stage.capture("10-file-in-trash-other-tab-in-front")

        ideas.close()
        await stage.capture("11-file-in-trash-alone")

        try FileManager.default.moveItem(at: trashed, to: home)
        if await !stage.wait(for: { notes.fileURL?.path.contains("/.Trash/") == false }) {
            stage.note("the document never heard that its file was put back")
        }
        await stage.capture("12-file-put-back")

        // The toolbar lays its items out again when the window changes
        // size, and with tabs it once kept the old layout after growing.
        let reopened = try stage.open("ideas.md", text: AuditDocuments.ideas)
        stage.resize(to: NSSize(width: size.width + 300, height: size.height))
        await stage.capture("13-two-tabs-window-grown")

        stage.resize(to: NSSize(width: 760, height: size.height))
        await stage.capture("14-two-tabs-window-narrow")

        stage.resize(to: size)
        await stage.capture("15-two-tabs-window-back")

        reopened.close()
        stage.resize(to: NSSize(width: size.width + 300, height: size.height))
        await stage.capture("16-one-document-window-grown")
    }
}
