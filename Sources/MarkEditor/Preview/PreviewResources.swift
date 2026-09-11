import Foundation

/// The preview's stylesheet and script, kept as plain files next to the code
/// (Preview/preview.css and Preview/preview.js). The app carries them in
/// Contents/Resources, copied by Scripts/build-app.sh; tests and `swift run`
/// read them from the package's resource bundle.
enum PreviewResources {
    static func text(named name: String, extension ext: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext)
                ?? Bundle.module.url(forResource: name, withExtension: ext),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            Log.preview.fault("Missing preview resource \(name, privacy: .public).\(ext, privacy: .public)")
            return ""
        }
        // The files end with a newline; the page templates add their own.
        return text.hasSuffix("\n") ? String(text.dropLast()) : text
    }
}
