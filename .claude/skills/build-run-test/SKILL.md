---
name: build-run-test
description: Use when building, launching, testing or visually checking the MacMD app — after code changes, before claiming a change works, or when a build, test or UI check fails.
---

# Build, run and test MacMD

## Quick reference

| Goal | Command |
|---|---|
| Regenerate project (after adding/removing files) | `make setup` |
| Core logic tests (fast) | `make test-kit` or `cd Packages/MacMDKit && swift test --filter <Suite>` |
| Debug build | `make build` |
| Launch on a file | `make build && build/DerivedData/Build/Products/Debug/MacMD.app/Contents/MacOS/MacMD path/to/file.md` |
| UI smoke tests + screenshots | `make test-ui` (add `-resultBundlePath build/ui.xcresult` to the xcodebuild line for a named bundle) |
| UI tests with no capturable display ("Failed to create screenshot") | prefix with `TEST_RUNNER_MACMD_SKIP_SCREENSHOTS=1`; assertions still run, but check visuals later |
| Lint / format | `make lint` / `make format` |

## Seeing the UI

Screen capture from a terminal usually lacks Screen Recording permission. Use the UI tests instead: they attach
`edit-light`, `edit-dark`, `read-light`, `read-dark` (and `-2` scrolled) screenshots. Export them:

```sh
xcrun xcresulttool export attachments --path build/ui.xcresult --output-path /tmp/shots
```

`manifest.json` in the output maps exported files to screenshot names. Launch arguments
`-appearance light|dark`, `-theme paper|clean|mono` override settings for a run.

## Common failures

- **"Cannot find X in scope" for a new file** → run `make setup`; the project is generated.
- **Concurrency errors on AppKit delegate methods** → prefer `@preconcurrency` conformance or a `nonisolated`
  method that only touches `nonisolated(unsafe)` state documented as main-thread-only.
- **Editor suddenly lays out differently / slow** → something touched `layoutManager` (TextKit 1 fallback).
- **Reader shows blank page** → open Web Inspector: `defaults write io.github.rodanr.macmd WebKitDeveloperExtras -bool YES`,
  check the CSP in `ReaderPage.swift` and that assets resolve under `macmd://app/`.
