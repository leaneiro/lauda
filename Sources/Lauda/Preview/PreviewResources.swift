import Foundation

/// The preview's stylesheet, script and wordmark font, kept as plain files
/// next to the code (Preview/). The app carries them in Contents/Resources,
/// copied by Scripts/build-app.sh; tests and `swift run` read them from the
/// package's resource bundle.
enum PreviewResources {
    static func text(named name: String, extension ext: String) -> String {
        guard let data = data(named: name, extension: ext),
              let text = String(data: data, encoding: .utf8) else { return "" }
        // The files end with a newline; the page templates add their own.
        return text.hasSuffix("\n") ? String(text.dropLast()) : text
    }

    static func data(named name: String, extension ext: String) -> Data? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext)
                ?? Bundle.module.url(forResource: name, withExtension: ext),
              let data = try? Data(contentsOf: url) else {
            Log.preview.fault("Missing preview resource \(name, privacy: .public).\(ext, privacy: .public)")
            return nil
        }
        return data
    }
}
