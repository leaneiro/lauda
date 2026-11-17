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
preview sets it in the typeface of the app icon. Write each paragraph on
one line: by default the preview breaks the line at every Return, so a
paragraph wrapped by hand would show its breaks.

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
builds and opens the app, `swift test` runs the unit tests, and
`Scripts/lint.sh` runs the linters. For every pull request, CI builds the
package, runs the tests, lints and assembles the universal app bundle on
Apple silicon, then builds and tests again on an Intel Mac. Tests run in
parallel, so when the Intel job crashes, the last test its log lists is
not necessarily the one that crashed: look for a suite that started and
never finished, and see `Tests/LaudaTests/TestMachine.swift` for what
that runner can't draw.

The lint catches slips, not style: the Swift here is formatted by hand, so
swift-format's opinions on indentation, blank lines, line length and the
semicolons a scanner uses are off (`.swift-format` and `Scripts/lint.sh`
list what is off and why). The preview's script goes through Biome, with
the rules that don't fit a script called from Swift turned off in
`biome.json`.

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/),
for example `fix(preview): …` or `feat(editor): …`.

### Tests

Tests use [Swift Testing](https://developer.apple.com/documentation/testing)
(`@Test`, `#expect`, `#require`). It runs tests in parallel and in no
particular order, so each one has to stand on its own. A test that writes
settings uses `TestDefaults`, which keeps them in memory: a named suite is
a file in ~/Library/Preferences, and removing the domain leaves the file
behind. A test that touches the disk makes its own temporary folder, named
with a fresh UUID and removed when the test ends. Never write to
`UserDefaults.standard`: those are the real settings of whoever is running
the tests.

Suites that drive AppKit are marked `@MainActor`. Some are also
`@Suite(.serialized)`, so their tests run one at a time: among them
`UndoGranularityTests`, which pumps the runloop while NSTextView coalesces
undo by timing, and the ones that drive a WebKit page: `PDFExportTests`,
`ScrollLinkPanesTests` and the suites in `PreviewReflowTests.swift`.

Tests in `Tests/LaudaTests/EndToEnd` go through the real window: the
workspace with its panes, kept far off every screen, files moved under a
file coordinator as the Finder moves them, and keys sent to the window.
They are for what a test of one type can't see, such as who has the
keyboard or what a save writes. They never use the pasteboard, the real
Trash or a real click: those belong to whoever is at the Mac.

A suite that puts documents in `NSDocumentController.shared`, or keeps a
document's panes drawing in a window while it waits, is declared inside
`OpenDocumentsSuites` (an extension of it), which runs its suites one
after another: closing every tab closes every document in the process,
whichever suite opened it, and panes drawing off screen take frames from
a suite that times a WebKit page.

A scroll sync test checks where the text really is: where the element
that starts the synced line sits (`getBoundingClientRect().top`, as
`offsetOfItem(startingWith:)` in `PreviewReflowTests` measures it), or
which text is at the top of each pane. Comparing the line the preview
reports with the editor's proves nothing: both come from the same
anchors, so they agree even when the anchors are wrong. See a new sync
test fail against the old behaviour before trusting it. Measure on an
everyday document too, such as the welcome guide
(`Resources/Welcome/<language>.lproj/Welcome.md`), not only on one built
for the edge case: a short document goes through other paths than a long
one.

`Scripts/ui-audit.sh [ref]` (or `make ui-audit`) captures every screen of
the app, in light and dark and in two window sizes, from the working tree
and from `ref` (`main` by default), and writes what differs to a folder in
/tmp. A difference is something to read: it has to be one the change
meant. The suite behind it, `UIAuditTests`, only runs when `UI_AUDIT_OUT`
names the folder for the captures, which is the one place a test writes
outside its temporary folder. It needs the screen unlocked.

### Probing the app

What a test or a diagnostic build meets when it looks at the app from
code:

- Events made in code reach SwiftUI's gestures and buttons when sent
  straight to `window.sendEvent`, even with the window off screen and the
  app in the background (host the view in an `NSHostingView` whose
  `acceptsFirstMouse` returns true). Posted with `NSApp.postEvent`, a
  click doesn't drive SwiftUI while the app is inactive.
- Hover can't be simulated: synthetic `mouseEntered` and `mouseMoved`
  events change nothing, so a hover look is checked by eye.
- Liquid Glass is drawn in the order of the views, whatever their
  `zIndex`. A glass view that has to come to the front is drawn after the
  others (see `liftedTabsView` in `WorkspaceTabStrip`).
- Over glass, hierarchical styles such as `.secondary` are drawn vibrant
  and come out paler than expected. `Color(nsColor: .secondaryLabelColor)`
  matches the system's toolbar buttons.
- With the screen locked, a capture of the window comes out blank, but
  `CALayer.presentation()` still answers, so an animation can be read as
  numbers.
- SwiftUI's menu items can't be measured from code: `isEnabled` reads
  false for commands that work, `NSApp.sendAction` finds no action, and
  `performKeyEquivalent(with:)` returns true without any effect to
  observe. Test the function a command calls, and try the menu by hand.
- `cacheDisplay` doesn't capture a WKWebView, which comes out blank.
  `UIAudit` captures the window as the window server composes it.
- The SwiftUI hosting view is flipped: y grows downward from its top
  edge.
- In zsh, `log` is a builtin. Read the app's log with
  `/usr/bin/log show --predicate 'subsystem == "com.carneirolabs.lauda"'`.

### Settings and logs

- Every stored setting is declared once in `AppSettings`, with its key and
  default. Views bind to it with `@AppStorage(AppSettings.…)`, and other
  code reads `UserDefaults.standard[AppSettings.…]`.
- Failures worth diagnosing go to the system log through `Log`
  (`os.Logger`, subsystem `com.carneirolabs.lauda`). Never log document
  text or file names: people may attach these logs to public bug reports.

### The one window

Every document is a tab of one window, the workspace's. AppKit owns the
window and SwiftUI draws in it, toolbar and title included. Each file is
a `MarkdownDocument`, an `NSDocument` with no window of its own:
`makeWindowControllers` adds it as a tab, and the one window controller
moves to the selected document, so the title, Save and sheets reach it.
Each document keeps its own editor and preview alive (`DocumentStack`),
and switching tabs only changes which set is hidden.

One editor and one preview shared by every tab, with the text swapped on
a switch, was tried and dropped: undo, the caret, the find state and the
scroll position leaked from one document into the next, and text being
composed with an input method could land in the wrong file. A set per
document costs a text view and a web view for each open file, as a window
per document did.

What AppKit was measured to do around this window is written beside the
code that depends on it: the close button
(`MarkdownDocument.shouldCloseWindowController`), the order of a quit
(`AppDelegate.applicationShouldTerminate`), a menu that observed state
doesn't rebuild (`FileCommands`) and the toolbar that has to lay out
again when the window grows (`Workspace.layOutToolbarAgain`). Two rules
live nowhere else:

- Never wrap a tab change in a global `withAnimation`. Together with the
  title bar changing its layout, the update came late about one time in
  three and left a closed document's panes on screen with the keyboard.
  The workspace shows the panes itself, and the tab strip animates on its
  own with `.animation(_:value:)`.
- A `@MainActor` test waiting for work sent with `DispatchQueue.main.async`
  (closing every tab is one) has to `await Task.sleep`. Spinning
  `RunLoop.current.run(until:)` doesn't run those blocks, since the test
  itself runs inside one.

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
