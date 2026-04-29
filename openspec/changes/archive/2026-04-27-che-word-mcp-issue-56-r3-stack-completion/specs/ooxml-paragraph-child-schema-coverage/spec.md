## ADDED Requirements

### Requirement: ContentControl SHALL expose a position: Int field and emit in source order

The `ContentControl` model representing a paragraph-level `<w:sdt>` element SHALL expose a public `position: Int` stored property. `DocxReader.parseParagraph` SHALL pass the current `childPosition` value when constructing or appending a `ContentControl`, so each `ContentControl` carries the index at which it appeared among the parent paragraph's `<w:p>` children. `Paragraph.toXMLSortedByPosition` SHALL include each `ContentControl` instance as a positioned entry in the merged sort list, alongside runs, hyperlinks, bookmarks, and other positioned children. The `<w:sdt>` element SHALL be emitted at its source position rather than always at the end of the paragraph.

#### Scenario: SDT between runs round-trips at its source position

- **GIVEN** source paragraph XML `<w:p><w:r><w:t>A</w:t></w:r><w:sdt><w:sdtContent><w:r><w:t>X</w:t></w:r></w:sdtContent></w:sdt><w:r><w:t>B</w:t></w:r></w:p>`
- **WHEN** the paragraph is parsed by `DocxReader` and re-emitted via `Paragraph.toXML()`
- **THEN** the emitted XML contains the runs and the `<w:sdt>` block in the order: A, X (inside sdt), B
- **AND** the `<w:sdt>` block does NOT appear after the final `<w:r>B</w:r>`

##### Example: positioned-entry order

| Source order | Element | Position |
| --- | --- | --- |
| 0 | `<w:r>A</w:r>` | 0 |
| 1 | `<w:sdt>X</w:sdt>` | 1 |
| 2 | `<w:r>B</w:r>` | 2 |

After `toXML()`, the emitted child order is identical to source order (A, sdt-X, B).

### Requirement: nextBookmarkId calibration SHALL scan all bookmark-bearing document parts

`DocxReader.read(from:)` calibration of `WordDocument.nextBookmarkId` SHALL recursively walk:

1. All paragraphs in `document.body.children`, including paragraphs nested inside `<w:tbl>` table cells (any nesting depth) and inside block-level `<w:sdt>` children.
2. All paragraphs in headers (`word/header*.xml`).
3. All paragraphs in footers (`word/footer*.xml`).
4. All paragraphs in footnotes (`word/footnotes.xml`).
5. All paragraphs in endnotes (`word/endnotes.xml`).

For each visited paragraph, calibration SHALL inspect both `bookmarks` (typed) and `bookmarkMarkers` (raw) for the maximum `id`. After scanning, `WordDocument.nextBookmarkId` SHALL be set to one greater than the maximum bookmark `id` observed across all parts.

#### Scenario: Bookmark in table cell calibrates nextBookmarkId

- **GIVEN** a `.docx` whose only bookmarks live inside table cells, with the maximum id being 99
- **WHEN** the document is loaded via `DocxReader.read(from:)`
- **THEN** `document.nextBookmarkId == 100`
- **AND** subsequent `document.insertBookmark(...)` calls allocate ids ≥ 100 with no collision against the source id 99

#### Scenario: Bookmark in header calibrates nextBookmarkId

- **GIVEN** a `.docx` whose body has bookmark id 5 and whose header has bookmark id 50
- **WHEN** the document is loaded
- **THEN** `document.nextBookmarkId == 51`

##### Example: calibration across parts

| Document part | Max bookmark id |  |
| --- | --- | --- |
| body top-level paragraphs | 5 | scanned |
| body table cells | 99 | scanned |
| header1.xml | 12 | scanned |
| footer1.xml | 30 | scanned |
| footnotes.xml | 7 | scanned |
| endnotes.xml | (none) | scanned |
| Calibration result | `nextBookmarkId = 100` | max(5,99,12,30,7) + 1 |
