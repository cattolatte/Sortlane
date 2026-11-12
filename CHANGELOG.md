# Changelog

Notable changes to Sortlane are recorded here. Version 0.2.0 is the first published preview.

## [0.2.0] — 2026-11-13

### Added

- A native review workspace with light, dark, and system appearances, search, filters, sorting, batch selection, and a file inspector.
- Six default categories: Documents, Images, Videos, Audio, Archives, and Installers.
- Prioritized rules with extension, filename text, wildcard, exclusion, size, and modification-age conditions.
- Destination templates using `{year}` and `{month}` from a file's modification date.
- Manual destinations and validated JSON rule import/export. Imported rules start disabled.
- Apple Intelligence document suggestions with on-device OCR for scanned PDF pages and common document images.
- Folder watching and optional automatic moves for eligible rule matches while the app is open.
- Progress and Stop controls for scans, document classification, and move batches.
- A persistent SQLite move journal, checked Undo, and startup reconciliation for interrupted operations.
- A sample workspace with synthetic text documents and a scanned receipt.

### Safety and reliability

- App Sandbox with user-selected folder access and scoped bookmarks.
- Independent path restrictions, protected-folder markers, project exclusions, and symlink rejection.
- File identity revalidation, content digests, exclusive same-volume renames, and destination-conflict detection.
- Preservation of manual destinations, document suggestions, selections, and inspected-file identity across eligible rescans.
- Revalidation before document reads and bounded extraction, OCR, and classification caching.
- Rule validation, bounded wildcard matching, and safe duplication of maximum-length rule names.
- A 38-test core regression suite.

### Known limits

- Preview packages are ad-hoc signed and are not notarized.
- Moves are restricted to the same volume and supported folders within the home directory.
- Cloud-only files, encrypted PDFs, and unsupported document formats are not read for suggestions.
- Document suggestions can be wrong and always require review.
- No multi-source profiles, duplicate detection, login helper, or Finder extension.
- Additional parser isolation, concurrency testing, accessibility testing, and release signing remain planned work.

[0.2.0]: https://github.com/cattolatte/Sortlane/releases/tag/v0.2.0
