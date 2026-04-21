## Context

`.note → pdf` output via `note-to-pdf-swift` produces broken pagination on multi-page Notability files with non-uniform stroke distribution. Two prior rounds of fixes landed:

- **Round 1** (v0.1.0 of both packages): reverted by Scope Guard — went too broad trying to recalibrate the entire coordinate transform.
- **Round 2** (`note-core-swift@0.1.3` + `note-to-pdf-swift@0.1.2`, deployed via `#82 d771589` on main): heuristic `pageHeight = (maxY - minY) / pageCount`, pageYOffset derived from stroke `minY`. Improves simple cases but still cuts strokes and misplaces whitespace on multi-page diagrammatic content (observed on 2026-04-17 Wei 家教 test file).

**Phase A investigation** during `/spectra-discuss` resolved the dominant epistemic ambiguity: the issue body's original RCA claimed strokes should be grouped by `kPageLayoutDocumentPageNumberKey`, while `NoteParser.swift:80` comment asserted "strokes have no per-stroke page index". Direct plist inspection (on `test-files/筆記 2026-03-20 15:25:20.note`, a 9-page format-v9 file) confirmed the code comment: strokes live in a flat `SpatialHash.curvespoints` bytes array with no per-curve page key, and `pageLayoutArray` entries carry only `{PageIsBookmarked, PDFPageNumber, PDFIsOriginalPage, DocumentPageNumber}` — no Y offsets.

Stakeholders: `macdoc` CLI end users (primary — `convert --to pdf .note` output currently unreliable for any file with non-trivial content structure); downstream `note-to-html-swift` consumers (parallel fix bundled). Constraints: no paid GitHub tier (affects release flow — see `#80 psychquant-security-defaults`); must stay on `.note` format v9 (v10+ out of scope); test fixtures must not leak personal handwriting content (privacy).

## Goals / Non-Goals

**Goals:**

- Eliminate cross-page stroke cuts on multi-page `.note` files with non-uniform content distribution.
- Reduce observed cumulative drift (currently ~204 pt by page 9 of a 9-page letter-portrait note) to ≤ 20 pt total across any supported page count.
- Maintain backwards compatibility: existing `ParsedNote.pageHeight` + `pageYOffset` keep working for consumers who don't opt into `pageBounds`.
- Apply identical fix to `note-to-html-swift` so HTML output doesn't diverge from PDF output.
- Keep fix discoverable in audit trail: tags, Package.swift pin bumps, and changelog entries reference this change.

**Non-Goals:**

- Schema-driven fix via per-stroke page attribution — Phase A proved the schema doesn't expose that data.
- `recordingTimestampString`-based temporal clustering — deferred alternative; not implemented in this change.
- A4 / legal / landscape PDF output support.
- `.note` format v10+ support or migration plumbing.
- Visual perceptual-diff regression harness — deferred.
- Per-stroke attribution via pre-rendering + OCR — computationally prohibitive, out of scope.

## Decisions

### Expose pageBounds as optional additive field on ParsedNote

Add `public let pageBounds: [PageBounds]` to `ParsedNote` where `PageBounds` is a new public struct `{yStart: Float, yEnd: Float, documentPageNumber: Int}`. Optional because consumers written against `0.1.3` continue working — they read `pageHeight` + `pageYOffset` as before. `PageBounds` is additive, not replacement. Alternatives: (a) replace `pageHeight`/`pageYOffset` entirely → rejected because breaks downstream `note-to-html-swift@0.1.0`; (b) separate `ParsedNote2` type → rejected as unnecessary API surface bloat.

### Gutter-gap detection as primary page-boundary source

Compute Y-histogram of stroke points, identify contiguous Y ranges where point density falls below `quietBandThreshold` (empirical: 1% of peak density) AND the band is at least `minGutterHeight` tall (empirical: 40 pt). When `pageCount - 1` such gutters are found, they define page boundaries. Populate `pageBounds` accordingly. Alternatives: (a) k-means clustering on stroke centroids with k=pageCount → more complex implementation for marginal gain; (b) use `paperSize`-derived aspect ratio → already proven wrong (22.7 pt/page drift).

### Fallback to current even-split heuristic when gutters are insufficient

