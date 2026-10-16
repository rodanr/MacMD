# Architecture

MacMD is a document-based AppKit app whose windows are SwiftUI views, plus a UI-free Swift package that holds
all Markdown logic. This document explains how the pieces fit and why they were chosen.

## Layers

```
┌──────────────────────────── MacMD.app ────────────────────────────┐
│ AppDelegate + MainMenu        (AppKit lifecycle, menus)            │
│ MarkdownDocument : NSDocument (I/O, autosave, versions, undo)      │
│   └─ DocumentWindowController ─ NSHostingController(DocumentView)  │
│        ├─ SidebarView   (Outline · Files)                          │
│        ├─ EditorView ── MarkdownTextView (TextKit 2) + StyleEngine │
│        ├─ ReaderView ── ReaderController (WKWebView)               │
│        └─ StatusBar                                                │
├──────────────────────────── MacMDKit ─────────────────────────────┤
│ SpanCollector · HTMLRenderer · Outline/Slugger · MathExtractor     │
│ SourceRangeMapper · ListContinuation · InlineFormatting · …        │
│                    swift-markdown (cmark-gfm)                      │
└────────────────────────────────────────────────────────────────────┘
```

## Editing pipeline

```
keystroke ─► NSTextView ─► NSTextStorage (source of truth)
                               │ didProcessEditing (.editedCharacters)
                               ├─► DocumentModel: revision += 1, debounced outline + word count
                               └─► StyleEngine: mark dirty range, schedule pass
                                       │ Task.detached: SpanCollector.collect(text)
                                       ▼
                               generation still current? no IME composition?
                                       │
                               MarkdownStyler.apply — only blocks that are dirty or whose
                               signature (text + spans) is new; attributes only
```

- **Attributes only.** Styling never edits characters, so undo, autosave and the edited dot are untouched.
- **Generation check.** Results computed for an older text are dropped, so ranges can't go stale.
- **Block diffing.** Each top-level block carries a signature; unchanged blocks keep their attributes, so a
  keystroke relayouts one paragraph rather than the whole document.
- **IME safety.** No styling while the input method has marked text.
- **Large files.** Above 2 MB the editor shows plain text and says so in the status bar.
- **UTF-8 vs UTF-16.** swift-markdown reports 1-based UTF-8 columns; `SourceRangeMapper` converts them to
  `NSRange`. It is tested with emoji, CJK, CRLF and CR line endings.

Block backgrounds (code), the quote bar and rules are drawn by `DecoratedLayoutFragment`, chosen through the
`NSTextLayoutManagerDelegate` from a `blockDecoration` attribute. `NSTextBlock`/`NSTextTable` are avoided because
they force TextKit 1.

**Focus and typewriter modes** never change text or attributes. Focus mode lays two `FocusShadeView`s (paper at
45 % opacity) above and below the focused range, which `FocusParagraph` (MacMDKit) picks: the lines the selection
touches, or the nearest non-blank line when the caret is on a blank one. Typewriter mode scrolls the caret line to
the middle of the view. Both are recomputed from `layout()`, because laying out lines above the caret moves it
after the fact (`textViewportLayoutControllerDidLayout` would be the natural hook, but only the macOS 27 SDK lets a
subclass override it). An empty document shows a "Start writing…" hint drawn by the view, never inserted as text.

## Vim mode

Optional (Settings → Editing, `AppSettings.vimMode`, off by default). `VimEngine` in MacMDKit is a pure key
interpreter: each call gets the current text and selection and returns `VimAction`s (`replace`, `select`,
`undo`, `save`, …). It never owns the text, so the editor stays the single source of truth:

- `MarkdownTextView+Vim.swift` turns `NSEvent`s into `VimKey`s and applies actions through the same
  undoable `apply(TextEdit)` path as every other edit, so undo, autosave, styling and spell check just work.
- Insert mode passes keys straight to `NSTextView` (list continuation, IME and smart pairs keep working).
- `j`/`k` move by *display* lines (wrapped paragraphs), which needs layout, so the engine asks the editor
  (`moveDisplayLines`) and gets the result back through `cursorMoved(to:text:)`. Operators (`dj`) use logical lines.
