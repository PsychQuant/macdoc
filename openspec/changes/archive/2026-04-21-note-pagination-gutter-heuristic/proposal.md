## Why

`.note → pdf` conversion (tracked in PsychQuant/macdoc#77) ships broken output on multi-page Notability files with non-uniform content distribution. Round-1 fix was reverted (Scope Guard), round-2 heuristic (`pageHeight = (maxY - minY) / pageCount` even-split) is deployed on `main` but still produces cut strokes and whitespace misplacement — follow-up evidence (2026-04-17 Wei 家教 `.note`) confirms the regression.

Phase A investigation (performed during `/spectra-discuss` on 2026-04-21) resolved an epistemic gap between the issue body's RCA and the current `NoteParser.swift:80` code comment by inspecting a 9-page `.note` file empirically:

- `.note` format v9 **has no per-stroke page attribution** (SpatialHash contains flat `curvespoints`/`curveUUIDs`/... arrays, not grouped by page).
- `pageLayoutArray` entries expose only 4 keys (`PageIsBookmarked`, `PDFPageNumber`, `PDFIsOriginalPage`, `DocumentPageNumber`) — **no Y offsets, no page heights**.
- `reflowState` exposes only `pageWidthInDocumentCoordsKey` (583.8 pt for iPad) — **no pageHeight**.
- Stroke coordinates form a **flat global canvas**: X ∈ [16.57, 559.64], Y ∈ [35.69, 6595.16] for the 9-page test file.

A schema-driven fix is therefore not possible; the fix must be a smarter heuristic. The existing even-split heuristic fails because (a) it assumes uniform stroke distribution per page (violated when one page has a diagram + next is sparse), (b) it derives pageHeight that drifts ~22.7 pt per page compared to Notability's internal rendering (observed 204 pt cumulative drift by page 9), (c) it uses first-point-only check so a stroke spanning a page boundary gets orphaned into the wrong page.

## What Changes

- **New `PageBounds` API** on `note-core-swift` — `ParsedNote` gains optional `pageBounds: [PageBounds]` field where each entry is `{yStart: Float, yEnd: Float, documentPageNumber: Int}`. Preserves existing `pageHeight` / `pageYOffset` for backwards compatibility (derived from pageBounds when new field is populated).
- **New gutter-gap detection** in `note-core-swift` — scan stroke Y distribution for bands of near-zero density (width ≥ `minGutterHeight`). When `pageCount` gutters are found, they define `pageBounds`. When fewer (or zero) gutters are detected, fall back to even-split heuristic as today.
- **NoteToPDFConverter rewrite** in `note-to-pdf-swift` — iterate `ParsedNote.pageBounds` when available (one PDF page per `PageBounds` entry), filter strokes by full bounding box (not first-point-only) so cross-boundary strokes render completely on the page that contains most of their area. Fall back to current heuristic iteration when `pageBounds` is empty.
- **NoteToHTMLConverter parallel fix** in `note-to-html-swift` — apply identical pageBounds-driven iteration. Ships in the same patch wave to prevent divergence from the PDF output.
- **Drop `logicalPageHeight(paperSize:)` helper** in `NoteParser.swift` as a pageHeight source — it produces 755.5 pt for letter but empirical files use ~728-733 pt. Keep the function only as a last-ditch fallback (documented in its docstring) when both gutter detection and stroke-bounds fail.
- **CLI smoke test** in `macdoc` updates — extend `NotePDFConvertTests` to assert: page count matches source, no single curve spans two pages in output PDF (detected via per-page stroke bounding-box checks on the generated PDF).

## Non-Goals

- **No schema change discovery round** — Phase A investigation proved no further hidden per-stroke page attribution exists in `.note` v9. Not re-investigating.
- **No `recordingTimestampString`-based temporal clustering** — kept as deferred alternative if gutter-gap detection proves unreliable in production; out of scope for this change.
- **No A4 / legal / landscape PDF output support** — deferred to a separate follow-up. Output remains US Letter portrait.
- **No `.note` file format v10+ support** — `sessionFormatVersion: 9` is the only target. Format migration is separate work.
- **No visual perceptual diff harness** — nice-to-have but beyond this change's minimal viable scope. Smoke assertions + manual verification remain the test gate.
- **No per-stroke page attribution inference by PDF pre-rendering** (i.e., "render to PDF, OCR, find page break") — out of scope; far too expensive computationally.
- **No upgrade to GitHub Pro / paid features** — unrelated to this bug but mentioned because the `openspec/specs/repository-security-baseline` baseline constrains `note-*-swift` downstream packages; this change respects those constraints.

## Capabilities

### New Capabilities

(none — all fixes extend existing capabilities)

### Modified Capabilities

- `note-core-parsing`: add `pageBounds: [PageBounds]` field on `ParsedNote`; `NoteParser` runs gutter-gap detection and populates pageBounds when ≥1 gutter is found; existing `pageHeight`/`pageYOffset` fields retained for backwards compatibility (derived from pageBounds or fallback to even-split).
- `note-to-pdf-conversion`: `NoteToPDFConverter` iterates `ParsedNote.pageBounds` when present, filters strokes by per-page bounding-box intersection (not first-point-only), falls back to current even-split iteration when pageBounds is empty.

## Impact

- **Affected specs**: 2 modified — `note-core-parsing`, `note-to-pdf-conversion`. No new capabilities.
- **Affected code**:
  - `packages/note-core-swift/Sources/NoteCore/NoteParser.swift` — add `PageBounds` struct; add `gutterDetection(...)` free function; wire into `parse(...)`; demote `logicalPageHeight(...)` to fallback-only.
  - `packages/note-core-swift/Sources/NoteCore/StrokeDecoder.swift` — possibly expose Y-histogram helper if gutter detection needs raw stroke-point access.
  - `packages/note-to-pdf-swift/Sources/NoteToPDF/NoteToPDFConverter.swift` — rewrite page iteration.
  - `packages/note-to-html-swift/Sources/NoteToHTML/NoteToHTMLConverter.swift` — identical pattern rewrite.
  - `macdoc/Package.swift` — bump `note-core-swift` pin from `0.1.3` → `0.1.4`, `note-to-pdf-swift` from `0.1.2` → `0.1.3`, `note-to-html-swift` from `0.1.0` → `0.1.1`.
  - `macdoc/Tests/MacDocCLITests/NotePDFConvertTests.swift` — add no-cross-page-strokes assertion.
- **Affected dependencies**: internal only. No external package changes. All bumps are patch-level backwards-compatible.
- **Affected systems**: `macdoc` CLI `.note → pdf` + `.note → html` routes.
- **Releases**: 3 new tags on PsychQuant private packages (`note-core-swift@0.1.4`, `note-to-pdf-swift@0.1.3`, `note-to-html-swift@0.1.1`) + `macdoc` Package.swift bump PR.
- **Test fixtures**: continues to rely on `test-files/筆記 2026-03-20 15:25:20.note` (gitignored, privacy-preserving). No new committable fixture this round; synthetic fixture tracked as follow-up.
- **End-user impact**: `macdoc convert --to pdf file.note` output quality materially improves on multi-page non-uniform notes; identical PDF output on uniform notes (no regression). Same for HTML output.
- **Relationship to `#80 psychquant-security-defaults`**: this change adds no security regression; CI release flow will run `./scripts/audit-security.sh` per repo pre-tag as documented in `common-release-flow.md`.
