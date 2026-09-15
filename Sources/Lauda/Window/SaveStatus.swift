import SwiftUI

/// What the status bar says about saving a document.
enum SaveStatus: Equatable {
    /// A new document that has never been written.
    case notSavedYet
    /// The text on screen is what was last written. `date` is when this
    /// window saw that save; nil for a file shown as it was on disk.
    case saved(date: Date?)
    /// The text changed since the last save, which autosave will catch up on.
    case editing

    init(text: String, fileURL: URL?, lastSavedText: String?, lastSaveDate: Date?) {
        if fileURL == nil && lastSavedText == nil {
            self = .notSavedYet
        } else if text == lastSavedText {
            self = .saved(date: lastSaveDate)
        } else {
            self = .editing
        }
    }

    var icon: String {
        switch self {
        case .notSavedYet: return "circle.dotted"
        case .saved: return "checkmark.circle.fill"
        case .editing: return "ellipsis.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .notSavedYet:
            return String(localized: "Not saved yet")
        case .saved(let date?):
            let time = date.formatted(date: .omitted, time: .shortened)
            return String(localized: "Saved · \(time)")
        case .saved(nil):
            return String(localized: "Saved")
        case .editing:
            return String(localized: "Editing…")
        }
    }

    var color: Color {
        switch self {
        case .notSavedYet: return .secondary
        case .saved: return .green
        case .editing: return .orange
        }
    }
}
