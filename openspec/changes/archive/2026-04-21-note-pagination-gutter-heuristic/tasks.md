## 1. Phase 1: note-core-swift@0.1.4 — ParsedNote exposes per-page Y bounds via PageBounds + gutter-gap detection identifies page boundaries from stroke density

- [x] 1.1 In `Sources/NoteCore/NoteParser.swift`, add a public `struct PageBounds` with fields `yStart: Float`, `yEnd: Float`, `documentPageNumber: Int` (per design decision: expose pageBounds as optional additive field on ParsedNote).
- [x] 1.2 Extend `public struct ParsedNote` so that ParsedNote exposes per-page Y bounds via PageBounds: add `public let pageBounds: [PageBounds]` as a new additive field; keep existing `pageHeight` and `pageYOffset` derived-or-fallback-consistent (additive API means patch-level bumps, not minor).
- [x] 1.3 Implement `internal static func gutterDetection(strokes:pageCount:minGutterHeight:quietBandThreshold:) -> [PageBounds]` so that Gutter-gap detection identifies page boundaries from stroke density: single-pass Y-histogram (O(numpoints)), bucket scan for contiguous near-zero-density bands ≥ minGutterHeight meeting quietBandThreshold; return exactly `pageCount` PageBounds when `pageCount - 1` gutters are found, else empty array (per design decision: gutter-gap detection as primary page-boundary source).
- [x] 1.4 Implement even-split fallback populates pageBounds when gutter detection is inconclusive — i.e., fallback to current even-split heuristic when gutters are insufficient: when `gutterDetection` returns empty, derive `[PageBounds]` from the existing `heuristicPageBounds(bounds:pageCount:)` call's output (wraps pageYOffset + pageHeight × i across pageCount entries) so consumers always receive a populated `pageBounds` for non-zero-stroke notes.
- [x] 1.5 Ensure logicalPageHeight paper-size helper is demoted to last-resort fallback: docstring updated with 22.7 pt/page drift caveat + "SHALL NOT be primary" directive; no call site in `parse(...)` invokes it (parse uses gutterDetection → evenSplitPageBounds chain instead).
- [x] 1.6 Add unit tests in `Tests/NoteCoreTests/GutterDetectionTests.swift` covering: threePages-with-clear-gutters, no-gutters-returns-empty, wrong-gutter-count-returns-empty, zero-strokes-returns-empty, single-page-returns-empty, narrow-gutter-disqualified, evenSplit-populates-pageCount, evenSplit-zero-pageCount, evenSplit-zero-pageHeight — 10 new tests.
- [x] 1.7 `swift test` green (21 tests pass); next: commit + tag + push.

## 2. Phase 2: note-to-pdf-swift@0.1.3 — NoteToPDFConverter iterates ParsedNote.pageBounds when available + stroke allocation by bounding-box overlap with midpoint tiebreaker

- [x] 2.1 Rewrote `NoteToPDFConverter.convert(note:)` with `renderUsingPageBounds(...)` (primary) and `renderUsingLegacyEvenSplit(...)` (fallback) branches. When `note.pageBounds` is non-empty, iterate entries in order; else fall back.
- [x] 2.2 Implemented `NoteToPDFConverter.allocateToPage(minY:maxY:pageBounds:)` static helper — computes per-page overlap with curve's Y bounding box, returns `pageIndex` with largest overlap.
- [x] 2.3 Tied overlap and 3+-page spans use midpoint tiebreaker via `pageContainingMidpoint(...)` helper; curve drawn fully on midpoint-containing page.
- [x] 2.4 Legacy fallback (`renderUsingLegacyEvenSplit`) preserves the original `firstY in [pageYStart, pageYEnd)` filter + `0..<pageCount` loop for zero-stroke notes.
- [x] 2.5 `allocateImages(...)` applies same bounding-box overlap allocation to `NoteImage` (Y range from `originY..originY+height`); images without position metadata skipped.
- [x] 2.6 `Package.swift` kept at `from: "0.1.3"` which already admits `0.1.4`; `Package.resolved` locks to `0.1.4` (rev `9ccb8ac`). Functionally equivalent to explicit bump.
- [x] 2.7 `swift test` green (7 AllocationTests), commit `fix: iterate pageBounds + bounding-box allocation (#77)`, tag `v0.1.3`, push origin main + tag (rev `6ebd5ff`).

## 3. Phase 3: note-to-html-swift@0.1.1 — bundle note-to-html-swift patch, release three tags together

- [x] 3.1 Applied pagebounds fix in two places (HTML is JSON-emit + JS-render, not pure Swift page iteration): (a) `NoteConverter.buildJSON(...)` emits `pageBounds` when populated; (b) `PlayerTemplate.playerJS(...)` print-mode loop consumes `data.pageBounds` with bounding-box overlap + midpoint tiebreaker identical to Phase 2. Main scrollable canvas unchanged.
- [x] 3.2 Bumped note-core-swift to `from: "0.1.4"`; Package.resolved locks to 0.1.4 (rev 9ccb8ac).
- [x] 3.3 `swift build` green (no test target present → "no tests found" is expected not a failure); commit `fix: emit pageBounds in JSON + pageBounds-driven print mode (#77) (#86)`, tag `v0.1.1`, push origin main + tag (rev aceac08).
- [~] 3.4 Visual comparison deferred — needs human judgment + `.note` fixture; recommend post-Phase-4 manual check by running `macdoc convert --to pdf X.note` + `macdoc convert --to html X.note --output X-html/` on same file.

## 4. Phase 4: macdoc integration — smoke assertion strengthens existing NotePDFConvertTests rather than new test file + security baseline re-audit

- [ ] 4.1 In `macdoc/Package.swift`, bump three pins atomically: `note-core-swift` → `from: "0.1.4"`, `note-to-pdf-swift` → `from: "0.1.3"`, `note-to-html-swift` → `from: "0.1.1"`.
- [ ] 4.2 Run `swift package update` + `swift build` in `macdoc` repo root; expect clean build with no compile errors from ParsedNote additive field.
- [ ] 4.3 Extend `Tests/MacDocCLITests/NotePDFConvertTests.swift` with a no-cross-page-strokes smoke assertion: parse the generated PDF via PDFKit, extract each page's stroke bounding boxes, assert no single stroke bounding box crosses the PDF page-break line by more than a small epsilon (e.g., 2 pt). Continue to `XCTSkip` when `test-files/*.note` fixture is absent, per the existing #81 pattern.
- [ ] 4.4 Run `swift test` — expect either PASS (with fixture present) or XCTSkip (without) — no regressions.
- [ ] 4.5 Run `./scripts/audit-security.sh macdoc note-core-swift note-to-pdf-swift note-to-html-swift` to confirm the `#80 psychquant-security-defaults` baseline remains green across the 4 affected repos (drift check pre-PR).
- [ ] 4.6 Commit `chore: bump note-* pins + no-cross-page-strokes smoke (#77) (#86)`; push branch; open PR against `main` with title referencing `#77` and `#86`.
- [ ] 4.7 Close `#77` via `/idd-close #77` after PR merges (Closing Summary referencing the 3-tag cascade + the `note-pagination-gutter-heuristic` Spectra change); close `#86` similarly if the smoke assertion satisfies its ask.
