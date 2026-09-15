# Contributing to Lauda

Thanks for your interest in helping! Translations are the easiest way to
contribute, and they make a real difference for everyone using the app in
your language.

## Translations

Lauda follows the macOS system language, with English as the base
language.

| Language | Status |
|---|---|
| English | Base language |
| Portuguese (Brazil) | Reviewed |
| Chinese (Simplified) | Draft, needs review |
| French | Draft, needs review |
| German | Draft, needs review |
| Japanese | Draft, needs review |
| Spanish | Draft, needs review |

The drafts were machine-generated and haven't been checked by a native
speaker yet. They already ship in the app, so even a partial review helps.

### Where the strings live

- `Resources/Localizable.xcstrings`: all interface text (about 60 short
  strings).
- `Resources/InfoPlist.xcstrings`: the document type name shown in Finder.

Both are Apple String Catalogs. Xcode opens them in a table editor, and any
text editor works too, since they're JSON.

### Reviewing a draft

1. Open `Resources/Localizable.xcstrings` in Xcode and pick your language.
   Strings waiting for review are marked **Needs Review**.
2. Fix anything that reads wrong or unnatural, then mark the string as
   reviewed from Xcode's context menu. In a text editor, change
   `"state" : "needs_review"` to `"state" : "translated"`.
3. Do the same for `Resources/InfoPlist.xcstrings`.
4. Open a pull request. Reviewing part of a language is welcome too.

Guidelines:

- Use the terms macOS itself uses in your language (the Find commands in
  the Edit menu, "Save", "Preview" and so on), so the app feels native.
- Keep placeholders such as `%@` and `%lld`. You may reorder them if your
  grammar needs it.
- Plural strings (`%lld words`, `%lld characters`) have one entry per
  plural category of your language. Fill in the ones your language uses.
- Keep the pasted-image file name (`image-%@.png`) in ASCII letters, since
  it ends up inside Markdown links.

### Welcome guide

Each language also has a welcome document, shown on first launch and from
Help → Welcome Guide: `Resources/Welcome/<language>.lproj/Welcome.md`. The
versions other than English and Portuguese are machine drafts too. Review
them like the strings, and keep the Markdown structure (headings, lists,
the code block and the table), since the guide demonstrates each feature.
Keep the app's name wrapped in `<span class="wordmark">Lauda</span>`: the
preview sets it in the typeface of the app icon.

### Adding a new language

In Xcode's catalog editor, add the language (the + button) to both
catalogs and translate. Then add a translated
`Resources/Welcome/<language>.lproj/Welcome.md`, add the language code to
`CFBundleLocalizations` in `Support/Info.plist`, and add a row to the
table above.

### Testing

Building needs Xcode, whose `xcstringstool` compiles the catalogs into the
app (without it, the app builds but runs in English only). Build, then open
the app in a given language, such as `de`, `es`, `fr`, `ja`, `zh-Hans` or
`pt-BR`:

```bash
make app
open build/Lauda.app --args -AppleLanguages "(de)"
```

Check the menus, the Settings window (⌘,) and the status bar at the bottom
of a document window, and open Help → Welcome Guide to read the guide in
that language. Quit the app before switching languages, since `--args`
only applies to a fresh launch. You can also set a per-app language in
System Settings → General → Language & Region → Applications.

## Working on the code

Lauda is a plain SwiftPM package, with no Xcode project. `make run`
builds and opens the app, and `swift test` runs the unit tests. For every
pull request, CI builds the package, runs the tests and assembles the
universal app bundle on Apple silicon, then builds and tests again on an
Intel Mac.

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/),
for example `fix(preview): …` or `feat(editor): …`.

### Tests

Tests use [Swift Testing](https://developer.apple.com/documentation/testing)
(`@Test`, `#expect`, `#require`). It runs tests in parallel and in no
particular order, so each one has to stand on its own. A test that writes
settings makes its own `UserDefaults` suite, and a test that touches the
disk makes its own temporary folder, both named with a fresh UUID and
cleaned up when the test ends. Never write to `UserDefaults.standard`:
those are the real settings of whoever is running the tests.

Suites that drive AppKit are marked `@MainActor`. Two of them are also
`@Suite(.serialized)`, so their tests run one at a time: `UndoGranularityTests`,
which pumps the runloop while NSTextView coalesces undo by timing, and
`PDFExportTests`, which drives WebKit printing.

### Settings and logs

- Every stored setting is declared once in `AppSettings`, with its key and
  default. Views bind to it with `@AppStorage(AppSettings.…)`, and other
  code reads `UserDefaults.standard[AppSettings.…]`.
- Failures worth diagnosing go to the system log through `Log`
  (`os.Logger`, subsystem `com.carneirolabs.lauda`). Never log document
  text or file names: people may attach these logs to public bug reports.

### The editor uses TextKit 1 on purpose

`MarkdownTextView` builds its own TextKit 1 stack. TextKit 2 lays text out
by estimated viewport, and together with the per-keystroke syntax
highlighting that made scrolling jump and left blank regions. Scroll sync
between the panes also relies on exact line positions. Please don't switch
to TextKit 2 without carefully testing long documents and scroll sync.

### Writing Tools keeps Markdown intact

macOS 15 and later add Writing Tools (Proofread, Rewrite) to the editor's
context menu on its own, with no code on our side. The one thing the editor
does set is `allowedWritingToolsResultOptions = .plainText`. Left on the
system default, a rewrite may come back as an attributed string: Writing
Tools reads `**bold**` as bold, applies it as a text attribute and drops
the asterisks, which this plain-text view then throws away, so the emphasis
is lost. Asking for plain text keeps the document's own Markdown, code
fences included. Don't remove that line.

### Preview files

The preview's stylesheet and script are plain files:
`Sources/Lauda/Preview/preview.css` and `preview.js`. `PreviewTemplate`
loads them, `Scripts/build-app.sh` copies them into the app, and tests read
them from the package's resource bundle.

`LaudaWordmark.woff`, next to them, is Newsreader SemiBold at the 72 pt
optical size, the typeface of the icon's L, cut down to the letters of
"Lauda". `PreviewTemplate` embeds it as a data URI for the `.wordmark`
class, so it also travels inside exported HTML and PDF. The font is under
the SIL Open Font License (`Newsreader-OFL.txt`), and
`Scripts/make-wordmark-font.sh` regenerates it from the Newsreader variable
font (it needs fontTools).

### Preview security

The preview renders the document's raw HTML, and documents can come from
anyone. Keep these protections in place:

- The page's Content-Security-Policy (`PreviewTemplate`) blocks any script
  in the document and any connection it could open. Images and media may
  still load from the document's folder, `data:` URIs and the web.
- The app's own script runs in a separate content world
  (`PreviewWebView.contentWorld`). Call it with
  `callAsyncJavaScript(…, in: PreviewWebView.contentWorld)`, never `.page`.
- `HTMLRenderer` only keeps links that are relative or use `http`, `https`
  or `mailto` (`ExternalLinks`).
- `DocumentSchemeHandler` serves only image files inside the document's
  folder, with symlinks resolved.

If a change needs to loosen any of these, please open an issue first.
