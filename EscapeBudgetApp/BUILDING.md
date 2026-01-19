# Building Faster (Escape Budget)

## Quick wins

- Prefer a repo-local DerivedData to avoid global build-db hiccups:
  - `xcodebuild -project EscapeBudget.xcodeproj -scheme EscapeBudget -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath ./DerivedDataLocal build`
- If build is “stuck”, try **Product → Clean Build Folder** once, then build again.

## Xcode settings that usually help

- **Build Active Architecture Only** = `Yes` for Debug (faster device/simulator iteration).
- **Debug Information Format** = `DWARF` for Debug (faster than DWARF with dSYM for local dev).
- Keep **Previews** closed if you don’t need them (they can trigger extra builds).

## Why builds are slow here

This codebase has several very large SwiftUI files (e.g. `EscapeBudget/ReviewView.swift`, `EscapeBudget/ImportDataView.swift`). Swift compilation/type-checking tends to dominate overall build time for these.

If you want, the next step is to split those files into smaller subviews/files to improve incremental compile times (no UI behavior change, just organization).

