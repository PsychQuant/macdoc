## ADDED Requirements

### Requirement: NoteToPDFConverter iterates ParsedNote.pageBounds when available

`NoteToPDFConverter` SHALL iterate `ParsedNote.pageBounds` when the array is non-empty, producing exactly one PDF page per `PageBounds` entry. Iteration order SHALL match `pageBounds`' array order, which matches `documentPageNumber` ascending. The previous behavior of iterating `0..<pageCount` with derived `pageYStart = pageYOffset + i × pageHeight` SHALL remain as a fallback only when `pageBounds` is empty.

#### Scenario: Multi-page rendering matches pageBounds order

- **WHEN** `NoteToPDFConverter.convert(note:)` is called on a `ParsedNote` whose `pageBounds` has 5 entries with `documentPageNumber` values `[1, 2, 3, 4, 5]`
- **THEN** the generated PDF has exactly 5 pages whose page-order matches `documentPageNumber` ascending

#### Scenario: Fallback iteration preserved when pageBounds empty

- **WHEN** a `ParsedNote` is produced with zero strokes (and therefore empty `pageBounds`)
- **THEN** the converter falls back to the legacy `pageCount`-based page loop and renders blank PDF pages whose count equals `note.pageCount`

### Requirement: Stroke allocation by bounding-box overlap with midpoint tiebreaker

`NoteToPDFConverter` SHALL allocate each stroke (Curve) to the page whose `[yStart, yEnd)` range contains the largest portion of the stroke's Y bounding box. When the overlap is tied or the stroke bounding box spans three or more pages, the converter SHALL use the stroke's Y midpoint (`(minY + maxY) / 2`) as the assignment anchor. The previous first-point-only filter (`firstY >= pageYStart && firstY < pageYEnd`) SHALL NOT be used when `pageBounds` is populated.

#### Scenario: Stroke crossing page boundary renders on majority-overlap page

- **WHEN** a stroke's Y bounding box is `[700, 750]` and page boundaries are `pageBounds[2].yEnd = 732` (so the stroke is 32 pt on page 3, 18 pt on page 4)
- **THEN** the stroke renders fully on page 3, without truncation at y=732, without duplication on page 4

#### Scenario: Three-page stroke uses midpoint

- **WHEN** a stroke's Y bounding box is `[700, 2200]` and `pageBounds[2]` covers `[600, 1300]`, `pageBounds[3]` covers `[1300, 2000]`, `pageBounds[4]` covers `[2000, 2700]` (so the stroke touches 3 pages)
- **THEN** the stroke's midpoint `y = 1450` falls in `pageBounds[3]` and the stroke is rendered there entirely

### Requirement: Fallback stroke filter when pageBounds is empty

When `ParsedNote.pageBounds` is empty (e.g., a zero-stroke note that still has pages via `pageLayoutArray`), the converter SHALL use the original first-point-only filter as a fallback for stroke inclusion. This is the only path where the legacy filter applies, and it is primarily for edge cases where no strokes exist.

#### Scenario: Zero-stroke note generates correct page count with fallback

- **WHEN** `NoteToPDFConverter.convert(note:)` is called on a `ParsedNote` with `pageCount = 3`, zero strokes, and empty `pageBounds`
- **THEN** the generated PDF contains exactly 3 blank US Letter portrait pages with no rendering errors
