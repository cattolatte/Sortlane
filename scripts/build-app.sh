#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-debug}"
if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
    echo "Usage: bash scripts/build-app.sh [debug|release]" >&2
    exit 2
fi
for resource in Resources/AppIcon.icns Resources/Brand/SortlaneLogo.png; do
    if [[ ! -s "$resource" ]]; then
        echo "Required brand resource is missing or empty: $resource" >&2
        exit 1
    fi
done
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
build_flags=(--cache-path .build/cache --config-path .build/config --security-path .build/security)
if [[ "${SORTLANE_RESTRICTED_BUILD:-0}" == "1" ]]; then
    build_flags+=(--disable-sandbox)
fi
swift build "${build_flags[@]}" -c "$configuration"
binary_directory="$(swift build "${build_flags[@]}" -c "$configuration" --show-bin-path)"
app_directory="$PWD/build/Sortlane.app"
mkdir -p "$app_directory/Contents/MacOS" "$app_directory/Contents/Resources"
cp "$binary_directory/Sortlane" "$app_directory/Contents/MacOS/Sortlane.next"
mv -f "$app_directory/Contents/MacOS/Sortlane.next" "$app_directory/Contents/MacOS/Sortlane"
cp Resources/Info.plist "$app_directory/Contents/Info.plist"
cp Resources/AppIcon.icns "$app_directory/Contents/Resources/AppIcon.icns"
cp Resources/Brand/SortlaneLogo.png "$app_directory/Contents/Resources/SortlaneLogo.png"
codesign --force --sign - --entitlements Resources/Sortlane.entitlements "$app_directory"
codesign --verify --strict "$app_directory"
echo "Built sandboxed app: $app_directory"
