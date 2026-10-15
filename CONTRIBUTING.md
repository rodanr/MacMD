# Contributing to MacMD

Thanks for helping make MacMD better. Bug reports, ideas and pull requests are all welcome.

## Getting started

Requirements: macOS 26+, Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/rodanr/macmd.git
cd macmd
make run        # generates the project, builds and launches
make test       # unit + UI tests
```

Open `MacMD.xcodeproj` in Xcode if you prefer. It's generated from `project.yml`, so run `make setup`
after adding or removing files instead of editing the project.

## How the code is organised

- **`Packages/MacMDKit`**: all Markdown logic, with no UI. Start here; it has fast tests (`make test-kit`).
- **`App/`**: the macOS app (AppKit documents and menus, SwiftUI views, the TextKit 2 editor, the reader).

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) explains the data flow and the reasons behind it.
[docs/DESIGN.md](docs/DESIGN.md) lists the typography and color tokens.

## Pull requests

1. Open an issue first for larger changes, so we can agree on the approach.
2. Write a failing test in MacMDKit before the fix or feature, when the logic allows it.
3. Run `make format lint test` before pushing.
4. For UI changes, include light and dark screenshots. The UI tests produce them; see the
   `build-run-test` skill.
5. Keep pull requests focused. If users will notice the change, add a line under `## [Unreleased]` in
   `CHANGELOG.md` describing the effect; otherwise label the pull request `skip-changelog`.

## Commit messages

Commits follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):
`<type>(<optional scope>): <summary>`, with a lowercase imperative summary and no trailing period.

| Type | For |
|---|---|
| `feat` | A new feature users can see |
| `fix` | A bug fix |
| `perf` | A performance improvement |
| `refactor` | A code change that neither fixes a bug nor adds a feature |
| `docs` | Documentation only |
| `test` | Tests only |
| `build` / `ci` | The build, project file, scripts or GitHub Actions |
| `chore` | Maintenance, including `chore(release): X.Y.Z` |

Scopes are optional and name the area: `editor`, `reader`, `vim`, `export`, `sidebar`, `settings`, `kit`.
Mark breaking changes with `!` (`feat(settings)!: …`) and a `BREAKING CHANGE:` footer. Examples:

```text
feat(vim): add text objects for quotes and brackets
fix(editor): keep focus mode in sync with the caret
docs: explain how to open unnotarized builds
```

## Versions and releases

MacMD uses [Semantic Versioning](https://semver.org/) and is in early development (0.x).
[docs/RELEASING.md](docs/RELEASING.md) covers the versioning rules, the changelog style and how releases are cut.

## Using AI coding agents

The repository is set up for Claude Code and other agents: [CLAUDE.md](CLAUDE.md) holds the rules, and
`.claude/skills/` holds the task playbooks (building and testing, adding a Markdown feature, adding a theme,
releasing). Contributions made with agents are welcome. You are responsible for reviewing and testing what you submit.

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Be kind.
