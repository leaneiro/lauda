import Foundation

enum PreviewTemplate {
    /// UI language, used as the page's lang (hyphenation, CJK font choice).
    static let languageTag = Bundle.main.preferredLocalizations.first ?? "en"

    /// Stylesheet shared by the live preview and exported documents
    /// (Preview/preview.css).
    static let styles = PreviewResources.text(named: "preview", extension: "css")

    /// Content Security Policy of the live preview. The document's raw HTML
    /// can't run script (tags, inline handlers, javascript: URLs) or open
    /// connections. Images and media may come from the document's folder,
    /// data: URIs or the web, and https embeds (iframes) still load. The
    /// app's own script runs in a separate content world, outside this policy.
    static let previewContentSecurityPolicy = [
        "default-src 'none'",
        "img-src \(DocumentSchemeHandler.scheme): data: https: http:",
        "media-src \(DocumentSchemeHandler.scheme): data: https: http:",
        "style-src 'unsafe-inline'",
        "frame-src https:",
        "base-uri 'none'",
        "form-action 'none'",
    ].joined(separator: "; ")

    /// Exported documents load whatever the document references but, like the
    /// preview, never run its scripts.
    static let exportContentSecurityPolicy =
        "script-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"

    /// Page for the live preview. It carries no script of its own: `script`
    /// is injected into `PreviewWebView.contentWorld`.
    static let html = """
    <!DOCTYPE html>
    <html lang="\(PreviewTemplate.languageTag)">
    <head>
    <meta charset="utf-8">
    <meta http-equiv="Content-Security-Policy" content="\(previewContentSecurityPolicy)">
    <style>
    \(styles)
    </style>
    </head>
    <body>
    <article id="content"></article>
    </body>
    </html>
    """

    /// The preview's script (Preview/preview.js). It runs in its own content
    /// world, so the document's raw HTML, which shares the page, can't see or
    /// replace it.
    static let script = PreviewResources.text(named: "preview", extension: "js")

    /// Self-contained document (no scripts) for HTML/PDF export, styled like
    /// the preview and honoring the user's preview font settings.
    static func standalone(
        title: String,
        bodyHTML: String,
        fontFamily: String,
        fontSize: Double,
        lineHeight: Double
    ) -> String {
        """
        <!DOCTYPE html>
        <html lang="\(PreviewTemplate.languageTag)">
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(exportContentSecurityPolicy)">
        <title>\(HTMLRenderer.escape(title))</title>
        <style>
        \(styles)
        :root {
            --pfont: \(fontFamily);
            --psize: \(fontSize)px;
            --plh: \(lineHeight);
        }
        </style>
        </head>
        <body>
        <article id="content">
        \(bodyHTML)
        </article>
        </body>
        </html>
        """
    }
}
