# UI Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** executed in this session; shipped in 0.3.0. The open box was covered differently (PDF export is checked by the export UI test, not by eye). Deviations are listed in the
spec's Outcome section.

**Goal:** Refine MacMD's editor, Read mode and window chrome to one calm, consistent "editorial" design, without
new features. Spec: `docs/superpowers/specs/2026-10-15-ui-refinement-design.md`.

**Architecture:** Design tokens live in three mirrored places:
- `docs/DESIGN.md` (source of truth);
- `App/Theme/Theme.swift` (editor, AppKit/SwiftUI);
- `App/Resources/Web/reader.css` (Read mode and exports).

The renderer (`Packages/MacMDKit/Sources/MacMDKit/HTMLRenderer.swift`) gets two markup changes, both test-first.
Everything else is styling: attributes in the editor, CSS and JS in Read mode, SwiftUI in the chrome.

**Tech Stack:** Swift 6, AppKit/TextKit 2, SwiftUI (macOS 26), WKWebView, CSS, Mermaid 12, Swift Testing, XCTest UI
tests.

**Rules (from `CLAUDE.md`):**
- `make setup` after adding files.
- Styling changes attributes only.
- Keep the colors in `Theme.swift` and `reader.css` in sync.
- Conventional Commits authored as `Rodan Ramdam <rodan.ramdam@gmail.com>`, with no co-author trailer.
- `make lint test` before each commit.

---

## File map

| File | Change |
|---|---|
| `docs/DESIGN.md` | New "Tokens" section: spacing, radii, surfaces, quote bar, motion, contrast targets |
| `App/Theme/Theme.swift` | Token constants; marker and secondary alphas; shared quote-bar color |
| `App/Resources/Web/reader.css` | Token variables; code, table, task, quote, image, link and heading refinements; reduced motion |
| `App/Resources/Web/reader.js` | Mermaid `base` theme from page tokens; redraw on appearance change |
| `Packages/MacMDKit/Sources/MacMDKit/HTMLRenderer.swift` | Trim the code block's trailing newline; wrap tables in `div.table` |
| `Packages/MacMDKit/Tests/MacMDKitTests/HTMLRendererTests.swift` | Tests for both renderer changes |
| `App/Editor/BlockDecoration.swift` | Radius, quote bar and code inset from tokens |
| `App/Editor/MarkdownStyler.swift` | Code indent from tokens |
| `App/Editor/MarkdownTextView.swift` | Empty-document placeholder; focus shade alpha |
| `App/Document/DocumentModel.swift`, `App/Reader/ReaderController.swift` | Observable reader position for the outline |
| `App/Sidebar/OutlineView.swift`, `App/Sidebar/FolderBrowserView.swift` | Indent guides, current-item pill |
| `App/Window/DocumentView.swift`, `App/Window/HUD.swift` | Status bar hairline and spacing; Reduce Motion |
| `AppTests/ContrastTests.swift` (new) | WCAG contrast checks for every theme and appearance |
| `AppUITests/DesignReviewUITests.swift` (new) | Screenshots of every theme × appearance for review |
| `CHANGELOG.md` | Unreleased → Changed and Fixed |

---

### Task 0: Release v0.2.0 and commit the spec

- [x] **Step 1:** Confirm CI on `54239ef` passed:
  `gh run list --workflow ci.yml --branch main --limit 1 --json conclusion,headSha`. Expected:
  `"conclusion":"success"`. If it failed, use superpowers:systematic-debugging, fix, push, and wait again.
- [x] **Step 2:** Run `make prepare-release VERSION=0.2.0`. Expected: `Committed: chore(release): 0.2.0` and
  `Tagged v0.2.0`.
- [x] **Step 3:** Run `git push origin main v0.2.0`, then
  `gh run watch $(gh run list --workflow release.yml --limit 1 --json databaseId -q '.[0].databaseId')`.
  Expected: success.
- [x] **Step 4:** Download `MacMD-0.2.0.dmg` with `gh release download v0.2.0`. Verify `shasum -a 256 -c`,
  `gh attestation verify MacMD-0.2.0.dmg --repo rodanr/MacMD`, and that `CFBundleShortVersionString` is `0.2.0`.
- [x] **Step 5:** Copy the spec to `docs/superpowers/specs/2026-10-15-ui-refinement-design.md` and this plan to
  `docs/superpowers/plans/2026-10-15-ui-refinement.md`. Commit:
  `git commit -m "docs: add the UI refinement spec and plan"`.

