## ADDED Requirements

### Requirement: Container parts SHALL preserve <w:t> whitespace content via WhitespaceOverlay

The `DocxReader` whitespace overlay mechanism (introduced for `word/document.xml` whitespace preservation) SHALL extend to all OOXML container parts that use Foundation `XMLDocument` parsing: `word/header*.xml`, `word/footer*.xml`, `word/footnotes.xml`, `word/endnotes.xml`, `word/comments.xml`. The same Foundation `XMLDocument` whitespace-stripping limitation affects these parts; the same `WhitespaceOverlay` pre-parse byte-stream scan applies uniformly across them.

#### Scenario: Header whitespace round-trips through container parsing

- **GIVEN** a `.docx` file with a header (`word/header1.xml`) containing `<w:r><w:t xml:space="preserve">   </w:t></w:r>` (3-character whitespace) between non-whitespace runs
- **WHEN** `DocxReader.read(from:)` parses the file, the header is mutated (forcing `word/header1.xml` into `modifiedParts`), and the document is written back
- **THEN** the output `word/header1.xml` SHALL preserve the 3-character whitespace `<w:t>` element

#### Scenario: Footer whitespace round-trips through container parsing

- **GIVEN** a `.docx` file with a footer (`word/footer1.xml`) containing whitespace-only `<w:t xml:space="preserve">[space]</w:t>` runs
- **WHEN** the document is read, footer mutated, and saved
- **THEN** the output `word/footer1.xml` SHALL preserve the whitespace text content with the same character sequence as the source

#### Scenario: Footnote whitespace round-trips through container parsing

- **GIVEN** a `.docx` file with `word/footnotes.xml` containing whitespace-only `<w:t>` runs in any footnote body
- **WHEN** the document is read, marked modified, and saved
- **THEN** `word/footnotes.xml` whitespace content SHALL round-trip byte-equivalent to the source

#### Scenario: Endnote whitespace round-trips through container parsing

- **GIVEN** a `.docx` file with `word/endnotes.xml` containing whitespace-only `<w:t>` runs in any endnote body
- **WHEN** the document is read, marked modified, and saved
- **THEN** `word/endnotes.xml` whitespace content SHALL round-trip byte-equivalent to the source

#### Scenario: Comments whitespace round-trips through container parsing

- **GIVEN** a `.docx` file with `word/comments.xml` containing whitespace-only `<w:t>` runs in any comment body
- **WHEN** the document is read, marked modified, and saved
- **THEN** `word/comments.xml` whitespace content SHALL round-trip byte-equivalent to the source
