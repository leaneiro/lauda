import Foundation

enum PreviewTemplate {
    /// UI language, used as the page's lang (hyphenation, CJK font choice).
    static let languageTag = Bundle.main.preferredLocalizations.first ?? "en"

    /// Stylesheet shared by the live preview and exported documents
    /// (Preview/preview.css), after the wordmark's @font-face.
    static let styles = wordmarkFontFace + "\n" + PreviewResources.text(named: "preview", extension: "css")

    /// The face behind the `.wordmark` class: Newsreader SemiBold at the
    /// 72 pt optical size, the typeface of the app icon's L, cut down to the
    /// letters of "Lauda" (Preview/LaudaWordmark.woff, SIL Open Font
    /// License). Embedded as a data URI, so the preview, exported HTML and
    /// PDF all have it without fetching anything.
    static let wordmarkFontFace: String = {
        guard let font = PreviewResources.data(named: "LaudaWordmark", extension: "woff") else { return "" }
        return """
        @font-face {
            font-family: "Lauda Wordmark";
            src: url("data:font/woff;base64,\(font.base64EncodedString())") format("woff");
            font-weight: 600;
            font-display: block;
        }
        """
    }()

    /// Content Security Policy of the live preview. The document's raw HTML
    /// can't run script (tags, inline handlers, javascript: URLs) or open
    /// connections. Images and media may come from the document's folder,
    /// data: URIs or the web, and https embeds (iframes) still load. Fonts
    /// only come from data: URIs, which is how the wordmark face is
    /// embedded, so nothing is fetched for them. The
    /// app's own script runs in a separate content world, outside this policy.
    static let previewContentSecurityPolicy = [
        "default-src 'none'",
        "img-src \(DocumentSchemeHandler.scheme): data: https: http:",
        "media-src \(DocumentSchemeHandler.scheme): data: https: http:",
        "style-src 'unsafe-inline'",
        "font-src data:",
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
