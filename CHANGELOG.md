# Changelog

All notable changes to MacMD are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).
MacMD is in early development (0.x): minor versions can change behavior and settings. See
[docs/RELEASING.md](docs/RELEASING.md#versioning) for the full policy.

## [Unreleased]

### Fixed
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

[Unreleased]: https://github.com/rodanr/MacMD/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/rodanr/MacMD/releases/tag/v0.1.0
