#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "Release packages currently require an Apple Silicon Mac." >&2
    exit 1
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Expected a numeric major.minor.patch version in Resources/Info.plist." >&2
    exit 1
fi

out_directory="$PWD/dist"
archive_name="Sortlane-${version}-macos-arm64"
mkdir -p "$out_directory"
for asset in "$archive_name.dmg" "$archive_name.tar.gz" SHA256SUMS; do
    if [[ -e "$out_directory/$asset" ]]; then
        echo "Refusing to overwrite dist/$asset. Move existing packages out of dist first." >&2
        exit 1
    fi
done

bash scripts/build-app.sh release
codesign --verify --strict build/Sortlane.app
if [[ "$(lipo -archs build/Sortlane.app/Contents/MacOS/Sortlane)" != "arm64" ]]; then
    echo "Expected an arm64 app executable." >&2
    exit 1
fi

staging="$(mktemp -d "$out_directory/.package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/archive" "$staging/disk"
ditto --norsrc --noextattr build/Sortlane.app "$staging/archive/Sortlane.app"
cp LICENSE "$staging/archive/LICENSE.txt"
cat > "$staging/archive/READ-ME.txt" <<EOF
Sortlane ${version} — macOS preview

Requires macOS 26 or later and an Apple Silicon Mac.
Apple Intelligence is optional; sorting rules work without it.

Move Sortlane.app to Applications, then launch it.
Start with Explore sample files to try sorting and Undo.

This preview is ad-hoc signed, not Developer ID signed or notarized.
Gatekeeper may block downloaded copies. A DMG or archive does not change
that status. Building from source with Xcode is an alternative.

Only same-volume moves are supported. See the security policy for limits.

Project: https://github.com/cattolatte/Sortlane
Guide: https://github.com/cattolatte/Sortlane/blob/main/docs/USER_GUIDE.md
Security: https://github.com/cattolatte/Sortlane/security/policy
License: MIT (included)
EOF
codesign --verify --strict "$staging/archive/Sortlane.app"
COPYFILE_DISABLE=1 tar -czf "$staging/$archive_name.tar.gz" -C "$staging/archive" Sortlane.app LICENSE.txt READ-ME.txt
ditto --norsrc --noextattr "$staging/archive" "$staging/disk"
ln -s /Applications "$staging/disk/Applications"
hdiutil create -quiet -volname "Sortlane $version" -srcfolder "$staging/disk" -format UDZO "$staging/$archive_name.dmg"
hdiutil verify "$staging/$archive_name.dmg"
(
    cd "$staging"
    shasum -a 256 "$archive_name.dmg" "$archive_name.tar.gz" > SHA256SUMS
    shasum -a 256 -c SHA256SUMS
)
mv "$staging/$archive_name.dmg" "$staging/$archive_name.tar.gz" "$staging/SHA256SUMS" "$out_directory/"
echo "Release packages are ready in $out_directory"
