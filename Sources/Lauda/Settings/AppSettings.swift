import AppKit
import SwiftUI

/// One stored setting: its UserDefaults key and its default value.
struct Setting<Value> {
    let key: String
    let defaultValue: Value
}

/// Every setting the app stores, declared once with its key and default.
/// Views bind with `@AppStorage(AppSettings.editorFontSize)`; other code
/// reads `UserDefaults.standard[AppSettings.editorFontSize]`.
enum AppSettings {
    // The Settings window, reset by Restore Defaults.
    static let appearanceMode = Setting(key: "appearanceMode", defaultValue: AppearanceMode.auto.rawValue)
    static let editorFontName = Setting(key: "editorFontName", defaultValue: FontOption.systemMono)
    static let editorFontSize = Setting(key: "editorFontSize", defaultValue: 14.0)
    static let previewFontName = Setting(key: "previewFontName", defaultValue: FontOption.systemSans)
    static let previewFontSize = Setting(key: "previewFontSize", defaultValue: 16.0)
    static let previewLineHeight = Setting(key: "previewLineHeight", defaultValue: 1.65)
    static let strictLineBreaks = Setting(key: "strictLineBreaks", defaultValue: false)

    // Remembered state, which Restore Defaults leaves alone.
    static let lastViewMode = Setting(key: "lastViewMode", defaultValue: ViewMode.split.rawValue)
    static let previewWidthLevel = Setting(key: "previewWidthLevel", defaultValue: PreviewWidth.normal.rawValue)
    static let hasShownWelcomeGuide = Setting(key: "hasShownWelcomeGuide", defaultValue: false)

    /// The options in the Settings window.
    static let preferences: [(key: String, defaultValue: Any)] = [
        entry(appearanceMode), entry(editorFontName), entry(editorFontSize),
        entry(previewFontName), entry(previewFontSize), entry(previewLineHeight),
        entry(strictLineBreaks),
    ]

    static let rememberedState: [(key: String, defaultValue: Any)] = [
        entry(lastViewMode), entry(previewWidthLevel), entry(hasShownWelcomeGuide),
    ]

    private static func entry<Value>(_ setting: Setting<Value>) -> (key: String, defaultValue: Any) {
        (setting.key, setting.defaultValue)
    }

    /// Called at launch, so plain UserDefaults reads see the defaults too.
    static func registerDefaults(in defaults: UserDefaults = .standard) {
        let all = (preferences + rememberedState).map { ($0.key, $0.defaultValue) }
        defaults.register(defaults: Dictionary(uniqueKeysWithValues: all))
    }

    /// Restore Defaults: every preference goes back to its default, and views
    /// bound with @AppStorage update right away.
    static func restoreDefaults(in defaults: UserDefaults = .standard) {
        for preference in preferences {
            defaults.removeObject(forKey: preference.key)
        }
    }
}

extension UserDefaults {
    subscript<Value>(setting: Setting<Value>) -> Value {
        get { object(forKey: setting.key) as? Value ?? setting.defaultValue }
        set { set(newValue, forKey: setting.key) }
    }
}

extension AppStorage where Value == String {
    init(_ setting: Setting<String>) {
        self.init(wrappedValue: setting.defaultValue, setting.key)
    }
}

extension AppStorage where Value == Double {
    init(_ setting: Setting<Double>) {
        self.init(wrappedValue: setting.defaultValue, setting.key)
    }
}

extension AppStorage where Value == Bool {
    init(_ setting: Setting<Bool>) {
        self.init(wrappedValue: setting.defaultValue, setting.key)
    }
}

extension AppStorage where Value == Int {
    init(_ setting: Setting<Int>) {
        self.init(wrappedValue: setting.defaultValue, setting.key)
    }
}

/// How the preview looks, as set in Settings. Exports take one so they
/// match the preview.
struct PreviewStyle: Equatable {
    var fontName: String
    var fontSize: Double
    var lineHeight: Double
    var strictLineBreaks: Bool

    static func current(in defaults: UserDefaults = .standard) -> PreviewStyle {
        PreviewStyle(
            fontName: defaults[AppSettings.previewFontName],
            fontSize: defaults[AppSettings.previewFontSize],
            lineHeight: defaults[AppSettings.previewLineHeight],
            strictLineBreaks: defaults[AppSettings.strictLineBreaks]
        )
    }
}

/// Content-column width for the preview in full-preview mode (⌘3).
enum PreviewWidth: Int, CaseIterable, Identifiable {
    case normal
    case medium
    case wide

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .normal: return String(localized: "Normal")
        case .medium: return String(localized: "Medium")
        case .wide: return String(localized: "Wide")
        }
    }

    var rem: Double {
        switch self {
        case .normal: return 46
        case .medium: return 66
        case .wide: return 90
        }
    }

    var next: PreviewWidth {
        PreviewWidth(rawValue: (rawValue + 1) % Self.allCases.count) ?? .normal
    }
}

/// Listed in the Settings picker in declaration order, Automatic first.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case auto
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        case .auto: return String(localized: "Automatic")
        }
    }

    /// Sets the whole app's appearance; the preview follows via
    /// `prefers-color-scheme` and the editor via semantic NSColors.
    func apply() {
        switch self {
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .auto: NSApp.appearance = nil
        }
    }

    static var stored: AppearanceMode {
        AppearanceMode(rawValue: UserDefaults.standard[AppSettings.appearanceMode]) ?? .auto
    }
}

/// Font identifiers stored in settings. Besides real family names, three
/// sentinel values map to the system fonts so defaults work on any Mac.
enum FontOption {
    static let systemSans = "system-sans"
    static let systemSerif = "system-serif"
    static let systemMono = "system-mono"

    static let specialOptions: [(id: String, label: String)] = [
        (systemSans, String(localized: "System (Sans)")),
        (systemSerif, String(localized: "System (Serif)")),
        (systemMono, String(localized: "System (Mono)")),
    ]

    static let installedFamilies: [String] = NSFontManager.shared
        .availableFontFamilies
        .filter { !$0.hasPrefix(".") }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

    static func nsFont(for id: String, size: CGFloat) -> NSFont {
        switch id {
        case systemMono:
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        case systemSans:
            return .systemFont(ofSize: size)
        case systemSerif:
            let descriptor = NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif)
            return descriptor.flatMap { NSFont(descriptor: $0, size: size) }
                ?? .systemFont(ofSize: size)
        default:
            return NSFont(name: id, size: size)
                ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }

    static func cssFamily(for id: String) -> String {
        switch id {
        case systemSans:
            return #"-apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif"#
        case systemSerif:
            return #"ui-serif, "New York", Georgia, serif"#
        case systemMono:
            return #"ui-monospace, "SF Mono", Menlo, monospace"#
        default:
            return "\"\(id)\", -apple-system, sans-serif"
        }
    }
}
