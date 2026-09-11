import XCTest
@testable import MarkEditor

final class AppSettingsTests: XCTestCase {
    private let suiteName = "AppSettingsTests"
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testUnsetSettingsReadTheirDefaults() {
        XCTAssertEqual(defaults[AppSettings.previewFontSize], 16)
        XCTAssertEqual(
            PreviewStyle.current(in: defaults),
            PreviewStyle(fontName: FontOption.systemSans, fontSize: 16, lineHeight: 1.65, strictLineBreaks: false)
        )
    }

    func testStoredValuesWin() {
        defaults[AppSettings.previewFontSize] = 20
        defaults[AppSettings.strictLineBreaks] = true
        let style = PreviewStyle.current(in: defaults)
        XCTAssertEqual(style.fontSize, 20)
        XCTAssertTrue(style.strictLineBreaks)
    }

    func testRestoreDefaultsResetsPreferencesButKeepsRememberedState() {
        defaults[AppSettings.editorFontSize] = 20
        defaults[AppSettings.appearanceMode] = AppearanceMode.dark.rawValue
        defaults[AppSettings.lastViewMode] = ViewMode.previewOnly.rawValue

        AppSettings.restoreDefaults(in: defaults)

        XCTAssertEqual(defaults[AppSettings.editorFontSize], 14)
        XCTAssertEqual(defaults[AppSettings.appearanceMode], AppearanceMode.light.rawValue)
        XCTAssertEqual(defaults[AppSettings.lastViewMode], ViewMode.previewOnly.rawValue)
    }

    func testEverySettingHasItsOwnKey() {
        let keys = (AppSettings.preferences + AppSettings.rememberedState).map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    func testRegisteredDefaultsAnswerPlainReads() {
        AppSettings.registerDefaults(in: defaults)
        XCTAssertEqual(defaults.double(forKey: AppSettings.previewLineHeight.key), 1.65)
        XCTAssertEqual(defaults.string(forKey: AppSettings.editorFontName.key), FontOption.systemMono)
    }
}
