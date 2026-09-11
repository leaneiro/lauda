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
            Section("General") {
                Picker("Appearance", selection: $appearanceMode) {
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
                fontPicker("Font", selection: $editorFontName)
                sizeSlider("Size", value: $editorFontSize, range: 10...24)
            }

            Section("Preview") {
                fontPicker("Font", selection: $previewFontName)
                sizeSlider("Size", value: $previewFontSize, range: 12...28)
                HStack {
                    Slider(value: $previewLineHeight, in: 1.2...2.2, step: 0.05) {
                        Text("Line height")
                    }
                    Text(previewLineHeight.formatted(.number.precision(.fractionLength(2))))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                Toggle(isOn: $strictLineBreaks) {
                    Text("Strict line breaks")
                    Text("A single Return doesn't break the line, as in standard Markdown.")
                }
            }

            Section {
                Button("Restore Defaults") {
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

    private func fontPicker(_ title: LocalizedStringKey, selection: Binding<String>) -> some View {
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

    private func sizeSlider(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
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
