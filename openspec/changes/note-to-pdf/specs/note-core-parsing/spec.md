## ADDED Requirements

### Requirement: NoteParser extracts ParsedNote from .note ZIP bundle

The `note-core-swift` package SHALL expose a `NoteParser` type with a `parse(input: URL) -> ParsedNote` method that reads a Notability `.note` file (ZIP bundle) and returns a `ParsedNote` struct containing strokes, images, recordings, page geometry, and title.

#### Scenario: Valid .note file parsed successfully

- **WHEN** `NoteParser().parse(input: validNoteURL)` is called on a Notability `.note` file containing handwritten strokes
- **THEN** the returned `ParsedNote` has `strokes.curves` with at least one curve, `pageCount >= 1`, and non-empty `title`

#### Scenario: Non-existent file throws error

- **WHEN** `NoteParser().parse(input:)` is called with a URL pointing to a non-existent file
- **THEN** the method throws an error

<!-- @trace
source: note-to-pdf
updated: 2026-04-17
code:
  - packages/note-core-swift/Sources/NoteCore/NoteParser.swift
-->

---

### Requirement: StrokeDecoder produces Curve array with color and width

`StrokeDecoder` SHALL decode binary stroke data from `Session.plist` into an array of `Curve` structs, each carrying `points: [(x: Float, y: Float)]`, `color: UInt32` (RGBA packed), `width: Float`, and `style: UInt8`.

#### Scenario: Stroke with multiple points decoded

- **WHEN** `Session.plist` contains a stroke with 50 sample points
- **THEN** the decoded `Curve` has `points.count == 50` with valid `(x, y)` coordinates within `StrokeBounds`

#### Scenario: Color and width preserved

- **WHEN** a stroke was drawn with red color and 3.0 width
- **THEN** the decoded `Curve.colorHex` returns a red hex value and `Curve.width == 3.0`

<!-- @trace
source: note-to-pdf
updated: 2026-04-17
code:
  - packages/note-core-swift/Sources/NoteCore/StrokeDecoder.swift
-->

---

### Requirement: ParsedNote exposes page geometry

`ParsedNote` SHALL provide `pageCount: Int`, `pageWidth: Float`, and `pageHeight: Float` fields representing the note's page dimensions in Notability coordinate units.

#### Scenario: Multi-page note reports correct page count

- **WHEN** a 5-page Notability note is parsed
- **THEN** `parsedNote.pageCount == 5` and `pageWidth` / `pageHeight` are positive floats

<!-- @trace
source: note-to-pdf
updated: 2026-04-17
code:
  - packages/note-core-swift/Sources/NoteCore/NoteParser.swift
-->