---

### Task 1: Tokens and contrast

**Files:** `docs/DESIGN.md`, `App/Theme/Theme.swift`, `App/Resources/Web/reader.css`, new `AppTests/ContrastTests.swift`.

- [x] **Step 1: Write the failing contrast test** (`AppTests/ContrastTests.swift`):

```swift
import AppKit
import Testing

@testable import MacMD

/// WCAG contrast of the editor's text colors on its paper, for every theme and appearance.
@MainActor
@Suite struct ContrastTests {
    static func luminance(_ color: NSColor) -> Double {
        func channel(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.redComponent) + 0.7152 * channel(color.greenComponent)
            + 0.0722 * channel(color.blueComponent)
    }

    /// `color` composited over `background`, resolved in `appearance`.
    static func contrast(_ color: NSColor, on background: NSColor, appearance: NSAppearance) -> Double {
        var ratio = 0.0
        appearance.performAsCurrentDrawingAppearance {
            guard let fg = color.usingColorSpace(.sRGB), let bg = background.usingColorSpace(.sRGB) else { return }
            let a = fg.alphaComponent
            let blended = NSColor(
                srgbRed: fg.redComponent * a + bg.redComponent * (1 - a),
                green: fg.greenComponent * a + bg.greenComponent * (1 - a),
                blue: fg.blueComponent * a + bg.blueComponent * (1 - a), alpha: 1)
            let (l1, l2) = (luminance(blended), luminance(bg))
            ratio = (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
        }
        return ratio
    }

    @Test(arguments: Theme.ID.allCases, ["aqua", "darkAqua"])
    func textColorsMeetTheirTargets(theme id: Theme.ID, appearanceName: String) throws {
        let theme = Theme(id: id, fontSize: 16)
        let appearance = try #require(NSAppearance(named: NSAppearance.Name(appearanceName)))
        #expect(Self.contrast(theme.text, on: theme.background, appearance: appearance) >= 7)
        #expect(Self.contrast(theme.secondaryText, on: theme.background, appearance: appearance) >= 4.5)
        #expect(Self.contrast(theme.listMarker, on: theme.background, appearance: appearance) >= 3)
        // Syntax markers are decorative and redundant with styling, so they only need to stay visible.
        #expect(Self.contrast(theme.syntaxMarker, on: theme.background, appearance: appearance) >= 2)
    }
}
```

- [x] **Step 2:** Run `make setup && make test-app`. Expected: FAIL on Paper/aqua `secondaryText` (62% ink ≈ 4.4:1),
  and possibly syntax markers at 28%.
- [x] **Step 3: Update `Theme.swift`.** Replace the color lines and add token constants:

```swift
    var secondaryText: NSColor { text.withAlphaComponent(0.66) }
    /// Markdown punctuation: visible but quiet (decorative, ≥ 2:1).
    var syntaxMarker: NSColor { text.withAlphaComponent(0.38) }
    var quoteBar: NSColor { .controlAccentColor.withAlphaComponent(Self.quoteBarAlpha) }

    // MARK: Design tokens (docs/DESIGN.md; mirrored in reader.css)

    static let blockRadius: CGFloat = 10
    static let panelRadius: CGFloat = 14
    static let quoteBarWidth: CGFloat = 2.5
    static let quoteBarAlpha: CGFloat = 0.45
    static let codeInset: CGFloat = 12
    static let motion = 0.15
```

- [x] **Step 4:** Run `make test-app`. Expected: PASS. If a theme still fails, raise that alpha by 0.02 until it
  passes and record the value in DESIGN.md.
- [x] **Step 5: Mirror in `reader.css`.**
  - Change every `--ink-muted` alpha from `0.62`/`0.6` to `0.66`, in all theme and appearance blocks.
  - Add to `:root`:

```css
  --radius-inline: 6px;
  --radius-block: 10px;
  --radius-panel: 14px;
  --quote-bar: 2.5px solid color-mix(in srgb, var(--accent) 45%, transparent);
  --surface-2: color-mix(in srgb, var(--ink) 2.5%, transparent);
```

  - In each dark block, add `--surface-2: color-mix(in srgb, var(--ink) 3.5%, transparent);`.
- [x] **Step 6:** Add a "Tokens" table to `docs/DESIGN.md`. It must list spacing 4·8·12·16·24·32·48; radii 6/10/14
  (task box 4); `--surface` and `--surface-2` values; quote bar 2.5pt at accent 45%; motion 150 ms ease-out with
  none under Reduce Motion; contrast targets text 7, muted 4.5, list markers 3, syntax markers 2.
