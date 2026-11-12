# User guide

Sortlane organizes regular files from one source folder into category folders inside one destination. It can preview existing files and watch for new ones while the app is open.

## Choose your folders

Start with **Explore sample files** to try synthetic documents in the app's container. To use your own files, click the source and destination cards and choose folders through the macOS picker.

For example, select `Downloads/Inbox` as the source and `Documents/Sorted` as the destination. A rule targeting `Documents/Receipts` will create `Documents/Sorted/Documents/Receipts`. Destinations are always relative to the output folder you selected.

Use separate folders on the same volume. The source cannot be inside the destination. If the destination is within the source, scanning skips that destination subtree. Enable **Subfolders** for recursive scanning.

The home root, system locations, Library, hidden directories, app libraries, symlinks, and detected source-code projects are protected. Put an empty `.sortlane-protected` file in a source directory to exclude it and its descendants. Full Disk Access is not required.

## Review a plan

Click **Scan folder**. A scan reads file metadata and creates proposed destinations; it does not move files in review mode.

Search by name, destination, or explanation and sort by name, size, or modification time. Use **All files**, **Ready**, **Review**, **Conflicts**, or **AI suggestions** to narrow the queue. “Ready” means a valid destination is present, not that the file has been selected.

Rule matches without conflicts start selected. Unknown files, manual destinations, and Apple Intelligence suggestions need your selection. Click a row to inspect its details, choose a relative destination, and click **Apply**. Then select the file when you want to move it.

The batch menu selects or deselects eligible files in the current view. **Changing a search or filter does not clear selections elsewhere.** The footer shows the total selected count. **Organize selected** moves every selected eligible file, including selections hidden by the current view.

## Build sorting rules

Open **Rules library → New rule**. Rules run in priority order, and the first enabled matching rule wins. All populated conditions in a rule must match; empty conditions impose no restriction.

| Condition | Example | Meaning |
| --- | --- | --- |
| File extensions | `pdf, txt` | Match either extension; omit the leading dot |
| Name contains | `invoice` | Case-insensitive substring |
| Name pattern | `invoice-*.pdf` | Match the whole filename; `*` means any characters, `?` means one |
| Exclude names containing | `draft` | Reject names containing that substring |
| Size | At least `1` MB | Decimal megabytes; optional upper and lower bounds |
| Age | Older than `7` days | Time since last modification; fractions such as `0.5` are allowed |
| Folder | `Documents/{year}/{month}` | Relative destination using the file's modification year and month |

To route invoices before the general Documents rule, create a rule with extension `pdf`, pattern `invoice-*.pdf`, and destination `Documents/Invoices/{year}`. Move it above Documents with its menu.

Rules support enable/disable, reordering, duplication, and removal. Changing rules or folders clears the preview and pauses automatic moves. Scan again to review the new plan.

**Export** saves your library as JSON. **Import** validates a JSON library and appends its rules with fresh IDs, initially disabled. Review imported rules before enabling them. Imports are limited to 1 MB, and the library is limited to 100 rules.

## Local document suggestions

Click **Refine** when Apple Intelligence is available. Sortlane considers supported files in the generic Documents or Images categories, plus supported unmatched files. It leaves manually assigned destinations alone.

Supported inputs are PDF, TXT, Markdown, PNG, JPEG, HEIC, TIFF, and WebP. Vision OCR reads text from scanned PDF pages or document images. Recognizing a photograph's visual subject is not supported.

The app supplies bounded document text to Apple's on-device model and maps the result to Receipts, Bills, Study, Work, or Personal. It can leave ambiguous documents unchanged. Suggestions start unselected and cannot move files automatically.

Processing is capped at 50 MB per input, the first three PDF pages, and a 4,000-character excerpt. OCR thumbnails are capped at 1,600 pixels. Files with too little readable text or locked PDFs may receive no suggestion. The app retains up to 128 classification results in memory.

No upload, API key, or separate model download is required by Sortlane. Apple's model must be available on the Mac and uses system resources. If it is unavailable, rules and manual routing still work. Suggestions need review and can be wrong.

## Watch and automate

Open **Review mode** at the bottom of the workspace to configure the routine:

- **Watch for new files** refreshes the queue while Sortlane is open.
- **Move rule matches automatically** opts into moving selected, nonconflicting rule matches during background scans.

The watcher responds to filesystem events and reconciles every 30 seconds. Files modified within the last ten seconds, partial downloads, cloud-only files, hidden items, protected folders, and packages are skipped. A file may appear on a later scan after it finishes writing.

Manual and Apple Intelligence suggestions always stay in review. Monitoring and automatic moves start disabled after launch. Folder or rule changes pause automatic moves; Undo also pauses them. There is no login helper in this preview.

## Stop, history, and Undo

Use **Stop** during a scan, refinement, or move batch to stop at the next safe boundary. A framework call already in progress may finish first. Completed moves remain recorded in **Activity**.

In Activity, search the journal, reveal a file in Finder, or select **Undo**. Undo checks the moved file's identity and SHA-256 digest and refuses to replace a file at the original location. Changed or missing files cannot be restored automatically. If permission to an older location is unavailable, select the relevant folders again.

Startup reconciles interrupted journal entries with the filesystem. Ambiguous situations are marked for review. The journal records paths and hashes locally; it is not a copy of your files and does not replace backups.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| No files appear | Wait for downloads, rescan, check filters, and check for protected or cloud-only files |
| Destination conflict | Resolve the existing file or choose another folder, then rescan; Sortlane will not overwrite it |
| Folder rejected | Use a regular folder inside your home directory, outside protected and project folders |
| File changed since preview | Scan again to obtain a fresh preview |
| Move crosses volumes | Choose a destination on the source volume; cross-volume moves are not implemented |
| Apple Intelligence unavailable | Check the sidebar status; continue using rules or manual destinations |
| Document gets no suggestion | Check format, size, readable text, and PDF lock status |
| macOS blocks a downloaded preview | The release is not notarized; building locally with Xcode is the supported alternative |

See [Security](../SECURITY.md) for the safety model and [Contributing](../CONTRIBUTING.md) for reporting a reproducible problem.
