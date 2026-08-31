import Foundation

enum PreviewTemplate {
    static let html = """
    <!DOCTYPE html>
    <html lang="pt-BR">
    <head>
    <meta charset="utf-8">
    <style>
    :root {
        --pfont: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
        --psize: 16px;
        --plh: 1.65;
    }
    * { box-sizing: border-box; }
    html { background: #ffffff; }
    body {
        margin: 0;
        font-family: var(--pfont);
        font-size: var(--psize);
        line-height: var(--plh);
        color: #1d1d1f;
        -webkit-font-smoothing: antialiased;
        text-rendering: optimizeLegibility;
        word-wrap: break-word;
    }
    article {
        max-width: 46rem;
        margin: 0 auto;
        padding: 3rem 2.75rem 6rem;
    }
    h1, h2, h3, h4, h5, h6 {
        line-height: 1.25;
        font-weight: 700;
        margin: 1.75em 0 0.6em;
        letter-spacing: -0.015em;
    }
    h1 { font-size: 2em; margin-top: 0.5em; padding-bottom: 0.35em; border-bottom: 1px solid #e8e8ed; }
    h2 { font-size: 1.5em; padding-bottom: 0.25em; border-bottom: 1px solid #efeff4; }
    h3 { font-size: 1.2em; }
    h4 { font-size: 1.05em; }
    h5, h6 { font-size: 1em; }
    h6 { color: #6e6e73; }
    p { margin: 0.9em 0; }
    a { color: #0969da; text-decoration: none; }
    a:hover { text-decoration: underline; }
    strong { font-weight: 650; }
    code {
        font-family: ui-monospace, "SF Mono", Menlo, monospace;
        font-size: 0.875em;
        background: #f6f8fa;
        padding: 0.15em 0.4em;
        border-radius: 4px;
    }
    pre {
        background: #f6f8fa;
        border: 1px solid #eaeef2;
        border-radius: 8px;
        padding: 1rem 1.25rem;
        overflow-x: auto;
        line-height: 1.5;
    }
    pre code { background: none; padding: 0; font-size: 0.85em; }
    blockquote {
        margin: 1.2em 0;
        padding: 0.1em 1.25em;
        border-left: 3px solid #d0d7de;
        color: #57606a;
    }
    ul, ol { padding-left: 1.6em; margin: 0.9em 0; }
    li { margin: 0.25em 0; }
    li > p { margin: 0.35em 0; }
    li.task { list-style: none; margin-left: -1.4em; }
    li.task input[type="checkbox"] { margin-right: 0.45em; vertical-align: -0.1em; accent-color: #0969da; }
    table {
        border-collapse: collapse;
        width: 100%;
        margin: 1.2em 0;
        font-size: 0.95em;
    }
    th, td { border: 1px solid #d8dee4; padding: 0.45em 0.8em; }
    th { background: #f6f8fa; font-weight: 650; }
    tbody tr:nth-child(even) { background: #fbfcfd; }
    hr { border: none; border-top: 1px solid #d8dee4; margin: 2.5rem auto; }
    img { max-width: 100%; border-radius: 6px; }
    ::selection { background: #b6d7ff; }
    </style>
    </head>
    <body>
    <article id="content"></article>
    <script>
    // Timestamp of the last programmatic change; scroll events shortly after
    // one are echoes (or reflows), not the user scrolling the preview.
    let suppressScrollEventsUntil = 0;

    function setContent(html) {
        suppressScrollEventsUntil = Date.now() + 200;
        document.getElementById("content").innerHTML = html;
    }
    function setStyle(family, size, lineHeight) {
        const style = document.documentElement.style;
        style.setProperty("--pfont", family);
        style.setProperty("--psize", size + "px");
        style.setProperty("--plh", lineHeight);
    }
    function setScrollFraction(fraction) {
        const max = document.documentElement.scrollHeight - window.innerHeight;
        if (max <= 0) { return; }
        const target = fraction * max;
        if (Math.abs(target - window.scrollY) < 2) { return; }
        suppressScrollEventsUntil = Date.now() + 200;
        window.scrollTo(0, target);
    }
    window.addEventListener("scroll", () => {
        if (Date.now() < suppressScrollEventsUntil) { return; }
        const max = document.documentElement.scrollHeight - window.innerHeight;
        const fraction = max > 0 ? Math.min(Math.max(window.scrollY / max, 0), 1) : 0;
        window.webkit.messageHandlers.previewScrolled.postMessage(fraction);
    }, { passive: true });
    </script>
    </body>
    </html>
    """
}