- [x] **Step 7:** `make lint test-kit test-app`, then commit:
  `git commit -m "style: add shared design tokens and contrast checks"`.

---

### Task 2: Renderer markup (TDD)

**Files:** `Packages/MacMDKit/Sources/MacMDKit/HTMLRenderer.swift`,
`Packages/MacMDKit/Tests/MacMDKitTests/HTMLRendererTests.swift`.

- [x] **Step 1: Write the failing tests** (append to `HTMLRendererTests`):

```swift
    @Test func codeBlocksHaveNoTrailingBlankLine() {
        let html = HTMLRenderer.render("```swift\nlet a = 1\n```").body
        #expect(html.contains(#"<code class="language-swift">let a = 1</code></pre>"#))
    }

    @Test func emptyCodeBlocksStayEmpty() {
        #expect(HTMLRenderer.render("```\n```").body.contains("<code></code>"))
    }

    @Test func tablesAreWrappedForRoundedCorners() {
        let html = HTMLRenderer.render("| a |\n|---|\n| 1 |").body
        #expect(html.hasPrefix(#"<div class="table">"#))
        #expect(html.contains("</table>\n</div>"))
    }
```

- [x] **Step 2:** `cd Packages/MacMDKit && swift test --filter HTMLRendererTests`. Expected: the three new tests FAIL.
- [x] **Step 3: Implement.** In `visitCodeBlock`, replace the first line (`let code = Placeholder.restoringTeX(…)`) with:

```swift
        // cmark keeps the line break before the closing fence; it would render as a blank last line.
        var code = Placeholder.restoringTeX(in: codeBlock.code, math: math)
        if code.hasSuffix("\n") { code.removeLast() }
```

  In `visitTable`, emit the wrapper. The `data-line` attribute moves to the wrapper so scroll sync still finds
  the block:

```swift
        output += "<div class=\"table\"\(lineAttribute(table))>\n<table>\n"  // was "<table\(lineAttribute(table))>\n"
        // … head and body unchanged …
        output += "</table>\n</div>\n"  // was "</table>\n"
```

- [x] **Step 4:** Run `swift test`. Expected: all pass, including `RendererReferenceTests`, since `div` is filtered
  out and white space is collapsed.
- [x] **Step 5:** Commit: `git commit -m "style(reader): tidy code block and table markup for styling"`.

---

### Task 3: Read mode styles

**Files:** `App/Resources/Web/reader.css`. **REQUIRED SKILL:** frontend-design:frontend-design.

- [x] **Step 1: Replace the code rules** (`/* Code */` section) with:

```css
code, pre, kbd { font-family: var(--font-mono); font-size: 0.86em; }

:not(pre) > code {
  background: var(--surface);
  padding: 0.1em 0.32em;
  border-radius: var(--radius-inline);
}

pre {
  background: var(--surface);
  border-radius: var(--radius-block);
  padding: 0.9em 1.1em;
  overflow-x: auto;
  line-height: 1.55;
  tab-size: 4;
  scrollbar-width: thin;
}

@media (prefers-color-scheme: dark) {
  pre { box-shadow: inset 0 0 0 1px var(--ink-faint); }
}
```

- [x] **Step 2: Replace the table rules** with:

```css
.table {
  margin: 0 0 1.05em;
  overflow-x: auto;
  border: 1px solid var(--ink-faint);
  border-radius: var(--radius-block);
  scrollbar-width: thin;
}

.table table {
  border-collapse: collapse;
  width: 100%;
  margin: 0;
  font-size: 0.94em;
  font-variant-numeric: tabular-nums;
}

th, td {
  padding: 0.55em 0.9em;
  border-bottom: 1px solid var(--ink-faint);
  text-align: left;
  vertical-align: top;
}

th { font-weight: 650; background: var(--surface-2); }
tr:last-child td { border-bottom: 0; }
```

  Also remove `table` from the shared margin selector (`p, ul, ol, … table, …`).
- [x] **Step 3: Task boxes, rounded squares.** Replace the `li.task input` and `:checked` rules:

