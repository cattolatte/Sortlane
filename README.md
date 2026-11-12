# Sortlane

**A little more order for your Mac.**

[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-161B28?logo=apple&logoColor=white)](https://github.com/cattolatte/Sortlane#requirements)
[![Apple Silicon](https://img.shields.io/badge/architecture-Apple_Silicon-635CDC)](https://github.com/cattolatte/Sortlane#download)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](Package.swift)
[![Preview v0.2.0](https://img.shields.io/badge/preview-v0.2.0-635CDC)](https://github.com/cattolatte/Sortlane/releases/tag/v0.2.0)
[![MIT License](https://img.shields.io/badge/license-MIT-36A17D)](LICENSE)
[![Build and test](https://github.com/cattolatte/Sortlane/actions/workflows/ci.yml/badge.svg)](https://github.com/cattolatte/Sortlane/actions/workflows/ci.yml)

Sortlane is a lightweight, native file organizer for macOS. Turn a crowded Downloads folder into a reviewable sorting plan, build precise rules, and find useful document categories with optional Apple Intelligence. Files stay on your Mac.

[Download](https://github.com/cattolatte/Sortlane/releases/tag/v0.2.0) · [User guide](docs/USER_GUIDE.md) · [Changelog](CHANGELOG.md) · [Security](SECURITY.md) · [Contributing](CONTRIBUTING.md)

> **Early preview:** v0.2.0 is ad-hoc signed and is not Developer ID signed or notarized. macOS may block a downloaded copy. For a locally built app, follow the build instructions below. This preview supports moves on the same volume only.

## What it does

- **Preview before organizing.** Search, filter, and sort a file queue, inspect destinations, and select files individually or in batches.
- **Make rules that fit your files.** Combine extensions, filename text, `*` / `?` patterns, exclusions, size limits, and modification age. Route files into folders such as `Documents/{year}/{month}`.
- **Read documents locally.** Apple Intelligence suggests Receipts, Bills, Study, Work, and Personal categories. Vision OCR reads scanned pages and document images. Suggestions always need your selection.
- **Keep a routine.** Watch a folder while the app is open, or opt into automatic moves for eligible rule matches. Manual and Apple Intelligence destinations remain under review.
- **Keep a record.** Every move is journaled locally. Undo checks file identity and content before restoring it.
- **Make it yours.** Light, dark, and system appearances; manual destinations; prioritized rules; JSON rule import and export.

No account, subscription, third-party model bundle, or network client entitlement. The app uses system frameworks and has no external package dependencies.

## Requirements

| | Requirement |
| --- | --- |
| Mac | Apple Silicon |
| Operating system | macOS 26 or later |
| Document suggestions | Apple Intelligence available on the Mac; optional |
| File locations | Regular folders within your home directory, on the same volume |
| Building from source | Full Xcode 26 or later; verified locally with Xcode 27.2 |

The rules engine works when Apple Intelligence is unavailable. Apple's system model still uses system storage and compute; Sortlane does not download its own model.

## Download

Get the files from the [v0.2.0 release](https://github.com/cattolatte/Sortlane/releases/tag/v0.2.0):

| Asset | Use |
| --- | --- |
| `Sortlane-0.2.0-macos-arm64.dmg` | Disk image containing the app |
| `Sortlane-0.2.0-macos-arm64.tar.gz` | Compressed app bundle |
| `SHA256SUMS` | SHA-256 checksums for the release assets |

For the disk image, open it and copy `Sortlane.app` to Applications. For the archive, extract it and move `Sortlane.app` to Applications. Quit an older Sortlane instance before replacing it. These are preview packages with the signing limitations described above.

To check downloaded assets, place them beside `SHA256SUMS`, open Terminal in that folder, and run:

```sh
shasum -a 256 -c SHA256SUMS
```

A checksum detects a changed or incomplete download; it does not replace code signing or notarization. GitHub's automatically generated source archives contain source code, not an installed app.

## First run

1. Choose **Explore sample files** to try a contained demonstration, or select your source and destination folders.
2. Click **Scan folder**. Review the proposed destinations and any conflicts.
3. Optionally use **Refine** for local document suggestions, or inspect a file to choose its destination.
4. Select the files you want to move and click **Organize selected**.
5. Open **Activity → Undo** to restore an unchanged moved file.

Start with a dedicated inbox and a small set of files. Full Disk Access is not needed. See the [user guide](docs/USER_GUIDE.md) for rule examples, automation, and troubleshooting.

## Build and test

```sh
git clone https://github.com/cattolatte/Sortlane.git
cd Sortlane
open Sortlane.xcodeproj
```

Select the **Sortlane** scheme and **My Mac**, then run. The native app target uses App Sandbox and local ad-hoc signing.

Or build an optimized app bundle from Terminal:

```sh
bash scripts/build-app.sh release
open build/Sortlane.app
```

Run the core tests with:

```sh
swift test
```

The v0.2.0 test suite contains 38 tests for path restrictions, conflicts, stale previews, move/undo, journal recovery, rules, and review preservation. Fixtures live under `.build/SecurityFixtures`. Use the Xcode app target or packaged `.app` for normal use: running the raw Swift Package executable does not enable App Sandbox.

## Safety and current limits

Sortlane combines App Sandbox with its own path policy. It rejects system locations, the home root, Library, hidden folders, app libraries, symlinks, and detected source projects. Destinations stay inside the selected output folder. Moves never replace an existing file, and there is no delete feature.

This is early software, and the journal is not a backup. Cross-volume moves, multiple source profiles, duplicate detection, a login helper, and a Finder extension are not implemented. Cloud-only files are skipped. Broader sync-provider, accessibility, large-folder, and adversarial testing remain open work. Read [SECURITY.md](SECURITY.md) for the precise boundaries and limitations.

## Project documentation

- [User guide](docs/USER_GUIDE.md): setup, rules, local suggestions, automation, and recovery.
- [Architecture](docs/ARCHITECTURE.md): modules, execution flow, persistence, and platform frameworks.
- [Contributing](CONTRIBUTING.md): development workflow and reporting issues.
- [Changelog](CHANGELOG.md): changes by version.
- [Security](SECURITY.md): protections, threat model, and release-hardening work.
- [Releasing](docs/RELEASING.md): release checks, packaging, and publication.

## License

Sortlane is available under the [MIT License](LICENSE).
