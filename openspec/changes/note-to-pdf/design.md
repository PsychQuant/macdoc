## Context

macdoc already converts `.note → html` via `note-to-html-swift` (Layer 3). That package contains both the parser (`NoteParser` + `StrokeDecoder`, ~520 lines) and the HTML output (`NoteConverter` + `PlayerTemplate`, ~610 lines). This change extracts the parser into a shared Layer 1 package and adds a second Layer 3 converter for PDF output.

Existing code state:
- `packages/note-to-html-swift/Sources/NoteToHTML/NoteParser.swift` (351 lines) — ZIP extraction, Session.plist parsing, stroke + image + recording extraction
- `packages/note-to-html-swift/Sources/NoteToHTML/StrokeDecoder.swift` (169 lines) — binary stroke data → `[Curve]`
- `packages/note-to-html-swift/Sources/NoteToHTML/TimelineDecoder.swift` (94 lines) — timeline events
- `packages/note-to-html-swift/Sources/NoteToHTML/NoteConverter.swift` (167 lines) — glue: parse → JSON → PlayerTemplate
- `packages/note-to-html-swift/Sources/NoteToHTML/PlayerTemplate.swift` (572 lines) — HTML + JS output
- `Sources/MacDocCLI/MacDoc+Convert.swift:107` — existing `("note", "html")` route

## Goals / Non-Goals

**Goals:**

- Extract shared parser into `note-core-swift` Layer 1 package
- Create `note-to-pdf-swift` Layer 3 converter rendering strokes + images via CGContext
- Add CLI route `macdoc convert --to pdf input.note`
- Support multi-page notes with correct page breaks
- Render embedded images as background layer (under strokes)

**Non-Goals:**

- Not rendering audio timeline annotations in the PDF — audio is inherently interactive; PDF is static. Users who want audio use the HTML player.
- Not supporting `--timeline` flag for PDF margin timestamps — deferred to a follow-up if requested.
- Not modifying the HTML converter's behavior — it continues to work exactly as before, just imports from `note-core-swift` instead of having its own copies.
- Not extracting PDFs from `.note/PDFs/` — those are user-imported background documents, not Notability handwriting exports. The whole point of this change is to render the ACTUAL strokes from `Session.plist`.

## Decisions

### Decision: Extract note-core-swift (Option C from diagnosis)

Move `NoteParser`, `StrokeDecoder`, `TimelineDecoder`, and all model structs into `packages/note-core-swift/`. Both `note-to-html-swift` and `note-to-pdf-swift` depend on it.

**Rationale**: matches the ooxml-swift (Layer 1) → word-to-md/html (Layer 3) pattern. The parser IS the substance (~520 lines); HTML converter is output formatting (~610 lines). Future consumers (e.g., note-to-md for handwriting OCR text extraction) get parsing for free.

**Alternatives**: Option A (add PDF to note-to-html-swift — misleading name) and Option B (new package depends on html package for parsing — couples PDF to HTML dependency chain) both rejected per discuss.

### Decision: Coordinate Transform is Scale + Y-Flip

```
scale = 612.0 / pageWidth    // US Letter width = 612 pt
pdfX = noteX * scale
pdfY = (pageHeight - noteY) * scale
```

Notability: top-left origin, ~560×730 units. PDF: bottom-left origin, 72 DPI points.

**Rationale**: `StrokeBounds` default is `(0, 0, 560, 730)`. Scale factor ≈1.09. The Y-flip is standard for all iOS→PDF coordinate conversions (Core Graphics uses bottom-left origin; UIKit/Notability uses top-left).

### Decision: Multi-Page Split by pageHeight Boundaries

Strokes are in global coordinate space. Page N occupies Y range `[N * pageHeight, (N+1) * pageHeight)`. For each PDF page: filter curves whose points fall in that range, offset by `-N * pageHeight`, apply scale + Y-flip, draw.

**Rationale**: `ParsedNote.pageCount` and `ParsedNote.pageHeight` are already parsed by `NoteParser`. The HTML player uses identical Y-range splitting in its JS. Reusing the same logic ensures visual consistency.

### Decision: Audio Skipped Entirely

PDF output contains zero audio data. `RecordingInfo` and `TimelineDecoder` output are not consulted during PDF rendering.

**Rationale**: PDF is a static format. Audio playback requires interactive runtime (JS/HTML). The issue body explicitly marks timeline annotation as "選配" (optional). Ship the core (strokes + images) first.

### Decision: Images Render as Background Layer

For each `NoteImage` with non-nil position data: convert `Data` → `CGImage` via `CGImageSource`, draw BEFORE any strokes on that page. Strokes render on top.

**Rationale**: Notability's rendering model: imported documents/images are the "paper"; handwriting is ink on top. Drawing images first, strokes second, matches this compositing order.

## Risks / Trade-offs

- **Risk**: Notability coordinate origin assumption wrong (top-left vs bottom-left). If wrong, the PDF renders upside-down.
  - **Mitigation**: visual comparison of the first test render against the HTML player output. One boolean flip to fix.

- **Risk**: multi-run curves that span page boundaries get clipped or duplicated.
  - **Mitigation**: each curve is drawn on the page where its FIRST point falls. Points that extend into the next page are clipped by the PDF page boundary (natural CGContext behavior). Acceptable for handwriting (strokes rarely span pages).

- **Risk**: `NoteImage` position data (`originX`, `originY`) is nil for some notes (not all note files populate these fields).
  - **Mitigation**: nil-position images are skipped with a debug log. Only positioned images render.

- **Risk**: refactoring `note-to-html-swift` breaks existing tests.
  - **Mitigation**: run `swift test` in `note-to-html-swift` after extraction. The refactor is purely moving files + updating imports — no behavior change.

## Open Questions

- _(none — all resolved during `/spectra-discuss`)_