```css
li.task input {
  appearance: none;
  flex: none;
  width: 1em;
  height: 1em;
  margin: 0;
  border: 1.5px solid var(--ink-muted);
  border-radius: 4px;
  position: relative;
  top: 0.14em;
}

li.task input:checked { background: var(--accent); border-color: var(--accent); }

li.task input:checked::after {
  content: "";
  position: absolute;
  left: 0.3em;
  top: 0.1em;
  width: 0.25em;
  height: 0.5em;
  border: solid white;
  border-width: 0 0.12em 0.12em 0;
  transform: rotate(45deg);
}
```

- [x] **Step 4: Quotes, headings, images, links, selection, details:**

```css
blockquote { margin-left: 0; padding: 0.1em 0 0.1em 1em; border-left: var(--quote-bar); color: var(--ink-muted); font-style: italic; }
h1 { font-size: 2.15em; }
h2 { margin-top: 2.2em; }
h1, h2, h3, h4, h5, h6 { scroll-margin-top: 32px; }
img { border-radius: var(--radius-inline); }
@media (prefers-color-scheme: dark) { img { outline: 1px solid var(--ink-faint); outline-offset: -1px; } }
a { text-decoration-color: color-mix(in srgb, var(--link) 30%, transparent); transition: text-decoration-color 150ms ease-out; }
::selection { background: color-mix(in srgb, var(--accent) 22%, transparent); }
details { border-radius: var(--radius-block); }
@media (prefers-reduced-motion: reduce) { * { transition: none !important; scroll-behavior: auto !important; } }
```

  Merge these into the existing rules rather than duplicating selectors. Keep `html[data-theme="mono"] blockquote`
  and the clean-theme roman rule.
- [x] **Step 5:** Run `make build`, then `make test-ui` for the Read mode and export tests. Expected: PASS.
- [x] **Step 6:** Commit: `git commit -m "style(reader): refine code, tables, task boxes, quotes and rhythm"`.

---

### Task 4: Diagrams themed from the page, and redrawn on appearance change

**Files:** `App/Resources/Web/reader.js`, `App/Resources/Web/reader.css`.

- [x] **Step 1:** Replace `renderDiagrams()` in `reader.js`:

```js
  /// A CSS color, composited over the paper so Mermaid gets an opaque color it can shade.
  function opaque(variable) {
    const probe = document.createElement("span");
    probe.style.color = `var(${variable})`;
    document.body.append(probe);
    const [r, g, b, a = 1] = getComputedStyle(probe).color.match(/[\d.]+/g).map(Number);
    probe.remove();
    const paper = getComputedStyle(document.documentElement).backgroundColor.match(/[\d.]+/g).map(Number);
    const mix = (c, p) => Math.round(c * a + p * (1 - a));
    return `rgb(${mix(r, paper[0])}, ${mix(g, paper[1])}, ${mix(b, paper[2])})`;
  }

  async function renderDiagrams() {
    const nodes = [...document.querySelectorAll(".mermaid")];
    if (!window.mermaid || nodes.length === 0) return;
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      theme: "base",
      fontFamily: "system-ui, -apple-system, sans-serif",
      themeVariables: {
        darkMode: prefersDark(),
        background: opaque("--paper"),
        primaryColor: opaque("--surface"),
        primaryTextColor: opaque("--ink"),
        primaryBorderColor: opaque("--ink-faint"),
        lineColor: opaque("--ink-muted"),
        secondaryColor: opaque("--surface-2"),
        tertiaryColor: opaque("--paper"),
        edgeLabelBackground: opaque("--paper"),
        fontSize: "14px",
      },
    });
    for (const node of nodes) {
      node.dataset.source ??= node.textContent;
      node.removeAttribute("data-processed");
      node.classList.remove("error");
      node.textContent = node.dataset.source;
      try {
        await mermaid.run({ nodes: [node] });
      } catch (error) {
        node.classList.add("error");
        node.textContent = `Diagram error: ${error?.message ?? error}`;
      }
    }
  }

  // Diagrams bake colors in; redraw them when the system switches between light and dark.
  window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => renderDiagrams());
```

- [x] **Step 2:** In `reader.css`, add `.mermaid .node rect, .mermaid .node polygon { rx: 8px; ry: 8px; }` and
  tighten the edge label padding: `.mermaid .edgeLabel p { padding: 0 4px; }`.
- [x] **Step 3:** Add `testDiagramRedrawsOnAppearanceChange` to `AppUITests/RobustnessUITests.swift`:
  1. Open the fixture in Read mode with `-appearance light`.
  2. Screenshot.
  3. Open Settings and set the Color scheme to Dark.
  4. Wait 2 s.
  5. Screenshot.
  6. Assert that `reader.otherElements` still contains the diagram (the `Write` static text exists).

  Review both screenshots: the diagram must use the dark palette in the second.
