import Foundation

enum PreviewTemplate {
    /// Stylesheet shared by the live preview and exported documents.
    static let styles = """
    :root {
        --pfont: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
        --psize: 16px;
        --plh: 1.65;

        --bg: #ffffff;
        --fg: #1d1d1f;
        --muted: #57606a;
        --faint: #6e6e73;
        --rule-strong: #e8e8ed;
        --rule-soft: #efeff4;
        --border: #d8dee4;
        --code-bg: #f6f8fa;
        --code-border: #eaeef2;
        --link: #0969da;
        --selection: #b6d7ff;
        --row-even: #fbfcfd;
        --quote-border: #d0d7de;
    }
    @media (prefers-color-scheme: dark) {
        :root {
            --bg: #1e1e21;
            --fg: #e6e6e9;
            --muted: #a0a5ad;
            --faint: #86868b;
            --rule-strong: #333338;
            --rule-soft: #2b2b30;
            --border: #3a3a41;
            --code-bg: #2a2a30;
            --code-border: #35353c;
            --link: #6cb2ff;
            --selection: #3b5b80;
            --row-even: #232327;
            --quote-border: #47474f;
        }
    }
    * { box-sizing: border-box; }
    html { background: var(--bg); }
    body {
        margin: 0;
        background: var(--bg);
        font-family: var(--pfont);
        font-size: var(--psize);
        line-height: var(--plh);
        color: var(--fg);
        -webkit-font-smoothing: antialiased;
        text-rendering: optimizeLegibility;
        word-wrap: break-word;
    }
    article {
        max-width: var(--article-max, 46rem);
        margin: 0 auto;
        padding: 3rem 2.75rem 6rem;
        transition: max-width 0.25s ease;
    }
    h1, h2, h3, h4, h5, h6 {
        line-height: 1.25;
        font-weight: 700;
        margin: 1.75em 0 0.6em;
        letter-spacing: -0.015em;
    }
    h1 { font-size: 2em; margin-top: 0.5em; padding-bottom: 0.35em; border-bottom: 1px solid var(--rule-strong); }
    h2 { font-size: 1.5em; padding-bottom: 0.25em; border-bottom: 1px solid var(--rule-soft); }
    h3 { font-size: 1.2em; }
    h4 { font-size: 1.05em; }
    h5, h6 { font-size: 1em; }
    h6 { color: var(--faint); }
    p { margin: 0.9em 0; }
    a { color: var(--link); text-decoration: none; }
    a:hover { text-decoration: underline; }
    strong { font-weight: 650; }
    code {
        font-family: ui-monospace, "SF Mono", Menlo, monospace;
        font-size: 0.875em;
        background: var(--code-bg);
        padding: 0.15em 0.4em;
        border-radius: 4px;
    }
    pre {
        background: var(--code-bg);
        border: 1px solid var(--code-border);
        border-radius: 8px;
        padding: 1rem 1.25rem;
        overflow-x: auto;
        line-height: 1.5;
    }
    pre code { background: none; padding: 0; font-size: 0.85em; }
    blockquote {
        margin: 1.2em 0;
        padding: 0.1em 1.25em;
        border-left: 3px solid var(--quote-border);
        color: var(--muted);
    }
    ul, ol { padding-left: 1.6em; margin: 0.9em 0; }
    li { margin: 0.25em 0; }
    li > p { margin: 0.35em 0; }
    li.task { list-style: none; margin-left: -1.4em; }
    li.task input[type="checkbox"] { margin-right: 0.45em; vertical-align: -0.1em; accent-color: var(--link); }
    table {
        border-collapse: collapse;
        width: 100%;
        margin: 1.2em 0;
        font-size: 0.95em;
    }
    th, td { border: 1px solid var(--border); padding: 0.45em 0.8em; }
    th { background: var(--code-bg); font-weight: 650; }
    tbody tr:nth-child(even) { background: var(--row-even); }
    hr { border: none; border-top: 1px solid var(--border); margin: 2.5rem auto; }
    img { max-width: 100%; border-radius: 6px; }
    ::selection { background: var(--selection); }
    mark.find-hit { background: rgba(255, 214, 10, 0.30); color: inherit; border-radius: 2px; padding: 0; }
    mark.find-hit.current { background: #ff9f0a; color: #1d1d1f; }
    @media print {
        body { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        article { max-width: none; padding: 0; }
        pre { white-space: pre-wrap; word-break: break-word; overflow-x: visible; }
        pre, table, blockquote, img { break-inside: avoid; }
        h1, h2, h3, h4 { break-after: avoid; }
        p { orphans: 3; widows: 3; }
        /* Keep-with-next: the probe reserves ~2.5 lines below the heading
           inside an unbreakable wrapper; the negative margin gives the space
           back so following content flows normally. */
        .keep-with-next { break-inside: avoid; margin-bottom: -4rem; }
        .keep-with-next .keep-probe { height: 4rem; }
        a { color: inherit; text-decoration: underline; }
    }
    """

