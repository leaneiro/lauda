import SwiftUI

enum ViewMode: Int {
    case editorOnly
    case split
    case previewOnly
}

struct ViewModeKey: FocusedValueKey {
    typealias Value = Binding<ViewMode>
}

extension FocusedValues {
    var viewMode: Binding<ViewMode>? {
        get { self[ViewModeKey.self] }
        set { self[ViewModeKey.self] = newValue }
    }
}

struct ViewModeCommands: Commands {
    @FocusedBinding(\.viewMode) private var viewMode: ViewMode?

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Somente Editor") { viewMode = .editorOnly }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(viewMode == nil)
            Button("Editor e Visualização") { viewMode = .split }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(viewMode == nil)
            Button("Somente Visualização") { viewMode = .previewOnly }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(viewMode == nil)
            Divider()
        }
    }
}

struct ContentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    @SceneStorage("viewMode") private var viewMode: ViewMode = .split
    @State private var editorScrollFraction: CGFloat = 0

    var body: some View {
        HSplitView {
            if viewMode != .previewOnly {
                MarkdownTextView(text: $document.text, scrollFraction: $editorScrollFraction)
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
            if viewMode != .editorOnly {
                PreviewWebView(
                    markdown: document.text,
                    baseURL: fileURL?.deletingLastPathComponent(),
                    scrollFraction: editorScrollFraction
                )
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 700, minHeight: 440)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            statusBar
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Modo de exibição", selection: $viewMode) {
                    Label("Somente editor", systemImage: "doc.plaintext")
                        .tag(ViewMode.editorOnly)
                    Label("Editor e visualização", systemImage: "rectangle.split.2x1")
                        .tag(ViewMode.split)
                    Label("Somente visualização", systemImage: "doc.richtext")
                        .tag(ViewMode.previewOnly)
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
            }
        }
        .focusedSceneValue(\.viewMode, $viewMode)
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            Text("\(wordCount) palavras")
            Text("\(document.text.count) caracteres")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var wordCount: Int {
        document.text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count
    }
}
