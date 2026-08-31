import AppKit

enum SettingsKeys {
    static let editorFontName = "editorFontName"
    static let editorFontSize = "editorFontSize"
    static let previewFontName = "previewFontName"
    static let previewFontSize = "previewFontSize"
    static let previewLineHeight = "previewLineHeight"
}

enum SettingsDefaults {
    static let editorFontName = FontOption.systemMono
    static let editorFontSize = 14.0
    static let previewFontName = FontOption.systemSans
    static let previewFontSize = 16.0
    static let previewLineHeight = 1.65
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
