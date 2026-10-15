---
name: release
description: Use when cutting a new MacMD release or pre-release, bumping the version, deciding between a patch and minor version, updating the changelog for a release, or when the release workflow fails.
---

# Releasing MacMD

Policy (SemVer, 0.x rules, pre-releases, changelog style): `docs/RELEASING.md`. Releases are built by
`.github/workflows/release.yml` when a `vX.Y.Z` tag is pushed.

## Choosing the version

MacMD is 0.x. Fixes only → patch (`0.2.0` → `0.2.1`). New features or any change to behavior, shortcuts or
settings → minor (`0.2.1` → `0.3.0`). Testers first → `0.3.0-beta.1`. Never `1.0.0` without the maintainer.

## Checklist

1. On an up-to-date `main` with green CI, run `make lint test`.
2. Read `## [Unreleased]` in `CHANGELOG.md`: user-facing wording, right sections. Fix it in a normal commit.
3. `make prepare-release VERSION=X.Y.Z` (sets `MARKETING_VERSION`, dates the changelog, commits, tags; no push).
4. **Ask the maintainer**, then `git push origin main vX.Y.Z`.
5. Watch: `gh run watch $(gh run list --workflow release.yml --limit 1 --json databaseId -q '.[0].databaseId')`.
6. Check the release page has `MacMD-X.Y.Z.dmg` and its `.sha256`, and the notes match the changelog.

Never edit `MARKETING_VERSION` or old changelog sections by hand, and never move or delete a pushed tag:
fix forward with a new patch version.

## Failures

- **"Tag vX.Y.Z, but project.yml has …"** → the tag was made by hand; delete the local tag, use step 3.
- **"CHANGELOG.md has no '## [X.Y.Z]' section"** → same cause; use `make prepare-release`.
- **"nothing under ## [Unreleased]"** → write the changelog entries first.
- **Archive fails but `make build` works** → Release-only issue: try `make release` locally.
- **Notarization rejected** → `xcrun notarytool log <id>`; usually a missing hardened runtime or an unsigned nested binary.
