## ADDED Requirements

### Requirement: NoteToPDFConverter renders strokes to multi-page PDF

The `note-to-pdf-swift` package SHALL expose a `NoteToPDFConverter` that takes a `ParsedNote` and produces a PDF `Data` object containing one page per note page. Each page SHALL render all curves whose first point falls within that page's Y-range.

#### Scenario: Single-page note produces 1-page PDF

- **WHEN** a 1-page note with 10 curves is converted
- **THEN** the output PDF has exactly 1 page and is non-empty

#### Scenario: Multi-page note produces correct page count

- **WHEN** a 5-page note is converted
- **THEN** the output PDF has exactly 5 pages

#### Scenario: Empty note (no strokes) produces pages with no ink

- **WHEN** a 2-page note with zero curves is converted
- **THEN** the output PDF has 2 blank pages (no crash, no zero-page PDF)

<!-- @trace
source: note-to-pdf
updated: 2026-04-17
code:
  - packages/note-to-pdf-swift/Sources/NoteToPDF/NoteToPDFConverter.swift
-->

---

### Requirement: Coordinate transform applies scale and Y-flip

Stroke coordinates SHALL be transformed from Notability space (top-left origin, ~560x730 units) to PDF space (bottom-left origin, 72 DPI points) using: `pdfX = noteX * scale`, `pdfY = (pageHeight - noteY) * scale`, where `scale = 612.0 / pageWidth`.

#### Scenario: Top-left stroke appears at top of PDF page

- **WHEN** a stroke point is at Notability coordinate `(10, 10)` (near top-left)
- **THEN** the corresponding PDF point is near the top-left of the PDF page (high Y value in PDF coordinates due to Y-flip)

<!-- @trace
source: note-to-pdf
updated: 2026-04-17
code:
  - packages/note-to-pdf-swift/Sources/NoteToPDF/NoteToPDFConverter.swift
-->

---

### Requirement: Images render as background layer under strokes

For each `NoteImage` with non-nil `originX`, `originY`, `width`, and `height`, the converter SHALL draw the image BEFORE drawing strokes on the same page, so that handwritten ink appears on top of imported images.

#### Scenario: Image with position data renders on correct page

- **WHEN** a `NoteImage` has `originY` within page 2's Y-range
- **THEN** the image is drawn on page 2 of the PDF, under any strokes on that page

#### Scenario: Image without position data is skipped

- **WHEN** a `NoteImage` has `originX == nil` or `originY == nil`
- **THEN** the image is not drawn in the PDF (silently skipped)

<!-- @trace
source: note-to-pdf
updated: 2026-04-17
code:
  - packages/note-to-pdf-swift/Sources/NoteToPDF/NoteToPDFConverter.swift
-->

---

### Requirement: CLI route converts .note to PDF

`macdoc convert --to pdf input.note` SHALL produce a PDF file. Default output path: same directory as input, with `.pdf` extension. Supports `--output` for custom path.

#### Scenario: Default output path

- **WHEN** `macdoc convert --to pdf ~/notes/lecture.note` is run without `--output`
- **THEN** the PDF is written to `~/notes/lecture.pdf`

#### Scenario: Custom output path

- **WHEN** `macdoc convert --to pdf input.note --output /tmp/out.pdf` is run
- **THEN** the PDF is written to `/tmp/out.pdf`

<!-- @trace
source: note-to-pdf
updated: 2026-04-17
code:
  - Sources/MacDocCLI/MacDoc+Convert.swift
-->
