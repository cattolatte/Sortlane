# Security design — early preview

Sortlane is designed to keep the scope of a mistake small. These controls are engineering boundaries, not a claim that early software is infallible or a replacement for backups.

## Reporting a vulnerability

Use [GitHub's private vulnerability reporting](https://github.com/cattolatte/Sortlane/security/advisories/new) for security issues. Include the version, macOS version, impact, and reproduction steps using synthetic files where possible. Do not publish sensitive files, filenames, local paths, or exploit details in a public issue. General bugs can go to [Issues](https://github.com/cattolatte/Sortlane/issues).

The latest 0.2.x preview is the currently maintained version. Fixes are delivered in new releases; no response-time or support-term guarantee is offered.

## Access

The signed `.app` has App Sandbox, user-selected read/write access, and app-scoped bookmarks. It has no network, Apple Events, camera, microphone, or broad filesystem entitlements. Do not grant Full Disk Access; the app does not need it. User grants are obtained through the native folder picker, not by scanning the home directory automatically.

Core file operations separately enforce approved roots. In production those are the user's home directory and a narrowly scoped internal demo directory. Selecting the home root itself is forbidden. Library, Applications, hidden directories, app bundles, media libraries, known dependency directories, and detected source-code projects are excluded. Tests inject only their own disposable fixture root.

## Planning and moving

Scanning only reads metadata. Known temporary downloads, recently modified files, cloud placeholders, symlinks, directories, packages, and protected subtrees are skipped. A ten-second minimum modification age is a conservative heuristic, not proof that another process has closed the file.

Before moving, the executor validates both selected roots, the source's containment, the destination's relative path and containment, and path-component symlinks. It checks source volume/inode, size, and modification time against the preview, hashes the file in bounded chunks, then checks the metadata again. Unsupported or conflicting operations fail without overwriting.

The first release only uses same-volume `renamex_np(..., RENAME_EXCL)`. A rename fails if the target exists. It does not use shell commands, replace existing files, or implement delete. Concurrent local processes can still mutate files; the app must not claim to defeat an actively malicious process with the same user's permissions. Descriptor-relative, no-follow traversal and stronger coordination are future hardening work for path races.

## Journal and undo

A SQLite journal entry commits with synchronous FULL before each move. Completion is recorded afterward. Undo verifies recorded identity and a SHA-256 digest, refuses an occupied original path, and journals the reverse rename. Startup reconciles prepared moves with the current filesystem and marks ambiguous cases for review rather than guessing. Database transactions and filesystem renames are not one atomic transaction; the prepared/completed protocol addresses that gap.

Undo pauses automatic moves. Changed/missing files or unavailable permissions can make undo unavailable. History is an audit trail, not a full file backup. Paths and hashes are stored locally in the sandbox container; file contents and model prompts are not persisted by this app.

## AI and document parsing

Foundation Models uses the system on-device model. Only bounded text excerpts are supplied. On-device Vision OCR is used for scanned pages and images. AI inputs are capped at 50 MB; at most three PDF pages and 4,000 text characters are processed, and OCR images are downscaled to at most 1,600 pixels. Source identity and symlink/ancestor protection are checked again before AI reads. Document text and filenames are explicitly untrusted. The model receives no tools and produces an enum-based document category through guided generation. Code maps categories to a fixed set of relative folders. Even if a document tricks the model into a wrong category, it cannot generate a shell command, arbitrary absolute path, or tool call.

AI and manually assigned destinations require user selection and are excluded from automatic rule moves. The core executor validates them exactly like any other plan. Rescans preserve unapproved suggestions for unchanged files. Rules remain available when the model is unavailable.

This version parses PDFs in the sandboxed app process via PDFKit. An isolated parser service and hostile-document fuzzing remain work before a stable release. Cancellation is checked between extraction, OCR, inference, and file operations; a framework call already in progress may finish first. Archive extraction is not implemented.

## Verification and release gate

Automated tests cover path traversal, protected folders, symlinks, forged proposals, late destination collisions, stale previews, modified content during undo, duplicate plans, persistent journals, interruption recovery, and review-state preservation. UI smoke tests use synthetic documents in the app's sample directory.

Before stable release: independent security review, adversarial path/concurrency tests, power-loss recovery exercises, iCloud/external-volume testing, parser isolation and fuzzing, scalability limits, accessibility testing, and Developer ID signing/notarization. Published 0.2.x packages are ad-hoc signed previews and may be blocked by Gatekeeper on download.

## Rules and imports

Imported rule JSON is bounded to 1 MB and 100 total rules, validated, assigned fresh IDs, and appended disabled. Imports do not run rules. Patterns use a bounded wildcard matcher (`*` and `?`) rather than executable expressions or scripts. Templates expand only `{year}` and `{month}`, followed by the usual destination validation. Changing rules or folders pauses automatic moves.