When fewer than `pageCount - 1` gutters are detected (e.g., one very long diagram bridging two pages with no quiet band), fall back to even-split as current R2 code does, but populate `pageBounds` from that even-split so downstream consumers receive consistent data shape. Document in `PageBounds` that `.fallback` origin is possible. Alternatives: (a) propagate `nil` when uncertain → rejected because consumers then need to replicate the even-split logic; (b) refuse to return a ParsedNote on ambiguity → rejected as hostile UX.

### Render strokes by bounding-box intersection, not first-point-only

Current R2 code: `guard firstY >= pageYStart && firstY < pageYEnd else { continue }` — a stroke starting on page 3 but extending 60 pt into page 4's top drops its tail silently (reported as "diagram cut" symptom). New behavior: compute `curveBoundsY = (curve.points.map(\.y).min, ...max)`; include curve on whichever page's `[yStart, yEnd)` contains the most overlap with `curveBoundsY`. If exactly tied or curve spans three pages, include on the page containing the curve's midpoint. Alternatives: (a) split the curve at page boundary → complex, may produce visual artifacts at page break; (b) render curve on all pages it touches → duplicates ink, incorrect; (c) always use first-point → current buggy behavior.

### Bundle note-to-html-swift patch, release three tags together

`note-to-html-swift@0.1.1` receives the same pageBounds-driven iteration. Three tags ship together (`note-core-swift@0.1.4`, `note-to-pdf-swift@0.1.3`, `note-to-html-swift@0.1.1`). macdoc `Package.swift` bumps pins atomically in a single PR. Alternatives: (a) stagger releases → risks `note-to-html-swift` drifting out of sync with `note-core-swift`, exactly what's currently broken; (b) publish only `note-core-swift` + `note-to-pdf-swift`, defer HTML → leaves #86 and HTML consumers broken.

### Additive API means patch-level bumps, not minor

`ParsedNote` adds a new field; no existing field's type or behavior changes. Swift source compatibility is preserved (code compiled against 0.1.3 continues to compile against 0.1.4). Consumers gain access to `pageBounds` by opt-in (read the field) but are not forced to change. Per semver, a purely additive non-breaking change is patch-level. Alternatives: (a) 0.2.0 minor bump → would be correct semver for public Swift library, but since these packages are all PsychQuant-internal with a single consumer (`macdoc`), the practical blast radius is smaller and patch bump keeps the release-notes noise proportionate.

### Smoke assertion strengthens existing NotePDFConvertTests rather than new test file

