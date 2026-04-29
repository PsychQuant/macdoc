## ADDED Requirements

### Requirement: DocxReader SHALL capture w:tbl direct children of header, footer, footnote, and endnote roots

`DocxReader.parseContainerBody` (the renamed `parseContainerParagraphs`) SHALL collect both `<w:p>` and `<w:tbl>` direct children of `<w:hdr>`, `<w:ftr>`, `<w:footnote>`, and `<w:endnote>` root elements into a `[BodyChild]` collection that is then assigned to the container model's `bodyChildren` field. The prior R3-NEW-5 behavior of collecting only `<w:p>` and silently discarding `<w:tbl>` is forbidden because it hides any bookmark, content control, or revision id residing inside header/footer tables from `nextBookmarkId` calibration, the unified document walker, and revision accept/reject helpers.

The container model fields SHALL evolve as follows:

- `Header`, `Footer`, `Footnote`, `Endnote` each SHALL gain `public var bodyChildren: [BodyChild]` populated by the reader.
- `paragraphs: [Paragraph]` SHALL remain on each container model as a backward-compatible computed view: `bodyChildren.compactMap { if case .paragraph(let p) = $0 { return p } else { return nil } }`.
- `Header.toXML()`, `Footer.toXML()`, `Footnote.toXML()`, `Endnote.toXML()` SHALL emit from `bodyChildren` so table children round-trip rather than being dropped on write.

#### Scenario: Header table bookmark surfaces in nextBookmarkId calibration

- **GIVEN** `word/header1.xml` containing `<w:hdr><w:p>...</w:p><w:tbl><w:tr><w:tc><w:p><w:bookmarkStart w:id="42" w:name="HeaderBookmark"/></w:p></w:tc></w:tr></w:tbl></w:hdr>`
- **WHEN** `DocxReader.read()` parses the document
- **THEN** the calibration walker visits the bookmark with id 42
- **AND** `document.nextBookmarkId` is at least 43
- **AND** the parsed `Header.bodyChildren` contains exactly two entries — `.paragraph` then `.table` — preserving source order

#### Scenario: Footer table content survives roundtrip

- **GIVEN** `word/footer1.xml` containing a `<w:tbl>` with one row, one cell, one paragraph, with text "footer-cell"
- **WHEN** the document is read by `DocxReader`, written by `DocxWriter` to a new file, then re-read
- **THEN** the re-read document's `Footer.bodyChildren` contains a `.table` entry whose first cell's first paragraph yields text "footer-cell"
- **AND** `Footer.paragraphs` (the computed view) contains zero entries because the only direct child is a table, not a paragraph

### Requirement: DocxReader SHALL assign source paragraph child positions starting at 1

`DocxReader.parseParagraph` SHALL initialize the per-paragraph child-position counter at `1` (not `0`) so that every source paragraph child — whether `Run`, `ContentControl`, hyperlink, etc. — receives a positive `position` value. The reserved value `position == 0` SHALL mean "API-built sentinel" — assigned only when callers programmatically construct a child without specifying a position.

`Paragraph.toXMLSortedByPosition` SHALL include ALL `contentControls` entries in the positioned-emit list (drop the prior `> 0` filter). The legacy emit path that prepends API-built children SHALL include only `contentControls` whose `position == 0`. `Paragraph.hasSourcePositionedChildren` SHALL recognize a paragraph as source-positioned when ANY child (run, contentControl, etc.) has `position > 0`.

The R3-NEW-2 behavior of routing `position > 0` into sorted emit while letting `position == 0` fall through to legacy emit is forbidden because `position == 0` was overloaded between "first source position" (for source-built first children) and "API-built sentinel" — collapsing the two values caused first-child source SDTs to be silently demoted to the end of the paragraph on write.

#### Scenario: First-child source SDT round-trips at first position

- **GIVEN** source XML for a paragraph: `<w:p><w:sdt><w:sdtContent><w:r><w:t>A</w:t></w:r></w:sdtContent></w:sdt><w:r><w:t>B</w:t></w:r></w:p>`
- **WHEN** `DocxReader.read()` parses the paragraph and the document is round-tripped via `DocxWriter` then `DocxReader`
- **THEN** the re-read paragraph's emit order has the SDT first and the run "B" second (matching source)
- **AND** the re-read paragraph's `contentControls[0].position == 1`
- **AND** the re-read paragraph's only run has `position == 2`

#### Scenario: API-built ContentControl preserves position-zero sentinel

- **GIVEN** an in-memory paragraph constructed via `Paragraph()` followed by `paragraph.contentControls.append(ContentControl(...))` (no position specified, defaulting to 0)
- **WHEN** the paragraph is emitted via `toXML()`
- **THEN** the emit goes through legacy path (not sorted) and the SDT is prepended at end of the paragraph (preserving the prior R2 API-built behavior)

<!-- @trace
source: che-word-mcp-issue-56-r4-stack-completion
updated: 2026-04-26
code:
  - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift
  - packages/ooxml-swift/Sources/OOXMLSwift/Models/Paragraph.swift
  - packages/ooxml-swift/Sources/OOXMLSwift/Models/Header.swift
  - packages/ooxml-swift/Sources/OOXMLSwift/Models/Footer.swift
  - packages/ooxml-swift/Sources/OOXMLSwift/Models/Footnote.swift
  - packages/ooxml-swift/Sources/OOXMLSwift/Models/Endnote.swift
-->
