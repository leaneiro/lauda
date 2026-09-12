import Foundation

/// File extensions the app treats as images: dropped or pasted into the
/// editor, and served to the preview from the document's folder.
enum ImageFileTypes {
    static let extensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "tif", "heic", "avif", "svg", "ico",
    ]

    static func isImage(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }
}

/// Link schemes allowed to leave the app: the renderer keeps them, clicks in
/// the preview open them in the browser, and pasting one over a selection
/// makes a link.
enum ExternalLinks {
    static let allowedSchemes: Set<String> = ["http", "https", "mailto"]
}
