import SwiftUI
import AppKit

/// Unified floating find bar — same look and position in every view mode.
struct FindBar: View {
    @Binding var query: String
    let current: Int
    let total: Int
    var onQueryChanged: () -> Void
    var onNext: () -> Void
    var onPrevious: () -> Void
    var onClose: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find", text: $query)
                .textFieldStyle(.plain)
                .frame(width: 170)
                .focused($isFocused)
                .onSubmit(onNext)
                .onExitCommand(perform: onClose)
                .onChange(of: query) {
                    onQueryChanged()
                }
            if !query.isEmpty {
                Text(total > 0 ? "\(current)/\(total)" : "0")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(total > 0 ? Color.secondary : Color.red)
                    .frame(minWidth: 34)
            }
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(total == 0)
            .help("Previous (⇧⌘G)")
            Button(action: onNext) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(total == 0)
            .help("Next (⌘G)")
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 10, y: 3)
        .padding(12)
        .onAppear { isFocused = true }
    }
}
