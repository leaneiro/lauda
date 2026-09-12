import Foundation
import Testing
@testable import Lauda

/// Each test gets its own UserDefaults suite, so they can run in parallel
/// and in any order without writing over each other (or over the real app's
/// settings on this Mac).
final class AppSettingsTests {
    private let suiteName = "AppSettingsTests-\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    @Test func unsetSettingsReadTheirDefaults() {
        #expect(defaults[AppSettings.previewFontSize] == 16)
        #expect(PreviewStyle.current(in: defaults)
            == PreviewStyle(fontName: FontOption.systemSans, fontSize: 16, lineHeight: 1.65, strictLineBreaks: false))
    }

    @Test func storedValuesWin() {
        defaults[AppSettings.previewFontSize] = 20
        defaults[AppSettings.strictLineBreaks] = true
        let style = PreviewStyle.current(in: defaults)
        #expect(style.fontSize == 20)
        #expect(style.strictLineBreaks)
    }

    @Test func restoreDefaultsResetsPreferencesButKeepsRememberedState() {
        defaults[AppSettings.editorFontSize] = 20
        defaults[AppSettings.appearanceMode] = AppearanceMode.dark.rawValue
        defaults[AppSettings.lastViewMode] = ViewMode.previewOnly.rawValue

        AppSettings.restoreDefaults(in: defaults)

        #expect(defaults[AppSettings.editorFontSize] == 14)
        #expect(defaults[AppSettings.appearanceMode] == AppearanceMode.light.rawValue)
        #expect(defaults[AppSettings.lastViewMode] == ViewMode.previewOnly.rawValue)
    }

    @Test func everySettingHasItsOwnKey() {
        let keys = (AppSettings.preferences + AppSettings.rememberedState).map(\.key)
        #expect(Set(keys).count == keys.count)
    }

    @Test func registeredDefaultsAnswerPlainReads() {
        AppSettings.registerDefaults(in: defaults)
        #expect(defaults.double(forKey: AppSettings.previewLineHeight.key) == 1.65)
        #expect(defaults.string(forKey: AppSettings.editorFontName.key) == FontOption.systemMono)
    }
}
