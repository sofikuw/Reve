# AGENTS.md

## Versioning

- The app starts at `1.0.0` (beta #001). `pubspec.yaml` carries the number; the
  workflow derives tag, APK names and version code from it.
- Bump the version by `0.0.1` only when a release adds, removes or visibly
  changes **at least five** user-facing things. Fixes, refactors and CI edits
  ship as another build (`#002`, `#003`, …) of the same version.
- Never reuse a version + channel build number: tags are the counter.

## Checks

- No Flutter SDK here. Verify Dart edits with `tree-sitter` +
  `tree_sitter_dart` (zero `ERROR` / missing nodes) and let CI do the real
  compile.
