// Timestamp of the last programmatic change; scroll events shortly after
// one are echoes (or reflows), not the user scrolling the preview.
let suppressScrollEventsUntil = 0;

// Block-level DOM diff: only blocks that actually changed are replaced,
// so typing repaints one paragraph instead of relaying the whole page.
// Parsing via a detached div's innerHTML keeps <script> tags inert, and
// the page's Content-Security-Policy blocks inline handlers as well.
// Source line where each top-level block starts (parallel to the
// container's children) and the document's line count, so scroll sync
// can align both panes by content instead of by proportion.
let blockLines = [];
let totalLines = 1;

function setContent(html, lines, lineCount) {
    suppressScrollEventsUntil = Date.now() + 200;
    blockLines = lines || [];
    totalLines = Math.max(lineCount || 1, 1);
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
function maxScroll() {
    return Math.max(document.documentElement.scrollHeight - window.innerHeight, 0);
}
// [sourceLine, y] anchors: the top padding (line -1 at y 0), each
// top-level block and the document end. null when the DOM and the line
// map disagree (raw HTML can make the parser split a block); callers
// then fall back to proportional sync.
function lineAnchors() {
    const blocks = document.getElementById("content").children;
    if (blockLines.length === 0 || blocks.length !== blockLines.length) { return null; }
    const points = [[-1, 0]];
    for (let i = 0; i < blocks.length; i++) {
        const y = blocks[i].getBoundingClientRect().top + window.scrollY;
        const prev = points[points.length - 1];
        if (blockLines[i] > prev[0] && y >= prev[1]) { points.push([blockLines[i], y]); }
    }
    const last = points[points.length - 1];
    const endY = document.documentElement.scrollHeight;
    if (totalLines > last[0] && endY >= last[1]) { points.push([totalLines, endY]); }
    return points;
}
// Piecewise-linear lookup over anchors sorted by both columns.
function interpolate(points, value, from, to) {
    if (value <= points[0][from]) { return points[0][to]; }
    for (let i = 1; i < points.length; i++) {
        const a = points[i - 1], b = points[i];
        if (value <= b[from]) {
            const span = b[from] - a[from];
            return span > 0 ? a[to] + (value - a[from]) / span * (b[to] - a[to]) : b[to];
        }
    }
    return points[points.length - 1][to];
}
// Keeps the same source line at the top as the other pane, which also means
// the shorter pane reaches its bottom first.
function setScrollPosition(line, hasLine, fraction) {
    const max = maxScroll();
    if (max <= 0) { return; }
    const points = hasLine ? lineAnchors() : null;
    let target = points ? interpolate(points, line, 0, 1) : fraction * max;
    target = Math.min(Math.max(target, 0), max);
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
    const max = maxScroll();
    const y = window.scrollY;
    const fraction = max > 0 ? Math.min(Math.max(y / max, 0), 1) : 0;
    const points = lineAnchors();
    const line = points ? interpolate(points, y, 1, 0) : null;
    window.webkit.messageHandlers.previewScrolled.postMessage([line, fraction]);
}, { passive: true });