    static let html = """
    <!DOCTYPE html>
    <html lang="pt-BR">
    <head>
    <meta charset="utf-8">
    <style>
    \(styles)
    </style>
    </head>
    <body>
    <article id="content"></article>
    <script>
    // Timestamp of the last programmatic change; scroll events shortly after
    // one are echoes (or reflows), not the user scrolling the preview.
    let suppressScrollEventsUntil = 0;

    // Block-level DOM diff: only blocks that actually changed are replaced,
    // so typing repaints one paragraph instead of relaying the whole page.
    // Parsing via a detached div's innerHTML keeps <script> tags inert.
    function setContent(html) {
        suppressScrollEventsUntil = Date.now() + 200;
        const container = document.getElementById("content");
        const parsed = document.createElement("div");
        parsed.innerHTML = html;

        const oldBlocks = Array.from(container.children);
        const newBlocks = Array.from(parsed.children);
        const common = Math.min(oldBlocks.length, newBlocks.length);
        for (let i = 0; i < common; i++) {
            if (!oldBlocks[i].isEqualNode(newBlocks[i])) {
                container.replaceChild(newBlocks[i], oldBlocks[i]);
            }
        }
        for (let i = oldBlocks.length - 1; i >= common; i--) {
            container.removeChild(oldBlocks[i]);
        }
        for (let i = common; i < newBlocks.length; i++) {
            container.appendChild(newBlocks[i]);
        }
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
    // In-page find: wraps matches in <mark> so we can count and step through.
    let findState = { query: "", marks: [], index: -1 };
    function findClear() {
        for (const mark of findState.marks) {
            const parent = mark.parentNode;
            if (parent) {
                parent.replaceChild(document.createTextNode(mark.textContent), mark);
                parent.normalize();
            }
        }
        findState = { query: "", marks: [], index: -1 };
    }
    function findRun(query, forward, restart) {
        if (restart || query !== findState.query) {
            findClear();
            findState.query = query;
            if (!query) { return [0, 0]; }
            const lowered = query.toLowerCase();
            const walker = document.createTreeWalker(
                document.getElementById("content"), NodeFilter.SHOW_TEXT);
            const nodes = [];
            while (walker.nextNode()) { nodes.push(walker.currentNode); }
            for (const node of nodes) {
                let current = node;
                let position;
                while ((position = current.textContent.toLowerCase().indexOf(lowered)) !== -1) {
                    const match = current.splitText(position);
                    const rest = match.splitText(query.length);
                    const mark = document.createElement("mark");
                    mark.className = "find-hit";
                    match.parentNode.replaceChild(mark, match);
                    mark.appendChild(match);
                    findState.marks.push(mark);
                    current = rest;
                }
            }
            findState.index = findState.marks.length ? 0 : -1;
        } else if (findState.marks.length) {
            findState.index = (findState.index + (forward ? 1 : -1) + findState.marks.length)
                % findState.marks.length;
        }
        findState.marks.forEach((mark, i) => mark.classList.toggle("current", i === findState.index));
        if (findState.index >= 0) {
            suppressScrollEventsUntil = Date.now() + 200;
            findState.marks[findState.index].scrollIntoView({ block: "center" });
        }
        return [findState.index + 1, findState.marks.length];
    }
    // Resizes re-flow content and can fire scroll events with drifted
    // positions — those are not the user scrolling.
    window.addEventListener("resize", () => {
        suppressScrollEventsUntil = Date.now() + 300;
    });
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
        <html lang="pt-BR">
        <head>
        <meta charset="utf-8">
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
