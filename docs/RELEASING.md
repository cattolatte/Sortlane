# Releasing Sortlane

Releases are built on Apple Silicon with Xcode 26 or newer. Keep source, version metadata, release notes, and binaries at the same revision.

1. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in `Resources/Info.plist`.
2. Update `CHANGELOG.md` and review the security limitations.
3. Run `swift test` and build the native Xcode app target. Use synthetic files to check scan, selection, move, and Undo.
4. Commit the release source and wait for **Build and test** to pass.
5. Run `bash scripts/package-release.sh`. This builds the optimized app, checks its code signature and architecture, creates a compressed DMG and `.tar.gz`, verifies the DMG, and writes `dist/SHA256SUMS`.
6. Extract the archive and mount the DMG read-only to verify their app signatures and contents. Confirm the app version matches the release tag. Ensure packages contain no local data or credentials.
7. Create an annotated `vX.Y.Z` tag on the checked commit, push it, and publish a GitHub release with both packages and `SHA256SUMS`. Mark early previews as prereleases.

The packaging script refuses to overwrite assets already in `dist`. Move prior packages elsewhere before producing another version. Build products and packages are excluded from source control; distribute them through GitHub Releases. GitHub also provides source archives for each tag.

## Signing status

Current packages use an ad-hoc signature with App Sandbox entitlements. They are **not Developer ID signed or notarized**. Gatekeeper can block downloaded copies; packaging as a DMG does not establish developer trust. Release notes must disclose this status. Do not describe `codesign --verify` as notarization or a security audit.

For a future stable release, use a Developer ID Application certificate, enable the hardened runtime, submit the distribution for Apple notarization, staple the ticket, and validate the downloaded artifact on a separate Mac. Keep signing credentials outside the repository and limit publishing permissions. Complete the remaining verification work in [SECURITY.md](../SECURITY.md) before declaring a stable release.

## Download integrity

Users can put the two packages and `SHA256SUMS` in the same directory, then run:

```sh
shasum -a 256 -c SHA256SUMS
```

Checksums detect corrupted or changed downloads. They do not replace Developer ID signing or notarization.
