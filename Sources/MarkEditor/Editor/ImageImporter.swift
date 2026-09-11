import AppKit

/// Brings images into the document's folder so they can be referenced with
/// relative markdown paths (which the preview and exports already resolve).
enum ImageImporter {
    static func isImageFile(_ url: URL) -> Bool {
        ImageFileTypes.isImage(url)
    }

    /// What a paste should insert, decided from the pasteboard's flavors.
    enum PasteIntent: Equatable {
        case imageFiles([URL])
        case imageData(Data)
        case notAnImage
    }

    /// Copying a file in the Finder puts the file URL *plus* the file name as
    /// text *plus* the icon as TIFF — so file URLs must win over both text and
    /// raw data. Raw image data only counts when there's no text, which keeps
    /// pasting rich web content (text + images) behaving as text.
    static func pasteIntent(for pasteboard: NSPasteboard) -> PasteIntent {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        let imageFiles = urls.filter {
            isImageFile($0) && FileManager.default.fileExists(atPath: $0.path)
        }
        if !imageFiles.isEmpty {
            return .imageFiles(imageFiles)
        }
        guard pasteboard.string(forType: .string) == nil else { return .notAnImage }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            return .imageData(data)
        }
        return .notAnImage
    }

    /// Copies an image into `directory` (unless it already lives inside it)
    /// and returns the path to reference in markdown, relative to `directory`.
    static func importImage(from source: URL, into directory: URL) -> String? {
        let base = directory.resolvingSymlinksInPath().standardizedFileURL
        let canonicalSource = source.resolvingSymlinksInPath().standardizedFileURL

        // Already inside the document's folder: just reference it.
        if canonicalSource.path == base.path.appending("/").appending(canonicalSource.lastPathComponent)
            || canonicalSource.path.hasPrefix(base.path + "/") {
            return String(canonicalSource.path.dropFirst(base.path.count + 1))
        }

        let destination = uniqueDestination(for: source.lastPathComponent, in: directory)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return destination.lastPathComponent
        } catch {
            return nil
        }
    }

    /// Saves raw image data (e.g. a pasted screenshot) as PNG and returns the
    /// file name.
    static func saveImageData(_ data: Data, in directory: URL, now: Date = Date()) -> String? {
        guard let pngData = pngData(from: data) else { return nil }
        // Fixed POSIX locale so the timestamp is always Western digits and the
        // Gregorian calendar, whatever the user's region.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: now)
        let name = String(
            localized: "image-\(timestamp).png",
            comment: "File name for a pasted screenshot; keep the timestamp placeholder."
        )
        let destination = uniqueDestination(for: name, in: directory)
        do {
            try pngData.write(to: destination)
            return destination.lastPathComponent
        } catch {
            return nil
        }
    }

    /// Appends -2, -3… before the extension when the name is taken.
    static func uniqueDestination(for name: String, in directory: URL) -> URL {
        let baseName = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = directory.appendingPathComponent(name)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(baseName)-\(counter)" : "\(baseName)-\(counter).\(ext)"
            candidate = directory.appendingPathComponent(numbered)
            counter += 1
        }
        return candidate
    }

    /// Markdown for a list of relative paths, percent-encoding what URLs need.
    static func markdown(forRelativePaths paths: [String]) -> String {
        paths.map { path in
            let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
            return "![](\(encoded))"
        }
        .joined(separator: "\n\n")
    }

    private static func pngData(from data: Data) -> Data? {
        guard let representation = NSBitmapImageRep(data: data) else { return nil }
        return representation.representation(using: .png, properties: [:])
    }
}
