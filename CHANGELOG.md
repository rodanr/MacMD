# Changelog

All notable changes to MacMD are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).
MacMD is in early development (0.x): minor versions can change behavior and settings. See
[docs/RELEASING.md](docs/RELEASING.md#versioning) for the full policy.

## [Unreleased]

## [0.5.1] - 2026-10-16

### Fixed
- Folders you open in the Files sidebar stay open when you open a file from another folder, in every tab and
  window, including the folder you were browsing when a link takes you to its parent.

## [0.5.0] - 2026-10-16

### Added
- Right-click a file or folder in the Files sidebar to create a file or folder there, rename it, move it to
  the Trash (after asking) or show it in Finder.
- Click a folder in the Files sidebar to choose where New File creates; the sidebar's footer shows the folder.
- Code folders are easier to browse: folders without Markdown files are quieter and listed last (still there
  for new files), and a filter at the top of the Files sidebar finds Markdown files by name in any folder.

### Fixed
- A file opened from a link or another folder is shown in the Files sidebar: its folders open, and the list
  scrolls to it and highlights it. Open folders stay open when you move to another file.
- New File creates in the folder of the file you're in instead of always at the top.

## [0.4.0] - 2026-10-16

### Added
- Create Markdown files where you're working: **File → New File in Folder…** (⌥⌘N), the New File button and
  folder menus in the Files sidebar, and **New File Here…** in the Open panel. Each asks for a name and opens
  the new file.

### Fixed
- Following a link to another Markdown file keeps the Files sidebar on the folder you were browsing, instead
  of jumping to the linked file's folder.
- Relative links and images that go up a folder (`../notes.md`) open the right file in Read mode and exports.
- Links to a section of another file (`notes.md#setup`) open the file at that section.
- A link to a file that doesn't exist says so instead of doing nothing.
- The Files sidebar updates when files are added, renamed or deleted, here or in other apps.
- A new document (⌘N) keeps the folder you were working in, and saving it suggests that folder.

## [0.3.1] - 2026-10-16

### Fixed
- Focus mode keeps the paragraph you're writing readable: it no longer dims the whole page while you type, the
  paragraph you just wrote stays bright when you press Return to start a new one, a selection keeps every
  paragraph it touches bright, and dimmed text is lighter so it stays easy to read.
- Typewriter mode keeps the line you type centered in long documents instead of drifting a line off.

## [0.3.0] - 2026-10-16

### Changed
- A calmer, more consistent look. Code blocks and quotes match between Edit and Read mode; tables sit in
  rounded frames with a tinted header; task boxes are rounded squares sized to the text; diagrams use the
  page's colors and a clean sans font; secondary text and Markdown markers are easier to read.
- The outline shows indent guides and highlights the current heading in Read mode too; the status bar and
  Files list are tidier, and an empty document shows a quiet "Start writing…" hint.
- Animations respect Reduce Motion.

### Fixed
- Diagrams switch colors when macOS switches between light and dark.
- Nested task lists in Read mode sit under their parent item instead of beside it.
- Settings passed at launch (`-theme mono`) are no longer mistaken for files to open, and only apply to that
  launch instead of overwriting your saved preferences.

## [0.2.0] - 2026-10-16

### Added
- Settings → Size → Font size: set the editor and Read mode text size in points (type it or use the
  stepper), or change it with ⌥⌘+ / ⌥⌘−. Zoom still scales the whole window on top of it.

### Fixed
- The Settings window fits small screens: it scrolls instead of running off the bottom.
- Vim mode now matches Vim: a file's final line break no longer counts as an extra line, and `dw`, `cw`, `dG`,
  `2dd`, `J`, `{` / `}`, `v$`, `aw`, `a"`, `i(` and paste follow Vim's rules at line ends, empty lines and the
  end of the file. Checked against real Vim on thousands of commands.
- Documents opened straight into Read mode show their relative images and follow links to other files
  (they were resolved before the document's folder was known).
- VoiceOver names the toolbar's mode buttons "Edit" and "Read" (the Read button was announced as "Bookmark").
- Pasting an image (for example a screenshot) works: ⌘V was disabled when the clipboard held only an image.
- Exported HTML can no longer run scripts from a document (event handlers, `javascript:` links and
  `<script>` are removed, and the file carries a strict Content Security Policy).
- Styling no longer goes stale after some edits: math colors spreading into the next paragraph, a nested list
  item losing its indent, or a code fence line missing its code style.
- A setext heading (a line underlined with `---` or `===`) no longer styles the line after it as a heading.
- Pressing Return after a horizontal rule (`* * *`, `- - -`) no longer starts a list.
- ⌘I on bold text makes it bold italic instead of replacing bold with italic, and ⌘B works the same way.
- Headings that differ only by a number suffix ("Intro", "Intro 1", "Intro") get unique anchors.
- Opening a file from the Files sidebar no longer closes the sidebar: the file opens in a new tab with the
  same folder listed.
- New windows and tabs open with the sidebar the way you last left it (shown or hidden, Outline or Files).

## [0.1.0] - 2026-10-15

First public release.

### Added
- Native TextKit 2 editor that styles Markdown as you type: headings, emphasis, code, quotes, lists, tasks,
  tables, links and math, with Markdown syntax drawn faintly.
- Read mode (⌘E) with syntax-highlighted code, KaTeX math and Mermaid diagrams, all offline.
- Outline and folder sidebars with a toolbar button (⌃⌘S), focus mode (F8) and typewriter mode (F9).
- Paper, Clean and Mono themes in light and dark, and a line width setting (narrow, medium, wide or full)
  that applies to both editing and Read mode.
- Zoom (⌘+, ⌘-, ⌘0) scales the editor, Read mode, sidebar and status bar together; the status bar shows the
  current level.
- Smart editing: list, quote and task continuation; Tab and ⇧Tab indent; ⌘B, ⌘I, ⌘K, ⇧⌘K, ⇧⌘X; ⌘1–⌘6 headings, ⌥⌘0 paragraph;
  typing a delimiter wraps the selection.
- Image drag and paste with relative links (pasted images are saved to `assets/`).
- Export to HTML and PDF, Print, Copy as HTML.
- Autosave, versions, tabs, Open Recent and automatic reload when the file changes on disk.
- Settings → General: choose whether documents open in Edit or Read mode.
- Every release ships with a SHA-256 checksum and a GitHub build attestation, so downloads can be verified.
- Optional Vim mode (Settings → Editing): normal, insert and visual modes, motions, operators, text objects,
  search, `.` repeat and `:w`. Off by default.
- Liquid Glass app icon with light, dark and tinted variants.
- About window with license, terms and privacy, and acknowledgements; manual Check for Updates… (the only time
  MacMD contacts GitHub). No analytics or telemetry; see [TERMS.md](TERMS.md).

[Unreleased]: https://github.com/rodanr/MacMD/compare/v0.5.1...HEAD
[0.5.1]: https://github.com/rodanr/MacMD/releases/tag/v0.5.1
[0.5.0]: https://github.com/rodanr/MacMD/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/rodanr/MacMD/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/rodanr/MacMD/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/rodanr/MacMD/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/rodanr/MacMD/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/rodanr/MacMD/releases/tag/v0.1.0
