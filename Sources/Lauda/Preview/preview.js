"use strict";
// How long scroll events are taken as echoes of something the app did
// rather than the reader scrolling: after a change of content or position,
// and longer after a reflow, which settles in more than one frame.
const ECHO_WINDOW_MS = 200;
const REFLOW_ECHO_WINDOW_MS = 300;

// Timestamp of the last programmatic change; scroll events shortly after
// one are echoes (or reflows), not the user scrolling the preview.
let suppressScrollEventsUntil = 0;

// Where the page should stay when its text reflows (a narrower or wider pane,
// the column width, the font): the arguments of the last setScrollPosition
// call, the line the reader scrolled to here, or { atEnd: true }. The browser
// keeps the pixel offset instead, which by then shows another line.
let lastPosition = null;

// Block-level DOM diff: only blocks that actually changed are replaced,
// so typing repaints one paragraph instead of relaying the whole page.
// Parsing via a detached div's innerHTML keeps <script> tags inert, and
// the page's Content-Security-Policy blocks inline handlers as well.
// Source line of each element the scroll sync anchors on (parallel to
// anchorElements()) and the document's line count, so scroll sync can
// align both panes by content instead of by proportion.
let anchorLines = [];
let totalLines = 1;

function setContent(html, lines, lineCount) {
    suppressScrollEventsUntil = Date.now() + ECHO_WINDOW_MS;
    anchorsMoved();
    anchorLines = lines || [];
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
    reflowing(() => {
        const style = document.documentElement.style;
        style.setProperty("--pfont", family);
        style.setProperty("--psize", `${size}px`);
        style.setProperty("--plh", lineHeight);
    });
}
function setContentWidth(rem) {
    reflowing(() => {
        document.documentElement.style.setProperty("--article-max", `${rem}rem`);
    });
}
// Applies a change that reflows the text (column width, font) and puts the
// page back at lastPosition. The change applies at once: an animated reflow
// would keep moving the text after the page was put back.
function reflowing(change) {
    if (!lastPosition) {
        rememberTopOfPage();
    }
    suppressScrollEventsUntil = Date.now() + REFLOW_ECHO_WINDOW_MS;
    const root = document.documentElement;
    root.classList.add("reflowing");
    change();
    document.body.getBoundingClientRect(); // lay out the new text now
    anchorsMoved();
    realign();
    root.classList.remove("reflowing");
}
// Takes the current position as lastPosition: the end of the page, or the
// line at the top.
function rememberTopOfPage() {
    const max = maxScroll();
    const y = window.scrollY;
    const points = lineAnchors();
    if (max > 0 && y >= max - 1) {
        lastPosition = { atEnd: true };
    } else if (points) {
        lastPosition = position(interpolate(points, y, 1, 0), null, max > 0 ? y / max : 0, 0, 1);
    }
}
// Puts the page back at lastPosition after its text reflowed.
function realign() {
    if (!lastPosition) { return; }
    if (lastPosition.atEnd) {
        suppressScrollEventsUntil = Date.now() + ECHO_WINDOW_MS;
        window.scrollTo(0, maxScroll());
        return;
    }
    setScrollPosition(lastPosition);
}
function maxScroll() {
    return Math.max(document.documentElement.scrollHeight - window.innerHeight, 0);
}
// Elements the line map names, in its order: every top-level block, then
// the list items and table rows inside it. Anchoring inside blocks keeps
// long lists aligned, where a single <ol> can span hundreds of source
// lines whose heights depend on how each one wraps. Raw HTML maps to no
// source line of ours, so nothing inside it is an anchor.
function anchorElements() {
    const elements = [];
    for (const block of document.getElementById("content").children) {
        elements.push(block);
        if (block.classList.contains("raw")) { continue; }
        for (const inner of block.querySelectorAll("li, tr")) { elements.push(inner); }
    }
    return elements;
}
// The anchors as they were last measured. Measuring walks every block, and
// every list item and table row inside it, reading each one's position, so
// it is done once and kept until something moves the text: new content, a
// reflow, a resize, or an image that finishes loading (the observer below
// catches the last two). Scroll events then cost a lookup rather than a
// pass over the page, which is what a long list made expensive.
let measuredAnchors = { valid: false, points: null, shape: null };

function anchorsMoved() {
    measuredAnchors = { valid: false, points: null, shape: null };
}

