import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKeys.editorFontName) private var editorFontName = SettingsDefaults.editorFontName
    @AppStorage(SettingsKeys.editorFontSize) private var editorFontSize = SettingsDefaults.editorFontSize
    @AppStorage(SettingsKeys.previewFontName) private var previewFontName = SettingsDefaults.previewFontName
    @AppStorage(SettingsKeys.previewFontSize) private var previewFontSize = SettingsDefaults.previewFontSize
    @AppStorage(SettingsKeys.previewLineHeight) private var previewLineHeight = SettingsDefaults.previewLineHeight
    @AppStorage(SettingsKeys.appearanceMode) private var appearanceMode = SettingsDefaults.appearanceMode
    @AppStorage(SettingsKeys.strictLineBreaks) private var strictLineBreaks = SettingsDefaults.strictLineBreaks

    var body: some View {
        Form {
            Section("Geral") {
                Picker("Aparência", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearanceMode) {
                    AppearanceMode.stored.apply()
                }
            }

            Section("Editor") {
                fontPicker("Fonte", selection: $editorFontName)
                sizeSlider("Tamanho", value: $editorFontSize, range: 10...24)
            }

            Section("Visualização") {
                fontPicker("Fonte", selection: $previewFontName)
                sizeSlider("Tamanho", value: $previewFontSize, range: 12...28)
                HStack {
                    Slider(value: $previewLineHeight, in: 1.2...2.2, step: 0.05) {
                        Text("Entrelinha")
                    }
                    Text(previewLineHeight.formatted(.number.precision(.fractionLength(2))))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                Toggle(isOn: $strictLineBreaks) {
                    Text("Quebras de linha estritas")
                    Text("Um Enter sozinho não quebra a linha, como no Markdown padrão.")
                }
            }

            Section {
                Button("Restaurar padrões") {
                    editorFontName = SettingsDefaults.editorFontName
                    editorFontSize = SettingsDefaults.editorFontSize
                    previewFontName = SettingsDefaults.previewFontName
                    previewFontSize = SettingsDefaults.previewFontSize
                    previewLineHeight = SettingsDefaults.previewLineHeight
                    appearanceMode = SettingsDefaults.appearanceMode
                    strictLineBreaks = SettingsDefaults.strictLineBreaks
                    AppearanceMode.stored.apply()
                }
            }
        }
        .formStyle(.grouped)
        // Everything fits in this fixed-size window, but the grouped Form
        // under the transparent title bar comes out 0.5pt taller than its
        // visible area, which shows a pointless scroll bar.
        .scrollDisabled(true)
        .scrollIndicators(.never)
        .frame(width: 480)
        .fixedSize()
    }

    private func fontPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(FontOption.specialOptions, id: \.id) { option in
                Text(option.label).tag(option.id)
            }
            Divider()
            ForEach(FontOption.installedFamilies, id: \.self) { family in
                Text(family).tag(family)
            }
        }
    }

    private func sizeSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Slider(value: value, in: range, step: 1) {
                Text(title)
            }
            Text("\(Int(value.wrappedValue)) pt")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}
