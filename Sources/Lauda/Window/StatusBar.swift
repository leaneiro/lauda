import SwiftUI

/// The strip under a document: word and character counts, reading time and
/// whether the document is saved.
struct StatusBar: View {
    let text: String
    let fileURL: URL?
    let lastSavedText: String?
    let lastSaveDate: Date?

    @State private var wordCounter = WordCountModel()

    var body: some View {
        HStack(spacing: 16) {
            if let wordCount = wordCounter.wordCount {
                Text("\(wordCount) words")
            }
            Text("\(text.count) characters")
            if let readingTime = wordCounter.wordCount.flatMap(ReadingTime.label(forWordCount:)) {
                Text(readingTime)
            }
            Spacer()
            saveStatusView
        }
        .task(id: text) { await wordCounter.update(for: text) }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var saveStatusView: some View {
        let status = SaveStatus(
            text: text,
            fileURL: fileURL,
            lastSavedText: lastSavedText,
            lastSaveDate: lastSaveDate
        )
        return HStack(spacing: 5) {
            Image(systemName: status.icon)
                .foregroundStyle(status.color)
            Text(status.label)
        }
        .help("macOS saves automatically; ⌘S saves right away.")
    }
}
