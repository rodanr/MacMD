# Releasing

Every `vX.Y.Z` tag pushed to GitHub builds a DMG and publishes a GitHub Release
(`.github/workflows/release.yml`). The `release` skill in `.claude/skills/` has the same steps for agents.

## Versioning

MacMD follows [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`, tagged `vX.Y.Z`.

**0.x: early development (now).** Expect change between minor versions.

| Bump | When | Example |
|---|---|---|
| Minor | New features, or changes to behavior, shortcuts or settings | 0.1.0 → 0.2.0 |
| Patch | Bug fixes only, nothing users have to relearn | 0.2.0 → 0.2.1 |
| Pre-release | A build for testers before a minor release | 0.3.0-beta.1, 0.3.0-rc.1 |

**1.0.0** comes when MacMD is something people can rely on: notarized builds, settings and file handling we
commit to keeping, and no known data-loss bugs. After 1.0, anything that breaks existing habits (removed
features, renamed shortcuts, reset settings) needs a major version.

- **Source of truth:** `MARKETING_VERSION` in `project.yml`. The release workflow refuses a tag that doesn't
  match it or that has no `CHANGELOG.md` section.
- **App version vs. tag:** the app shows plain `X.Y.Z` (macOS requires it); pre-release suffixes appear only in
  the tag, the DMG name and the release title. The build number is the CI run number, so it always increases.
- **Pre-releases** are published as GitHub *pre-releases* and never become "Latest", so neither the README
  download link nor **Check for Updates…** offers them to everyone.

## Changelog

[CHANGELOG.md](../CHANGELOG.md) follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and is written
for users, not for developers:

- Every pull request with a user-visible change adds a line under `## [Unreleased]`, in *Added*, *Changed*,
  *Deprecated*, *Removed*, *Fixed* or *Security*. The *Changelog* workflow enforces this; label a pull
  request `skip-changelog` for changes users won't notice (docs, CI, refactors).
- Describe the effect ("Focus mode now follows the caret"), not the implementation.
- Releases never edit old sections; the release script moves *Unreleased* into a dated section.

## Cutting a release

1. Update `main`, make sure CI is green, and run `make lint test`.
2. `make prepare-release VERSION=0.2.0`. It checks the version is newer than the last tag, sets
   `MARKETING_VERSION`, turns *Unreleased* into `## [0.2.0] - <today>` with a compare link, commits
   `chore(release): 0.2.0` and creates the tag. It never pushes.
3. Review with `git show v0.2.0`, then publish: `git push origin main v0.2.0`.
4. The release workflow checks that tag, project and changelog agree, builds and (when configured) notarizes
   the DMG, and publishes the release with that changelog section as its notes.
5. Download the DMG from the release page, open it, and check that the app launches and shows the new version
   in **About MacMD**.

Fixes go to `main` and ship as the next patch; there are no release branches while MacMD is 0.x. A bad
release is fixed forward with a new patch version rather than by moving or deleting its tag.

## Unsigned builds (default)

Without signing secrets, the app is ad-hoc signed and Gatekeeper blocks the first launch. The README's
[Install](../README.md#install) section walks users through **Open Anyway** and explains why they can trust
the build; the release notes link to it. Keep those steps in sync with the current macOS dialogs.

Every release also gets a SHA-256 file and a [build provenance attestation](https://docs.github.com/actions/security-for-github-actions/using-artifact-attestations),
which users check with `gh attestation verify MacMD-X.Y.Z.dmg --repo rodanr/macmd`.

## Enabling Developer ID signing and notarization

With an Apple Developer Program membership, add these repository secrets (**Settings → Secrets and
variables → Actions**). The workflow picks them up automatically:

| Secret | Value |
|---|---|
| `MACOS_CERT_P12` | Base64 of your *Developer ID Application* certificate exported as .p12 (`base64 -i cert.p12 \| pbcopy`) |
| `MACOS_CERT_PASSWORD` | Password used when exporting the .p12 |
| `APPLE_ID` | Apple ID email used for notarization |
| `APPLE_TEAM_ID` | 10-character team id |
| `APPLE_APP_PASSWORD` | An [app-specific password](https://support.apple.com/102654) for that Apple ID |

The app is then signed with the hardened runtime, the DMG is notarized and stapled, and the
"Open Anyway" note disappears from the release notes.

## Local packaging

```sh
make dmg      # → build/MacMD-<version>.dmg and .sha256
```

## Manual builds

**Actions → Release → Run workflow** with a version number creates a *draft* release, which is useful for
testing the pipeline.