- [x] **Step 4:** `make build test-ui`, then commit:
  `git commit -m "fix(reader): theme diagrams from the page and redraw them on appearance change"`.

---

### Task 5: Editor refinements

**Files:** `App/Editor/BlockDecoration.swift`, `App/Editor/MarkdownStyler.swift`, `App/Editor/MarkdownTextView.swift`,
`App/Editor/EditorView.swift`.

- [x] **Step 1: Decorations from tokens.** In `DecoratedLayoutFragment.draw`, the quote bar becomes:

```swift
            let bar = CGRect(
                x: frame.minX + 1, y: frame.minY, width: Theme.quoteBarWidth, height: frame.height + paragraphSpacing)
            context.addPath(
                CGPath(roundedRect: bar, cornerWidth: Theme.quoteBarWidth / 2, cornerHeight: Theme.quoteBarWidth / 2, transform: nil))
```

  In `drawCodeBackground`, use `let radius: CGFloat = Theme.blockRadius`.
- [x] **Step 2: Code inset.** In `MarkdownStyler.styleCodeBlock`, use
  `paragraphStyle(indent: Theme.codeInset, tailIndent: -Theme.codeInset, spacing: 0)`.
- [x] **Step 3: Focus shade.** In `FocusShadeView.draw`, use `color.withAlphaComponent(0.65)`, so dimmed text sits
  near 35% ink.
- [x] **Step 4: Placeholder.** Add to `MarkdownTextView`:

```swift
    /// Shown in an empty document; drawn, never part of the text.
    var placeholder = "Start writing…"

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText(), let font else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: (textColor ?? .labelColor).withAlphaComponent(0.35),
        ]
        (placeholder as NSString).draw(at: textContainerOrigin, withAttributes: attributes)
    }

    override func didChangeText() {
        super.didChangeText()
        if (string as NSString).length <= 1 { needsDisplay = true }  // show or hide the placeholder
    }
```

  Make sure `font` and `textColor` are set from the theme in `EditorView.configure`: `textView.font = theme.bodyFont`
  and `textView.textColor = theme.text`.
- [x] **Step 5:** Run `make test-app`. Expected: PASS. Then run it once with
  `@Test(arguments: 0..<60)` and `0..<120` steps, and restore afterwards. Run `make test-ui` too: the new-document
  test types into an empty editor, which checks that the placeholder never becomes text.
- [x] **Step 6:** Commit: `git commit -m "style(editor): match Read mode's code and quotes, tune focus shade, add an empty-document hint"`.

---

### Task 6: Window chrome

**Files:** `App/Document/DocumentModel.swift`, `App/Reader/ReaderController.swift`, `App/Sidebar/OutlineView.swift`,
`App/Sidebar/FolderBrowserView.swift`, `App/Window/DocumentView.swift`, `App/Window/HUD.swift`.

- [x] **Step 1: Observable reader position.**
  - Add `var readerTopLine: Int?` to `DocumentModel`.
  - In `ReaderController.userContentController`, case `"topLine"`, also set `model?.readerTopLine = lastTopLine`.
- [x] **Step 2: Outline.** Replace the `currentSlug` computation and the row label in `OutlineView`:

```swift
    private var currentSlug: String? {
        let line = model.mode == .read ? (model.readerTopLine ?? 1) : model.caretLine
        return model.outline.last { $0.line <= line }?.slug
    }
```

```swift
                    HStack(spacing: 0) {
                        ForEach(0..<(item.level - minLevel), id: \.self) { _ in
                            Rectangle().fill(.separator).frame(width: 1).padding(.leading, 6 * zoom).padding(.trailing, 5 * zoom)
                        }
                        Text(item.title.isEmpty ? "Untitled" : item.title)
                            .font(.system(size: 13 * zoom, weight: item.level == minLevel ? .semibold : .regular))
                            .lineLimit(1)
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(item.slug == currentSlug ? Color.accentColor.opacity(0.14) : .clear))
                    .contentShape(Rectangle())
```

- [x] **Step 3: Files.** In `FileNodeChildren`:
  - Give the current file the same pill (`RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.14))`)
    instead of accent-colored text.
  - Use `Label(…).symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)` for icons, with the text in
    `.primary`.
