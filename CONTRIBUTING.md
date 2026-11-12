# Contributing to Sortlane

Bug reports, focused fixes, and usability improvements are welcome. Sortlane is a preview; protecting file contents and keeping moves understandable take priority over adding automation.

## Report a problem

Search the [existing issues](https://github.com/cattolatte/Sortlane/issues) before opening a new report. Include:

- Sortlane version, macOS version, and Mac architecture.
- Steps to reproduce, expected behavior, and observed behavior.
- Whether the issue occurs in the sample workspace.
- A minimal rule or synthetic file example when relevant.

Remove personal filenames, document contents, and private paths from screenshots or logs. Do not attach the app's database or your real documents. For security concerns, follow [SECURITY.md](SECURITY.md).

## Set up the project

Use an Apple Silicon Mac and full Xcode 26 or later. The project targets macOS 26 or later and has been verified locally with Xcode 27.2. There are no external package dependencies.

```sh
git clone https://github.com/cattolatte/Sortlane.git
cd Sortlane
open Sortlane.xcodeproj
```

Choose the **Sortlane** scheme and **My Mac**. Run the native app target to exercise App Sandbox. For a packaged optimized build:

```sh
bash scripts/build-app.sh release
open build/Sortlane.app
```

The raw Swift Package executable does not itself enable the app sandbox. Use the sample workspace when exercising UI move operations.

## Make a change

Keep pull requests focused on a concrete problem. Explain the trigger, resulting behavior, and relevant validation. New app Swift files must also be added to `Sortlane.xcodeproj`; core files are discovered through the Swift package.

Run the core suite:

```sh
swift test
```

For app changes, also build the native Xcode target and check the affected workflow. Changes to moving, paths, journaling, rules, or undo should include regression coverage using disposable fixtures. Tests must never operate on a contributor's Downloads or Documents folders.

## File-operation boundaries

- Keep previews separate from execution; validate again at the point of use.
- Never silently overwrite, delete, or broaden filesystem access.
- Preserve review requirements for manual and document-classification suggestions.
- Treat filenames, imported rules, and document contents as untrusted input.
- Keep operations cancellable at safe boundaries and journal completed changes.
- Document limits instead of promising perfect recovery or universal compatibility.

See the [architecture guide](docs/ARCHITECTURE.md) and [security design](SECURITY.md) before changing the core executor. Update the user guide and changelog when behavior changes.
