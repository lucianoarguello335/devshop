#!/bin/bash
# Downloads Simple Icons brand marks and emits a compact JSON map of SVG path data.
#
#   slug -> { "p": "<path d>", "c": "<brand hex>" }
#
# Simple Icons ships every mark as a single 24x24 <path>, which the app renders
# directly with SwiftUI's Path. Icon files are CC0; trademarks belong to their owners.
set -euo pipefail

cd "$(dirname "$0")/.."
SLUGS="Scripts/icon-slugs.txt"
OUT="Sources/DevShop/UI/Theme/icons.json"
CDN="https://cdn.jsdelivr.net/npm/simple-icons@15/icons"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

missing=()
printf '{\n' > "$TMP/out.json"
first=1

while read -r slug; do
  [ -z "$slug" ] && continue
  svg="$TMP/$slug.svg"
  if ! curl -fsSL "$CDN/$slug.svg" -o "$svg"; then
    missing+=("$slug")
    continue
  fi
  # Single-path extraction: everything between the first d=" and its closing quote.
  d="$(perl -0777 -ne 'print $1 if /<path[^>]*\sd="([^"]+)"/s' "$svg")"
  if [ -z "$d" ]; then missing+=("$slug"); continue; fi
  [ $first -eq 0 ] && printf ',\n' >> "$TMP/out.json"
  first=0
  printf '  "%s": "%s"' "$slug" "$d" >> "$TMP/out.json"
  printf '.' >&2
done < <(sort -u "$SLUGS")

printf '\n}\n' >> "$TMP/out.json"
mkdir -p "$(dirname "$OUT")"
mv "$TMP/out.json" "$OUT"

echo "" >&2
echo "wrote $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes, $(grep -c '":' "$OUT") icons)" >&2
if [ ${#missing[@]} -gt 0 ]; then
  echo "no mark on Simple Icons (app falls back to SF Symbols): ${missing[*]}" >&2
fi
