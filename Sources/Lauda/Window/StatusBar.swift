import SwiftUI

/// The strip under a document: word and character counts, reading time and
/// whether the document is saved.
struct StatusBar: View {
    let text: String
    let fileURL: URL?
    let lastSavedText: String?
    let lastSaveDate: Date?

    /// Words in the document; nil until the first count finishes.
    @State private var wordCount: Int?

    var body: some View {
        HStack(spacing: 16) {
            if let wordCount {
                Text("\(wordCount) words")
            }
            Text("\(text.count) characters")
            if let readingTime = wordCount.flatMap(ReadingTime.label(forWordCount:)) {
                Text(readingTime)
            }
            Spacer()
            saveStatusView
        }
        .task(id: text) { await updateWordCount() }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    /// Counting walks the whole text (slow for long Japanese or Chinese
    /// documents), so while typing it waits for a pause and runs off the
    /// main thread. The first count, when the window opens, runs right away.
    private func updateWordCount() async {
        if wordCount != nil {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
        }
        let text = self.text
        let count = await Task.detached(priority: .userInitiated) { WordCount.count(in: text) }.value
        if !Task.isCancelled {
            wordCount = count
        }
    }

    private var saveStatusView: some View {
        let status = saveStatus
        return HStack(spacing: 5) {
            Image(systemName: status.icon)
                .foregroundStyle(status.color)
            Text(status.label)
        }
        .help("macOS saves automatically; ⌘S saves right away.")
    }

    private var saveStatus: (icon: String, label: String, color: Color) {
        if fileURL == nil && lastSavedText == nil {
            return ("circle.dotted", String(localized: "Not saved yet"), .secondary)
        }
        if text == lastSavedText {
            if let date = lastSaveDate {
                let time = date.formatted(date: .omitted, time: .shortened)
                return ("checkmark.circle.fill", String(localized: "Saved · \(time)"), .green)
            }
            return ("checkmark.circle.fill", String(localized: "Saved"), .green)
        }
        return ("ellipsis.circle.fill", String(localized: "Editing…"), .orange)
    }
}
