import AppKit

enum SettingsKeys {
    static let editorFontName = "editorFontName"
    static let editorFontSize = "editorFontSize"
    static let previewFontName = "previewFontName"
    static let previewFontSize = "previewFontSize"
    static let previewLineHeight = "previewLineHeight"
    static let appearanceMode = "appearanceMode"
    static let previewWidthLevel = "previewWidthLevel"
    static let lastViewMode = "lastViewMode"
}

/// Content-column width for the preview in full-preview mode (⌘3).
enum PreviewWidth: Int, CaseIterable, Identifiable {
    case normal
    case medium
    case wide

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .medium: return "Médio"
        case .wide: return "Amplo"
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

enum SettingsDefaults {
    static let editorFontName = FontOption.systemMono
    static let editorFontSize = 14.0
    static let previewFontName = FontOption.systemSans
    static let previewFontSize = 16.0
    static let previewLineHeight = 1.65
    static let appearanceMode = AppearanceMode.light.rawValue
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case light
    case dark
    case auto

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "Claro"
        case .dark: return "Escuro"
        case .auto: return "Automático"
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
        let raw = UserDefaults.standard.string(forKey: SettingsKeys.appearanceMode)
            ?? SettingsDefaults.appearanceMode
        return AppearanceMode(rawValue: raw) ?? .light
    }
}

/// Font identifiers stored in settings. Besides real family names, three
/// sentinel values map to the system fonts so defaults work on any Mac.
enum FontOption {
    static let systemSans = "system-sans"
    static let systemSerif = "system-serif"
    static let systemMono = "system-mono"

    static let specialOptions: [(id: String, label: String)] = [
        (systemSans, "Sistema (Sans)"),
        (systemSerif, "Sistema (Serif)"),
        (systemMono, "Sistema (Mono)"),
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
