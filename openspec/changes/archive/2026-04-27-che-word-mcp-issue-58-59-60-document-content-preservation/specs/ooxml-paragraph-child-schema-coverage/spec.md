## ADDED Requirements

### Requirement: BodyChild enum SHALL cover EG_BlockLevelElts members beyond paragraph and table

The `WordDocument` `BodyChild` enum, currently scoped to `paragraph` / `table` / `contentControl`, SHALL also model EG_BlockLevelElts members that can appear as direct children of `<w:body>` (per ECMA-376 Part 1 §17.2.2 `CT_Body`). Specifically, `<w:bookmarkStart>` and `<w:bookmarkEnd>` SHALL have a typed representation; any other unrecognized direct child of `<w:body>` SHALL be preserved as a raw-XML carrier rather than silently dropped.

#### Scenario: Body-level bookmarkStart preserved through round-trip

- **GIVEN** a `.docx` file containing `<w:bookmarkStart w:id="0" w:name="_Toc12345"/>` as a direct child of `<w:body>` (e.g., a TOC anchor wrapping a multi-paragraph block)
- **WHEN** `DocxReader.read(from:)` parses the file
- **THEN** the resulting `WordDocument.body.children` SHALL contain a `BodyChild.bookmarkMarker(BookmarkRangeMarker(kind: .start, id: 0, ...))` entry at the corresponding position in the array
- **AND** when `DocxWriter.write(_:to:)` re-serializes the document, the output `word/document.xml` SHALL contain the same `<w:bookmarkStart w:id="0" w:name="_Toc12345"/>` element at the equivalent body-child position

#### Scenario: Body-level bookmarkEnd preserved through round-trip

- **GIVEN** a `.docx` file containing `<w:bookmarkEnd w:id="0"/>` as a direct child of `<w:body>` (closing a multi-paragraph bookmark span)
- **WHEN** the document is read and written back unmodified
- **THEN** the output `<w:bookmarkEnd w:id="0"/>` SHALL appear at the same body-child position as the source

#### Scenario: Unknown body-level element preserved as raw element

- **GIVEN** a `.docx` file containing a direct child of `<w:body>` that the typed model does not recognize (e.g., `<w:moveFromRangeStart>`, body-level `<w:commentRangeStart>`, or a vendor extension element)
- **WHEN** the document is read and written back unmodified
- **THEN** the output `word/document.xml` SHALL contain the unrecognized element with its original XML serialization (attributes and text content) byte-equivalent to the source

### Requirement: nextBookmarkId calibration SHALL include body-level bookmark markers

The `WordDocument.nextBookmarkId` calibration walker SHALL include any body-level `BookmarkRangeMarker` entries (in addition to the paragraph-level `paragraph.bookmarkMarkers` already included). This prevents a future API-built bookmark from colliding with an existing body-level bookmark id.

#### Scenario: nextBookmarkId reflects body-level bookmarks after read

- **GIVEN** a `.docx` file containing one paragraph-level `<w:bookmarkStart w:id="3"/>` and one body-level `<w:bookmarkStart w:id="7"/>`
- **WHEN** `DocxReader.read(from:)` parses the file
- **THEN** the resulting `WordDocument.nextBookmarkId` SHALL equal `8` (one greater than the maximum bookmark id observed across paragraph and body levels)
