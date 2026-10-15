#!/usr/bin/env bash
# Prepares a release on main: sets the version in project.yml, turns CHANGELOG.md's [Unreleased] section
# into a dated release section with compare links, commits "chore(release): X.Y.Z" and creates the tag vX.Y.Z.
# It never pushes; it prints the push command instead. See docs/RELEASING.md.
#
# Usage: scripts/prepare-release.sh 0.2.0          (a release)
#        scripts/prepare-release.sh 0.2.0-beta.1   (a pre-release; published as such on GitHub)
set -euo pipefail

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$ ]]; then
  echo "usage: scripts/prepare-release.sh X.Y.Z[-alpha.N|-beta.N|-rc.N]" >&2
  exit 64
fi
CORE="${VERSION%%-*}"   # CFBundleShortVersionString must be plain X.Y.Z
REPO_URL="https://github.com/rodanr/macmd"
cd "$(dirname "$0")/.."

fail() { echo "error: $*" >&2; exit 1; }
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || fail "release from main"
[ -z "$(git status --porcelain)" ] || fail "commit or stash your changes first"
git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && fail "tag v$VERSION already exists"

CURRENT="$(awk '/MARKETING_VERSION:/ { print $2; exit }' project.yml)"
LATEST_TAG="$(git tag --list 'v*' | scripts/semver.py newest)"
if [ -n "$LATEST_TAG" ] && ! grep -qF "## [$VERSION]" CHANGELOG.md; then
  scripts/semver.py is-newer "$LATEST_TAG" "$VERSION" || fail "$VERSION is not newer than $LATEST_TAG"
fi

if grep -qF "## [$VERSION]" CHANGELOG.md; then
  # Already prepared (e.g. the first release, written by hand): only tag it.
  [ "$CURRENT" = "$CORE" ] || fail "CHANGELOG has [$VERSION] but project.yml says $CURRENT"
  # The section may have been written days earlier: date it with the release day.
  ESCAPED="$(printf '%s' "$VERSION" | sed 's/[.]/\\./g')"
  sed -i '' "s/^## \[$ESCAPED\] - .*/## [$VERSION] - $(date +%Y-%m-%d)/" CHANGELOG.md
  if ! git diff --quiet CHANGELOG.md; then
    git commit -q -m "chore(release): $VERSION" CHANGELOG.md
    echo "Committed: chore(release): $VERSION (dated today)"
  fi
  echo "CHANGELOG already has [$VERSION]; tagging it."
else
  python3 - "$VERSION" "$(date +%Y-%m-%d)" "${LATEST_TAG}" "$REPO_URL" <<'PY'
import re, sys
version, date, previous_tag, repo = sys.argv[1:]
path = "CHANGELOG.md"
text = open(path, encoding="utf-8").read()
match = re.search(r"^## \[Unreleased\]\n(.*?)(?=^## \[|^\[Unreleased\]:|\Z)", text, re.S | re.M)
if not match or not match.group(1).strip():
    sys.exit("error: nothing under ## [Unreleased] in CHANGELOG.md; describe the changes first")
body = match.group(1).strip("\n")
text = text[: match.start()] + f"## [Unreleased]\n\n## [{version}] - {date}\n\n{body}\n\n" + text[match.end() :]
# Compare links at the bottom keep every heading clickable.
links = [line for line in text.splitlines() if re.match(r"^\[[^\]]+\]: ", line)]
text = "\n".join(line for line in text.rstrip("\n").splitlines() if line not in links).rstrip("\n")
since = previous_tag or f"v{version}"
links = [l for l in links if not l.startswith("[Unreleased]:")]
new_links = [f"[Unreleased]: {repo}/compare/v{version}...HEAD"]
new_links.append(f"[{version}]: {repo}/compare/{previous_tag}...v{version}" if previous_tag else f"[{version}]: {repo}/releases/tag/v{version}")
text += "\n\n" + "\n".join(new_links + links) + "\n"
open(path, "w", encoding="utf-8").write(text)
PY
  sed -i '' "s/MARKETING_VERSION: .*/MARKETING_VERSION: $CORE/" project.yml
  git add CHANGELOG.md project.yml
  git commit -q -m "chore(release): $VERSION"
  echo "Committed: chore(release): $VERSION"
fi

git tag -a "v$VERSION" -m "MacMD $VERSION"
echo "Tagged v$VERSION. Review with 'git show v$VERSION', then publish with:"
echo "  git push origin main v$VERSION"
