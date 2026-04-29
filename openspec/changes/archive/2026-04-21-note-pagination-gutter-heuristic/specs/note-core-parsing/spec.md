## ADDED Requirements

### Requirement: ParsedNote exposes per-page Y bounds via PageBounds

`ParsedNote` SHALL expose a public `pageBounds: [PageBounds]` field where each `PageBounds` entry is a struct `{yStart: Float, yEnd: Float, documentPageNumber: Int}`. When populated, `pageBounds` is authoritative for per-page rendering boundaries. Existing `pageHeight` / `pageYOffset` fields SHALL remain available and SHALL be derived from `pageBounds` when `pageBounds` is non-empty, to preserve backwards compatibility with consumers built against earlier versions.

#### Scenario: pageBounds populated for multi-page note with detectable gutters

- **WHEN** `NoteParser().parse(input: multiPageNoteWithGutters)` is called on a `.note` file with 3+ logical pages and detectable quiet bands between them
- **THEN** the returned `ParsedNote.pageBounds` has exactly `pageCount` entries, each `documentPageNumber` is strictly increasing from 1, each `yStart < yEnd`, and adjacent entries have `yEnd[i] <= yStart[i+1]`

#### Scenario: backwards-compatible pageHeight still returned

- **WHEN** a caller reads `ParsedNote.pageHeight` on a note where `pageBounds` is populated
- **THEN** the value is consistent with `(pageBounds[0].yEnd - pageBounds[0].yStart)` or equivalent per-page height, and consumers that never read `pageBounds` continue to render pages at the same boundaries as prior `0.1.3` behavior

### Requirement: Gutter-gap detection identifies page boundaries from stroke density

`NoteParser` SHALL scan the stroke point distribution along the Y axis and identify contiguous Y ranges of near-zero stroke-point density ("gutters"). A gutter qualifies when its height is at least `minGutterHeight` (default 40 pt) AND its normalised point density falls below `quietBandThreshold` (default 1% of peak density). Detected gutters SHALL be used as page boundaries when the number of gutters found equals `pageCount - 1`.

#### Scenario: sufficient gutters drive pageBounds

- **WHEN** `NoteParser` parses a 9-page note and detects exactly 8 gutters between logical pages
- **THEN** `ParsedNote.pageBounds` contains 9 entries whose `yStart`/`yEnd` boundaries correspond to the detected gutter midpoints, and the `documentPageNumber` values match the order of `pageLayoutArray`

#### Scenario: insufficient gutters do not force schema violation

- **WHEN** `NoteParser` parses a note where only 3 gutters are detected but `pageCount` from `pageLayoutArray` is 5
- **THEN** gutter detection is considered inconclusive and the fallback even-split heuristic (see next requirement) is used instead

### Requirement: Even-split fallback populates pageBounds when gutter detection is inconclusive

When gutter detection finds fewer than `pageCount - 1` gutters, `NoteParser` SHALL fall back to the existing heuristic (`pageYOffset = max(bounds.minY, 0)`, `pageHeight = (bounds.maxY - bounds.minY) / pageCount`) AND SHALL still populate `pageBounds` from the fallback values so that downstream consumers always receive a non-empty `pageBounds` array when at least one stroke exists. This ensures consumers never need to implement their own even-split fallback.

#### Scenario: fallback still returns populated pageBounds

- **WHEN** gutter detection fails (0 gutters found on a single-continuous-drawing note that spans multiple pages)
- **THEN** `ParsedNote.pageBounds` is populated from even-split derivation with `pageCount` entries, and downstream converters receive a consistent data shape without needing fallback code

#### Scenario: zero-stroke note returns empty pageBounds

- **WHEN** `NoteParser` parses a `.note` file that contains zero strokes (newly created blank notes)
- **THEN** `ParsedNote.pageBounds` is an empty array, and consumers are expected to render blank pages using `pageLayoutArray` length as the page count signal

### Requirement: logicalPageHeight paper-size helper is demoted to last-resort fallback

The internal `NoteParser.logicalPageHeight(paperSize:paperOrientation:pageWidth:)` helper SHALL NOT be the primary source of `pageHeight`. It MAY be used only as the final fallback when both gutter detection AND stroke-bounds even-split produce no usable result (e.g., a note with zero strokes but non-zero `pageLayoutArray` length). Its docstring SHALL document that observed paperSize-derived heights drift up to 22.7 pt per page against empirical stroke bounds on iPad `.note` v9 files and therefore SHALL NOT be used for final layout decisions.

#### Scenario: logicalPageHeight not called on typical multi-page note

- **WHEN** `NoteParser` parses any `.note` file containing at least one stroke
- **THEN** the implementation path does not invoke `logicalPageHeight(...)` — gutter detection or stroke-bounds even-split is used instead
