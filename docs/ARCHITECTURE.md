# Architecture

Sortlane is a Swift 6 macOS app with a UI-independent core. It uses system frameworks and has no external package dependencies. The app targets macOS 26 or later; release packages currently target Apple Silicon.

## Components

| Component | Responsibility |
| --- | --- |
| `Sources/Sortlane/SortlaneApp.swift` | App entry point and native window/commands |
| `AppModel.swift` | Main-actor state, folder permissions, task progress, selection, and orchestration |
| `ContentView.swift`, `RuleEditor.swift` | SwiftUI workspace, rules, history, inspector, and editing |
| `FolderWatcher.swift` | FSEvents, debouncing, and periodic reconciliation |
| `AppleClassifier.swift` | Bounded PDF/text/image extraction, Vision OCR, and Foundation Models classification |
| `Sources/SortlaneCore/Models.swift` | Rules, snapshots, proposals, and journal records |
| `RuleMatcher.swift` | Validated conditions, bounded wildcard matching, and date templates |
| `Scanner.swift` | Metadata enumeration, exclusions, matching, and initial conflict checks |
| `ReviewPlan.swift` | Review-state preservation and merged-plan validation |
| `FolderPolicy.swift`, `PathSafety.swift` | Approved roots, protected folders, relative paths, and symlink checks |
| `Organizer.swift` | Serialized execution, content hashing, move/undo, and interruption recovery |
| `Database.swift` | SQLite settings and operation journal |
| `Sources/CSQLite` | Thin import shim for system SQLite |

Both the Swift package and native Xcode app consume the same core. App source files are explicitly listed in the Xcode project. Core package files are discovered by SwiftPM.

## Branding resources

`Resources/Brand/SortlaneLogo.png` is the canonical logo image. The sidebar loads it from the main app bundle. `Resources/AppIcon.icns` contains the macOS icon sizes, and `CFBundleIconFile` in `Resources/Info.plist` identifies it for Finder, the Dock, and the standard About panel.

The Xcode resource phase and the packaging script both include these assets in the app bundle. The repository banner embeds a compact copy of the same logo. After updating the canonical image, run `bash scripts/build-icons.sh` to regenerate the macOS icon sizes and `swift scripts/update-banner.swift` to refresh `docs/assets/banner.svg`. Commit the source artwork and both derived assets together. Branding does not change the core file-operation or permission model.

## Planning and execution

1. Native folder pickers grant access to source and destination folders. Scoped bookmarks preserve that access across launches.
2. The scanner validates roots and rules, enumerates eligible regular files, and captures identity snapshots. It skips unfinished or protected items and cloud placeholders.
3. Enabled rules run in priority order. The first match yields a relative destination. Date templates expand before path validation.
4. The review plan detects existing targets and colliding proposals. Rescans preserve selections and manual or document suggestions for unchanged snapshots, then validate their actual destinations.
5. The executor rechecks roots, containment, symlinks, file identity, target availability, and volume identity. It hashes content and checks metadata again before journaling and renaming.
6. A same-volume `renamex_np` call with `RENAME_EXCL` refuses an existing target. Completion is saved in the journal.

The UI never grants the classifier authority to move files. Automatic execution is restricted to selected, nonconflicting rule proposals. Manual and document-classification proposals require explicit selection.

## Persistence and recovery

Configuration and the SQLite journal live in the app container's Application Support directory. Configuration includes chosen bookmarks, rules, and the recursive-scan setting. Monitoring and automatic execution are not restored as enabled after launch. Classification results and review selections are session state.

SQLite uses synchronous FULL for committed journal writes. A move is recorded as prepared before the filesystem rename and completed afterward. Undo has an equivalent prepared state and verifies recorded identity and content digest before its reverse rename.

Startup reconciles prepared operations by checking recorded identity, content, and both paths. It marks ambiguous cases for review. A SQLite transaction and filesystem rename are separate operations; the journal protocol addresses the interruption gap.

## Concurrency and work limits

`AppModel` runs on the main actor. `Organizer` serializes core operations in its actor, and `AppleClassifier` owns extraction, inference, and its in-memory result cache in a separate actor. Long UI operations expose progress and a cancellation task. Cancellation is checked between safe steps; a framework call already executing may finish first.

FSEvents triggers debounced full scans of the selected source. A 30-second timer also reconciles files that were too new during an earlier scan. The watcher runs only while the app is open.

Rules are validated before scanning. Extension sets are normalized once per matcher, and wildcard matching uses bounded dynamic programming rather than unrestricted regular expressions. Imports are capped at 1 MB and 100 total rules.

## Local document classification

PDFKit reads up to three PDF pages; Vision OCR handles scanned pages and common document images. ImageIO downsizes image input before OCR. The classifier limits input files to 50 MB and extracts at most 4,000 characters for Foundation Models. Source policy and snapshot checks occur before reads, and identity is checked again afterward.

Guided generation returns a fixed document-kind enum. Application code maps it to a fixed relative folder. Filename and document content are untrusted data, and the model has no filesystem tools. A bounded in-memory cache stores at most 128 results associated with unchanged snapshots.

## Platform boundaries

The packaged app has App Sandbox, user-selected read/write access, and app-scoped bookmarks. It has no network client entitlement or Full Disk Access requirement. Core path restrictions apply in addition to sandbox enforcement. Running a bare SwiftPM executable does not activate the packaged app's sandbox.

Current gaps include cross-volume moves, parser isolation, adversarial path-race hardening, broad sync-provider testing, and large-folder scalability testing. See [SECURITY.md](../SECURITY.md) for the threat model and exact checks, and [CONTRIBUTING.md](../CONTRIBUTING.md) for development workflow.