- `.` replays the keys of the last change, including what was typed in insert mode.
- Mouse selections are adopted via `selectionChanged(to:text:)`; a drag enters visual mode.
- Normal mode hides the caret and draws `BlockCursorView` over the current character.

New commands go into `VimCommand.parse` + `VimEngine`, with a case in `VimEngineTests`.

## Read mode

`HTMLRenderer` turns the document into semantic HTML. Blocks carry `data-line` so the reader and editor can keep
their positions when switching with ⌘E. Heading ids come from `Slugger`, which the outline also uses. The renderer
reports which `Features` the page needs (code, math, Mermaid), and `ReaderPage` only injects those libraries.

The page loads from a custom `macmd://` scheme:

| URL | Served from |
|---|---|
| `macmd://app/…` | `Resources/Web` in the app bundle (CSS, JS, vendored libraries) |
| `macmd://file/<absolute path>` | the file system, **images and media only**, so pictures next to the document work |

Untrusted documents are contained in three ways:

- **Scripts.** A Content Security Policy allows scripts only from `macmd://app`, so `<script>` tags and
  event handlers in a document never run. Forms and `<base>` are disabled too.
- **Navigation.** The reader allows exactly one navigation: the page the app loads, plus in-page anchors.
  Meta refreshes and other redirects are cancelled.
- **Links.** `http`, `https` and `mailto` links open in the default app. Links to Markdown files open in
  MacMD. Any other local file is only revealed in Finder, so a link can never launch an app or script.
  `LinkRouter` opens linked files with the Files sidebar folder of the document the link is in (kept when the
  file is inside it, `FileNavigation.folderToBrowse`) and at the linked section (`DocumentModel.pendingAnchor`).

The Files sidebar's tree (`FileNode`) is read lazily and kept current by an FSEvents stream on the browsed
folder (`FolderWatcher`), which sees changes from every app. New files come from `NewFile`, used by the File
menu, the Files sidebar and the Open panel (`MarkdownDocumentController`, which also starts ⌘N documents in the
current folder).

The web view is created the first time Read mode is shown and then kept, so later switches are instant.
Exporting and printing use a separate offscreen web view in light appearance.

`reader.js` reports the top visible line (after scrolling, rendering and jumps); the outline uses it to highlight the
current heading in Read mode. Mermaid diagrams are themed from the page's CSS tokens and drawn again when the
system switches between light and dark, since their colors are baked into the SVG.

## Math

cmark consumes backslashes and treats `_` as emphasis, which breaks TeX. `MathExtractor` finds `$…$` and
`$$…$$` outside code first:

- for **editor spans** it masks math with filler of identical UTF-8 length, so source positions are unchanged;
- for **HTML** it swaps math for private-use placeholder tokens (padding lines so `data-line` stays correct),
  which the renderer turns into KaTeX elements.

## Decisions

| Decision | Why |
|---|---|
| NSDocument instead of SwiftUI `DocumentGroup` | Native autosave, versions, tabs, Open Recent, rename/move, and NSTextView undo wired to the document without copying the text on every keystroke. |
| AppKit lifecycle with a code-built main menu | Full control over standard document menus; every menu item is reviewable in one file. |
| TextKit 2 `NSTextView` | Native editing: IME, spelling, find bar, accessibility, services. |
| WKWebView for Read mode | Best-in-class typography, KaTeX and Mermaid; created lazily so editing stays light (~50 MB idle). |
| Not sandboxed (hardened runtime) | Relative images and the folder sidebar need access to files next to the document, which the App Sandbox blocks for a document opened on its own. |
| Launch arguments read like `UserDefaults` | `-key value` pairs are settings (the UI tests pin every setting this way); only the remaining arguments are files to open (`LaunchArguments`), and a setting given at launch is never saved. |
| XcodeGen | `project.yml` is reviewable; no `.pbxproj` merge conflicts. |
| Vendored, pinned web libraries | Works offline, reproducible builds, upgrades are explicit (`make vendor`). |
