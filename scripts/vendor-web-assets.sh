#!/usr/bin/env bash
# Downloads the pinned reader libraries into App/Resources/Web/vendor.
# Bump the versions here and in App/Support/WebAssets.swift together, then run `make vendor`.
set -euo pipefail

HIGHLIGHT_VERSION="11.12.0"
KATEX_VERSION="0.18.10"
MERMAID_VERSION="12.0.0"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/App/Resources/Web/vendor"
CDN="https://cdn.jsdelivr.net/npm"

fetch() { # url destination
  mkdir -p "$(dirname "$2")"
  curl --fail --silent --show-error --location "$1" --output "$2"
  echo "  $(shasum -a 256 "$2" | cut -c1-16)  ${2#"$ROOT"/}"
}

rm -rf "$VENDOR"
echo "highlight.js $HIGHLIGHT_VERSION"
for file in highlight.min.js styles/github.min.css styles/github-dark.min.css LICENSE; do
  fetch "$CDN/@highlightjs/cdn-assets@$HIGHLIGHT_VERSION/$file" "$VENDOR/highlight/$(basename "$file")"
done

echo "KaTeX $KATEX_VERSION"
for file in katex.min.js katex.min.css; do
  fetch "$CDN/katex@$KATEX_VERSION/dist/$file" "$VENDOR/katex/$file"
done
fetch "$CDN/katex@$KATEX_VERSION/LICENSE" "$VENDOR/katex/LICENSE"
fonts=$(curl --fail --silent "https://data.jsdelivr.com/v1/packages/npm/katex@$KATEX_VERSION?structure=flat" \
  | python3 -c 'import sys, json; print("\n".join(f["name"] for f in json.load(sys.stdin)["files"] if f["name"].startswith("/dist/fonts/") and f["name"].endswith(".woff2")))')
for font in $fonts; do
  fetch "$CDN/katex@$KATEX_VERSION$font" "$VENDOR/katex/fonts/$(basename "$font")"
done

echo "Mermaid $MERMAID_VERSION"
fetch "$CDN/mermaid@$MERMAID_VERSION/dist/mermaid.min.js" "$VENDOR/mermaid/mermaid.min.js"
fetch "$CDN/mermaid@$MERMAID_VERSION/LICENSE" "$VENDOR/mermaid/LICENSE"

# Drop source-map references; the maps are not shipped.
find "$VENDOR" -name '*.js' -exec sed -i '' -e '/^\/\/# sourceMappingURL=/d' {} +
echo "Done."
