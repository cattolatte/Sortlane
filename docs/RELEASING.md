# Releasing Sortlane

Releases are built on Apple Silicon with Xcode 26 or newer. Keep source, version metadata, release notes, and binaries at the same revision.

1. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in `Resources/Info.plist`.
2. Update `CHANGELOG.md`, current README download links, and the issue-template version placeholder. Review the security limitations.
3. Run `swift test` and build the native Xcode app target. Use synthetic files to check scan, selection, move, and Undo.
4. Commit the release source and wait for **Build and test** to pass.
5. Run `bash scripts/package-release.sh`. This builds the optimized app, checks its code signature and architecture, creates a compressed DMG and `.tar.gz`, verifies the DMG, and writes `dist/SHA256SUMS`.
6. Extract the archive and mount the DMG read-only to verify their app signatures and contents. Confirm the app version matches the release tag and that the app icon and sidebar logo are present. Ensure packages contain no local data or credentials.
7. Create an annotated `vX.Y.Z` tag on the checked commit, push it, and publish a GitHub release with both packages and `SHA256SUMS`. Mark early previews as prereleases.

The packaging script refuses to overwrite assets already in `dist`. Move prior packages elsewhere before producing another version. Build products and packages are excluded from source control; distribute them through GitHub Releases. GitHub also provides source archives for each tag.

## Branding checks

Keep `Resources/Brand/SortlaneLogo.png`, `Resources/AppIcon.icns`, and the repository banner consistent. `CFBundleIconFile` must reference the bundled icon. Both the native Xcode target and packaged app must include the logo and icon resources before code signing.

After updating the canonical logo, run these commands from the repository root:

```sh
bash scripts/build-icons.sh
swift scripts/update-banner.swift
```

The first command regenerates the macOS icon sizes in `Resources/AppIcon.icns`. The second embeds a compact logo copy in `docs/assets/banner.svg`. Commit the canonical image, icon, and banner together.

For an artwork update, inspect the logo at small sizes and check the sidebar, Finder, Dock, and About panel after launching the newly built app. macOS may retain an older icon until the previous app instance is quit and the updated bundle is reopened. Rebuild both release packages from the same checked revision.

## Signing status

Current packages use an ad-hoc signature with App Sandbox entitlements. They are **not Developer ID signed or notarized**. Gatekeeper can block downloaded copies; packaging as a DMG does not establish developer trust. Release notes must disclose this status. Do not describe `codesign --verify` as notarization or a security audit.

For a future stable release, use a Developer ID Application certificate, enable the hardened runtime, submit the distribution for Apple notarization, staple the ticket, and validate the downloaded artifact on a separate Mac. Keep signing credentials outside the repository and limit publishing permissions. Complete the remaining verification work in [SECURITY.md](../SECURITY.md) before declaring a stable release.

## Download integrity

Users can put the two packages and `SHA256SUMS` in the same directory, then run:

```sh
shasum -a 256 -c SHA256SUMS
```

Checksums detect corrupted or changed downloads. They do not replace Developer ID signing or notarization.
