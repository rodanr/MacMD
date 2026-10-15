# MacMD

Native macOS (26+, Apple silicon) Markdown reader/editor. AppKit document architecture + SwiftUI views,
TextKit 2 live-styled editor, WKWebView Read mode. Goal: light, fast, beautiful, few bugs.

## Commands

```sh
make setup      # regenerate MacMD.xcodeproj from project.yml (needed after adding/removing files)
make build      # debug build          make run   # build + launch
make test-kit   # MacMDKit unit tests incl. fuzz suites (seconds; run constantly)
make test-app   # app unit tests: incremental styling must equal a fresh restyle (random edits)
make test-ui    # UI tests: smoke + features (AppUITests/); light/dark screenshots in the result bundle
make test       # all three
make lint       # swift format lint --strict  ·  make format to fix
make dmg        # release build + build/MacMD-<version>.dmg
make prepare-release VERSION=X.Y.Z   # version + changelog + commit + tag (never pushes; see release skill)
```

`MacMD.xcodeproj` is generated and git-ignored — edit `project.yml`, never the project.

## Map

| Path | What lives there |
|---|---|
| `Packages/MacMDKit` | Pure-Swift core, no UI: parsing, style spans, HTML rendering, outline, list/inline editing rules. All logic goes here first, with tests. |
| `App/Document` | `MarkdownDocument` (NSDocument: I/O, autosave, external reload), `DocumentModel` (per-window observable state), menu actions |
| `App/Editor` | `MarkdownTextView` (NSTextView subclass, editing behaviours), `StyleEngine` (async restyle), `MarkdownStyler` (spans → attributes), `BlockDecoration` (code/quote/rule drawing) |
| `App/Reader` | `ReaderController` (WKWebView), `ReaderPage` (HTML template + CSP), `ResourceSchemeHandler` (`macmd://`) |
| `App/Resources/Web` | `reader.css`, `reader.js`, `vendor/` (pinned highlight.js, KaTeX, Mermaid — via `make vendor`) |
| `App/Export` | HTML/PDF export and printing through an offscreen web view |
| `App/Sidebar`, `App/Settings`, `App/Theme`, `App/Window` | SwiftUI views, `AppSettings`, `Theme` tokens |
| `Packages/MacMDKit/Sources/MacMDKit/Vim` | Vim engine: parses keys, returns `VimAction`s; holds no text. `App/Editor/MarkdownTextView+Vim.swift` applies them |
| `App/About`, `App/Support` | About window and legal texts (bundles `LICENSE`, `TERMS.md`), `AppInfo` links, `UpdateChecker` |
| `App/Resources/AppIcon.icon` | Icon Composer icon (glyph layer + `icon.json`; edit in Xcode → Open Developer Tool → Icon Composer); `make icon` renders the README preview |
| `App/MainMenu.swift` | The whole menu bar, built in code |
| `docs/` | `ARCHITECTURE.md` (data flow, decisions), `DESIGN.md` (type, color tokens), `RELEASING.md` |

## Rules

- Swift 6 strict concurrency. UI types are `@MainActor`; parsing runs off-main via `Task.detached`.
- **Never access `NSTextView.layoutManager`** — it silently drops the editor to TextKit 1. Use `textLayoutManager`.
- Styling changes attributes only, never characters (undo and dirty state stay correct). Don't style while `hasMarkedText()` (IME).
- A line's layout (paragraph style) comes from its first character. Incremental restyling must keep that in mind;
  `make test-app` fuzzes it against a full restyle. Raise its seeds/steps when touching `MarkdownStyler` or `SpanCollector`.
- Source positions from swift-markdown are 1-based UTF-8 columns: convert with `SourceRangeMapper`, never by hand.
- Editor and reader must agree: new Markdown features touch `SpanCollector` *and* `HTMLRenderer` (see the `add-markdown-feature` skill).
- No force unwraps outside tests and static literals; no new dependencies without discussion.
- No network access unless the user asks for it (TERMS.md promises this). New network use updates TERMS.md.
- Keep colors in `Theme.swift` and `reader.css` in sync (`docs/DESIGN.md` lists the tokens).

## Commits

[Conventional Commits](https://www.conventionalcommits.org/): `type(scope): summary`, lowercase imperative
summary, e.g. `fix(editor): keep focus mode in sync with the caret`. Types and scopes: CONTRIBUTING.md.

## Versions and changelog

0.x SemVer (`docs/RELEASING.md`). User-visible changes add a line under `## [Unreleased]` in `CHANGELOG.md`.
Never hand-edit `MARKETING_VERSION` or released changelog sections; `make prepare-release` does both.

## Definition of done

`make lint test` passes, the change is covered by a MacMDKit test where possible, and UI changes were checked
in light **and** dark mode (screenshots from `make test-ui` are in `build/` result bundles).