- [x] **Step 4: Status bar.** In `StatusBar`:
  - Set spacing to 16 and padding to `.horizontal 16, .vertical 6`.
  - Add `.overlay(alignment: .top) { Rectangle().fill(.separator).frame(height: 0.5) }`.
  - In `ModeChip`, replace `Capsule()` with `RoundedRectangle(cornerRadius: Theme.panelRadius / 2)`.
- [x] **Step 5: Reduce Motion.**
  - In `DocumentView`, add `@Environment(\.accessibilityReduceMotion) private var reduceMotion`. Use
    `.animation(reduceMotion ? nil : .easeOut(duration: Theme.motion), value: model.mode)`, and
    `withAnimation(reduceMotion ? nil : .default)` for the sidebar toggle.
  - In `HUDView`, use the same guard, and the transition `.opacity` only when motion is reduced.
- [x] **Step 6:** `make build test-ui`, then commit:
  `git commit -m "style(ui): refine the outline, files list and status bar, and respect Reduce Motion"`.

---

### Task 7: Design review screenshots and README

- [x] **Step 1: Create `AppUITests/DesignReviewUITests.swift`:**

```swift
import XCTest

/// Captures every theme in light and dark, in both modes, for visual review. Assertions are light;
/// the screenshots are the product.
final class DesignReviewUITests: XCTestCase {
    @MainActor
    func testCaptureThemes() throws {
        for theme in ["paper", "clean", "mono"] {
            for appearance in ["light", "dark"] {
                let app = launch([
                    fixture, "-theme", theme, "-appearance", appearance, "-sidebarVisible", "YES",
                    "-NSWindow Frame MarkdownDocumentWindow", "120 120 1200 780 0 0 2560 1410",
                ])
                let window = app.windows.firstMatch
                XCTAssertTrue(window.textViews["editor"].waitForExistence(timeout: 10))
                attach(window, "review-\(theme)-\(appearance)-edit")
                app.typeKey("e", modifierFlags: .command)
                XCTAssertTrue(window.webViews.firstMatch.staticTexts["Welcome to MacMD"].waitForExistence(timeout: 10))
                window.webViews.firstMatch.scroll(byDeltaX: 0, deltaY: -900)
                attach(window, "review-\(theme)-\(appearance)-read")
                if theme == "paper" {
                    app.typeKey(",", modifierFlags: .command)
                    XCTAssertTrue(app.windows["Settings"].waitForExistence(timeout: 5))
                    attach(app.windows["Settings"], "review-settings-\(appearance)")
                }
                app.terminate()
            }
        }
    }
}
```

- [x] **Step 2:** `make setup`, then run it with the display unlocked:
  `xcodebuild … test -only-testing:MacMDUITests/DesignReviewUITests -resultBundlePath build/review.xcresult`.
  Export the attachments and review all 12 images. Check:
  - consistent radii;
  - quote bars identical in both modes;
  - legible markers;
  - tables in rounded containers;
  - diagrams in the page palette;
  - outline pills and guides;
  - the status bar hairline.

  Fix anything off and repeat. If the display is locked, stop and ask the user; don't skip the review.
- [x] **Step 3:** Refresh the README screenshots: run `testOpenEditAndRead` and copy `edit-light`, `read-dark` and
  `read-dark-2` into `docs/screenshots/`.
- [x] **Step 4:** Commit: `git commit -m "test(ui): capture every theme for design review; refresh README screenshots"`.

---

### Task 8: Verify, document, ship

- [x] **Step 1:** Run `make lint test` (kit, app, UI). Expected: all pass. Report exact counts.
- [ ] **Step 2:** Export a PDF of the kitchen sink: `testExportPDFAndHTML` (keep the file) or the File menu.
  Open the PDF and confirm code, tables and diagrams look right on white.
- [x] **Step 3:** Run superpowers:requesting-code-review on the commits since the spec commit, then fix valid
  findings.
- [x] **Step 4:** Add to CHANGELOG under Unreleased:
  - **Changed:** "A calmer, more consistent look: matching code blocks and quotes in both modes, tables in rounded
    frames, square task boxes, diagrams in the page's colors, clearer secondary text, an outline that follows
    your place in Read mode, and Reduce Motion support."
  - **Fixed:** "Diagrams switch colors with light and dark mode."
- [x] **Step 5:** Run superpowers:verification-before-completion. Commit `docs: …`, then push to `main`.
  Releasing waits for the user.