// What the anchors were measured against. A reflow the app didn't ask for
// (a late image, a stylesheet) changes one of these, and the anchors are
// measured again before they are read, rather than waiting for the
// observer's turn, which comes after the reader may have scrolled.
function contentShape() {
    const content = document.getElementById("content");
    return `${content.clientWidth}x${document.documentElement.scrollHeight}`;
}

// [sourceLine, y] anchors: the top padding (line -1 at y 0), each mapped
// element and the document end. null when the DOM and the line map
// disagree (raw HTML can make the parser split a block); callers then
// fall back to proportional sync.
function lineAnchors() {
    const shape = contentShape();
    if (measuredAnchors.valid && measuredAnchors.shape === shape) { return measuredAnchors.points; }
    const points = measureLineAnchors();
    measuredAnchors = { valid: true, points, shape };
    return points;
}
function measureLineAnchors() {
    const elements = anchorElements();
    if (anchorLines.length === 0 || elements.length !== anchorLines.length) { return null; }
    const points = [[-1, 0]];
    for (let i = 0; i < elements.length; i++) {
        const y = elements[i].getBoundingClientRect().top + window.scrollY;
        const prev = points[points.length - 1];
        if (anchorLines[i] > prev[0] && y >= prev[1]) { points.push([anchorLines[i], y]); }
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
// Where the other pane is, in this one's terms: `line` and `endLine` are
// source lines, null when the leader can't name one and the fraction is all
// there is to go on.
function position(line, endLine, fraction, toEndDistance, convergence) {
    return { line, endLine, fraction, toEndDistance, convergence };
}
function setScrollPosition(at) {
    lastPosition = at;
    const max = maxScroll();
    if (max <= 0) { return; }
    const points = at.line === null ? null : lineAnchors();
    let target = at.fraction * max;
    if (points) {
        target = interpolate(points, at.line, 0, 1);
        // Over the leader's last `convergence` points, absorb the gap
        // between where its final line lands here and this pane's end, so
        // both panes reach the bottom together while staying line-aligned
        // everywhere before that.
        if (at.endLine !== null) {
            const gap = Math.max(max - interpolate(points, at.endLine, 0, 1), 0);
            const stretch = Math.max(Math.min(at.convergence, window.innerHeight), 1);
            target += gap * Math.max(0, 1 - at.toEndDistance / stretch);
        }
    }
    target = Math.min(Math.max(target, 0), max);
    if (Math.abs(target - window.scrollY) < 2) { return; }
    suppressScrollEventsUntil = Date.now() + ECHO_WINDOW_MS;
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
    findState.marks.forEach((mark, i) => { mark.classList.toggle("current", i === findState.index); });
    if (findState.index >= 0) {
        suppressScrollEventsUntil = Date.now() + ECHO_WINDOW_MS;
        findState.marks[findState.index].scrollIntoView({ block: "center" });
    }
    return { current: findState.index + 1, total: findState.marks.length };
}
// A resize (a view mode switch, the divider, the window) reflows the text:
// stay at lastPosition, and don't report the drifted offsets as the reader
// scrolling.
window.addEventListener("resize", () => {
    suppressScrollEventsUntil = Date.now() + REFLOW_ECHO_WINDOW_MS;
    anchorsMoved();
    realign();
});
// Where the page is, for the editor to follow. WebKit already paces scroll
// events by the frame, and the anchors are measured once (lineAnchors), so
// an event costs a lookup and the message itself.
function reportScrolled() {
    const max = maxScroll();
    const y = window.scrollY;
    const fraction = max > 0 ? Math.min(Math.max(y / max, 0), 1) : 0;
    const toEndDistance = Math.max(max - y, 0);
    const points = lineAnchors();
    const line = points ? interpolate(points, y, 1, 0) : null;
    const endLine = points ? interpolate(points, max, 1, 0) : null;
    lastPosition = max > 0 && y >= max - 1 ? { atEnd: true } : position(line, null, fraction, 0, 1);
    window.webkit.messageHandlers.previewScrolled.postMessage({ line, endLine, fraction, toEndDistance });
}
window.addEventListener("scroll", () => {
    if (Date.now() < suppressScrollEventsUntil) { return; }
    reportScrolled();
}, { passive: true });

// The content grows on its own when an image finishes loading, and the
// anchors below it move with it. Watching its box catches that, and the
// reflows a stylesheet can cause without any of the calls above.
new ResizeObserver(() => { anchorsMoved(); }).observe(document.getElementById("content"));
