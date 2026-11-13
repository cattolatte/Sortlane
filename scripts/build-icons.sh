#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

logo="Resources/Brand/SortlaneLogo.png"
if [[ ! -s "$logo" ]]; then
    echo "Missing canonical logo: $logo" >&2
    exit 1
fi
mkdir -p .build
staging="$(mktemp -d "$PWD/.build/icons.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
iconset="$staging/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips --resampleHeightWidth "$size" "$size" "$logo" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips --resampleHeightWidth "$retina" "$retina" "$logo" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns --output "$staging/AppIcon.icns" "$iconset"
mv "$staging/AppIcon.icns" Resources/AppIcon.icns
echo "Updated Resources/AppIcon.icns from $logo"
