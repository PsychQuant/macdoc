## Why

macdoc has `.note → html` (interactive HTML player with audio timeline) but no `.note → pdf`. PDF is essential for two use cases that HTML cannot serve:

1. **Claude/LLM analysis**: Claude's `Read` tool rasterizes PDF pages into images for vision models, enabling direct "reading" of handwritten content. HTML `<canvas>` rendering produces JS + stroke coordinates that LLMs cannot interpret visually.
2. **Print / archive**: PDF is the universal static format for printing and long-term preservation. HTML player requires JS + embedded audio — not portable.

The existing workaround (`extract_notability_pdf.py` in teaching-toolkit) has a structural flaw: it looks in `.note/PDFs/` for embedded PDFs, but that directory only contains user-imported background documents (e.g., lecture slides). The actual handwritten strokes live in `Session.plist` as vector ink data and are never exported to `.note/PDFs/`. Result: the script extracts background PDFs while losing all teacher annotations.

## What Changes

- **New Layer 1 package `note-core-swift`**: extracts `NoteParser`, `StrokeDecoder`, `TimelineDecoder`, and all model types (`ParsedNote`, `StrokeData`, `Curve`, `NoteImage`, `RecordingInfo`, `HandwritingEntry`, `StrokeBounds`) from `note-to-html-swift` into a shared parsing package. This is the "ooxml-swift pattern" — parser lives in Layer 1, converters in Layer 3.
- **Refactored `note-to-html-swift`**: becomes a thin Layer 3 converter depending on `note-core-swift` for parsing. Only `NoteConverter` + `PlayerTemplate` remain.
- **New Layer 3 package `note-to-pdf-swift`**: `NoteToPDFConverter` renders `ParsedNote` strokes + images into a multi-page PDF via `CGContext` (Core Graphics PDF context).
  - Coordinate transform: `scale = 612.0 / pageWidth`, `pdfY = (pageHeight - noteY) * scale` (Y-flip for iOS → PDF origin difference)
  - Multi-page: split strokes by Y-range (`page * pageHeight` boundaries), one `CGContext.beginPDFPage()` per page
  - Images: draw as background layer (BEFORE strokes) via `CGContext.draw(cgImage, in:)`
  - Audio: skipped entirely (static format; use HTML player for audio)
- **New CLI route**: `macdoc convert --to pdf input.note` in `MacDoc+Convert.swift`

## Non-Goals

<!-- Non-Goals in design.md -->

## Capabilities

### New Capabilities

- `note-core-parsing`: Shared Notability `.note` file parsing — ZIP extraction, `Session.plist` stroke decoding, image extraction, page geometry. Consumed by both the HTML converter and the new PDF converter.
- `note-to-pdf-conversion`: Renders `ParsedNote` handwritten strokes and embedded images into a static multi-page PDF via Core Graphics.

### Modified Capabilities

(none)

## Impact

- **Affected specs**:
  - New: `openspec/specs/note-core-parsing/spec.md`
  - New: `openspec/specs/note-to-pdf-conversion/spec.md`
- **Affected code**:
  - New: `packages/note-core-swift/` (Layer 1 — extracted from note-to-html-swift)
  - New: `packages/note-to-pdf-swift/` (Layer 3 — CGContext PDF renderer)
  - Modified: `packages/note-to-html-swift/` (refactored to depend on note-core-swift)
  - Modified: `Sources/MacDocCLI/MacDoc+Convert.swift` (new `("note", "pdf")` route)
  - Modified: `Package.swift` (add note-to-pdf-swift + note-core-swift deps)
  - Modified: `CLAUDE.md` (update project structure + dependency graph)
- **Platform**: macOS 14+ (Core Graphics, same as existing)
- **Closes**: [`PsychQuant/macdoc#76`](https://github.com/PsychQuant/macdoc/issues/76)