Extend the `NotePDFConvertTests.swift` `.note → pdf` smoke test (per #81) with a new assertion: parse the generated PDF, extract each page's content-stream stroke bounding boxes, assert no stroke's bounding box is split across page breaks. Reuses existing fixture-skip pattern (`XCTSkip` when `test-files/*.note` not present). Alternatives: (a) new test file → fragments test ownership of the same capability; (b) visual diff harness → overbuilt for this change's verification needs.

## Risks / Trade-offs

- **Risk**: Gutter-gap detection fails silently on a note where the user writes continuously across page breaks (no quiet band). → **Mitigation**: fallback path populates pageBounds via even-split; verified with same smoke test. Document limitation in `PageBounds` docstring.
- **Risk**: Bounding-box overlap allocation makes the "right" choice for simple diagrams but misassigns a long vertical stroke that truly sits on a page break. → **Mitigation**: midpoint tiebreaker; future work can add diagonal-stroke detection. Accept known limitation.
- **Risk**: Three-tag release cascade is fragile — if `note-core-swift@0.1.4` is tagged but `note-to-pdf-swift@0.1.3` isn't yet, macdoc's `swift package update` can pull inconsistent versions. → **Mitigation**: `tasks.md` orders tags tightly; pre-release audit via `./scripts/audit-security.sh` per repo confirms baseline before tagging; the three tags happen within a single working session.
- **Risk**: Adding `pageBounds` to `ParsedNote` may confuse consumers who see both `pageHeight`/`pageYOffset` and `pageBounds` and don't know which is authoritative. → **Mitigation**: docstring on `pageBounds` explicitly states "when non-empty, these are authoritative and `pageHeight`/`pageYOffset` are derived values kept for backwards compatibility".
- **Risk**: `note-to-html-swift@0.1.1` code path may be subtly different from `note-to-pdf-swift@0.1.3` even with same intent, leaking divergent rendering between PDF and HTML. → **Mitigation**: both converters use the same `ParsedNote.pageBounds` source of truth; rendering loops share identical structure; code review comparison before tagging.
- **Risk**: Performance regression if Y-histogram computation is O(numpoints × pageCount) naively. Test file has 83,250 points. → **Mitigation**: single-pass histogram bucket-count per point → O(numpoints); scan buckets once for gutters → O(buckets). Total O(numpoints + buckets), negligible for 100K-point files.
- **Risk**: Test-fixture privacy — existing `.note` file contains handwritten notes from a tutoring session. → **Mitigation**: fixture stays in `.gitignore`'d `test-files/`; not committed; test suite uses `XCTSkip` gracefully when fixture absent (already implemented per #81).
- **Trade-off**: Patch-level bump vs minor-level bump for `note-core-swift`. Chose patch because no API breakage; documented rationale in Decisions. If external consumers appear later, revisit.

## Migration Plan

**Pre-flight**: confirm current `main` state — `note-core-swift@0.1.3` + `note-to-pdf-swift@0.1.2` + `note-to-html-swift@0.1.0` pinned in `macdoc/Package.swift`. If not, resolve upstream drift first.

**Phase 1 — `note-core-swift@0.1.4`**:
1. Add `PageBounds` struct to `NoteCore`.
2. Add `gutterDetection(strokes:pageCount:minGutterHeight:quietBandThreshold:)` to `NoteParser`.
3. Wire into `parse(...)`: compute gutters; if ≥ `pageCount - 1` found, populate `pageBounds`; else fallback even-split (still populates pageBounds).
4. Demote `logicalPageHeight(...)` to fallback-only; update docstring.
5. Add unit tests on synthetic stroke arrays (multi-page, uniform-distribution, non-uniform, edge case with zero gutters).
6. Local `swift test` green → commit → tag `v0.1.4` → push.

**Phase 2 — `note-to-pdf-swift@0.1.3`**:
1. Rewrite `NoteToPDFConverter.convert(note:)` page iteration to use `note.pageBounds` when present.
2. Change stroke filter from `firstY in [pageYStart, pageYEnd)` to bounding-box overlap allocation with midpoint tiebreaker.
3. Keep fallback path for empty pageBounds.
4. Bump `note-core-swift` dep in `Package.swift` from `0.1.3` to `0.1.4`.
5. `swift test` → commit → tag `v0.1.3` → push.

**Phase 3 — `note-to-html-swift@0.1.1`**:
1. Mirror Phase 2's iteration changes on the HTML converter.
2. Bump `note-core-swift` dep from `0.1.3` to `0.1.4`.
3. `swift test` → commit → tag `v0.1.1` → push.

**Phase 4 — `macdoc` Package.swift + smoke assertion**:
1. Bump three pins in `macdoc/Package.swift`.
2. Extend `NotePDFConvertTests.swift` with no-cross-page-strokes assertion (per #81 patterns).
3. `swift build && swift test` locally (expect `XCTSkip` if no test-files `.note` fixture).
4. Run `./scripts/audit-security.sh macdoc` to confirm security baseline unaffected (per #80 release flow).
5. Open PR with title `fix: note pagination gutter heuristic (#77) (#86)` referencing this change.

**Rollback**: three-tag cascade is symmetric. Revert `macdoc/Package.swift` to previous pins; `git revert` on the three package tags; `git push` new tags with `-rollback` suffix (never delete old tags). Rollback leaves audit trail intact.

## Open Questions

None — all 7 open questions surfaced in diagnosis were resolved during `/spectra-discuss`:

1. Epistemic gap (schema vs heuristic) → resolved: heuristic is the only path.
2. Gutter-gap vs temporal clustering → resolved: gutter-gap primary, temporal deferred.
3. `paperSize` aspect-ratio helper → resolved: demote to last-ditch fallback.
4. Bundle `note-to-html-swift` → resolved: bundled.
5. Semver discipline → resolved: patch bump, rationale documented.
6. Test fixture strategy → resolved: continue `test-files/*.note` XCTSkip pattern; synthetic fixture is follow-up.
7. Fallback UX for unresolvable cases → resolved: even-split fallback populates pageBounds; documented.
