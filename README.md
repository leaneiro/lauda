# Lauda

A native macOS Markdown editor with a dual-pane layout: you write on the left
and see the rendered Markdown on the right, updated as you type.

## Features

- **Dual pane**: editor on the left, formatted preview on the right, with
  two-way scroll sync and an adjustable divider whose position is remembered.
  Scrolling is aligned by block (heading, paragraph, image, table), so large
  images and tables don't throw the two sides out of step.
- **Instant preview**: renders on every keystroke, with no debounce. A
  block-level DOM diff repaints only what changed.
- **View modes**: editor only (⌘1), split (⌘2) or preview only (⌘3), also
  available from the toolbar. Preview-only mode offers three text widths.
- **Polished preview**: headings, lists, task lists (`- [ ]`), GFM tables,
  code with syntax highlighting for 17 languages, quotes, images and links
  (which open in the browser).
- **Editor highlighting**: light Markdown syntax highlighting while you edit.
- **Export**: standalone HTML with the preview's look (⌥⇧⌘E) and paginated
  PDF (⇧⌘E), from the File menu.
- **Outline**: a toolbar button lists the headings (H1 to H6) and takes both
  panes, and the caret, to the one you pick.
- **Find**: ⌘F works in every view mode, with a match counter.
- **Images**: drag an image into the editor or paste a screenshot. It's
  copied next to the document and the Markdown link is written for you.
- **Welcome guide**: opens on first launch, in the system language, as an
  untitled document to experiment with. Reopen it from Help → Welcome Guide.
- **Languages**: follows the system language. English (the base language) and
  Brazilian Portuguese are reviewed; German, Simplified Chinese, French,
  Japanese and Spanish are drafts awaiting review by native speakers (see
  [CONTRIBUTING.md](CONTRIBUTING.md)).
- **Writing shortcuts**: ⌘B, ⌘I and ⌘K in the Format menu; Return continues
  lists (including task and numbered lists); Tab and Shift-Tab indent items.
- **Small comforts**: pasting a URL over a selection creates `[text](url)`;
  `->` and `<-` become → and ← outside code; the status bar shows the word
  count, reading time and save state.
- **Settings** (⌘,): appearance (automatic, light or dark; automatic by default),
  editor font and size, preview font, size and line height, and strict line
  breaks. By default each Return breaks the line in the preview; in strict
  mode, standard Markdown rules apply.
- **Native documents**: open and save `.md` files, autosave, undo, rename
  from the window title, and recent files.

## Requirements

macOS 14 Sonoma or later. Lauda is built on SwiftUI's document
architecture and on APIs that arrived between macOS 11 and 14: the
document window, menus and settings, `String(localized:)` for the
translations, and the isolated script world that keeps the preview safe.
Supporting older versions would mean rewriting those parts, and macOS 14
already covers every version that still receives security updates.

Building needs Xcode, or the Command Line Tools with Swift 5.10 or later.
Xcode's `xcstringstool` compiles the translations; without it the app
still builds, in English only.

## Building

```bash
make app     # builds build/Lauda.app
make run     # builds and opens the app
make dev     # debug build (swift build)
make dmg     # disk image for distribution
make icon    # rebuilds the app icon from Resources/Icons
make clean
```

Run the tests with `swift test`.

The project is a plain SwiftPM package. `Scripts/build-app.sh` assembles the
`.app` bundle from the executable and `Support/Info.plist` and signs it ad
hoc. You can also open the folder in Xcode and run the `Lauda` target.

## Project layout

```
Sources/Lauda/
  App/                       # app entry, menus, menu-to-window bridges
  Window/                    # document window: split view, toolbar, find bar
  Document/                  # Markdown document, recent files, welcome guide
  Editor/                    # NSTextView editor: highlighting, lists, formatting, find, images
  Preview/                   # WKWebView, HTML renderer, preview.css and preview.js
  Sync/                      # scroll position shared by the two panes
  Export/                    # HTML and PDF export
  Settings/                  # settings model and Settings window
  Outline.swift              # document outline
Resources/                   # string catalogs, welcome guides, icons
Support/Info.plist           # document types and bundle metadata
Scripts/                     # .app, DMG and icon builds
Tests/LaudaTests/       # unit tests
```

## Contributing

Translations are the easiest way to help. See [CONTRIBUTING.md](CONTRIBUTING.md)
for how to review a language, add a new one and test it.

## License

Lauda is released under the MIT License. See [LICENSE](LICENSE).
