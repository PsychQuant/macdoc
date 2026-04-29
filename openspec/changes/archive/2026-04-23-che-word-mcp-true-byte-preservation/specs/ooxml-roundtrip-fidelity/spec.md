## ADDED Requirements

### Requirement: WordDocument tracks modified OOXML parts via Set of paths

The `ooxml-swift` `WordDocument` SHALL expose `internal var modifiedParts: Set<String>` storing OOXML part paths (e.g., `"word/document.xml"`, `"word/header1.xml"`, `"word/theme/theme1.xml"`) the typed model has mutated since `DocxReader.read()` returned. A read-only public accessor `public var modifiedPartsView: Set<String>` SHALL be provided for testing and downstream verification. `DocxReader.read()` SHALL clear `modifiedParts` to empty as the final step before returning, guaranteeing freshly loaded documents start with `modifiedParts.isEmpty == true`.

#### Scenario: Freshly loaded document has empty modifiedParts

- **WHEN** `let doc = try DocxReader.read(from: url)` returns
- **THEN** `doc.modifiedPartsView.isEmpty == true`

#### Scenario: Initializer-built document has empty modifiedParts

- **WHEN** `let doc = WordDocument()` is called via the no-source-archive initializer
- **THEN** `doc.modifiedPartsView.isEmpty == true`

### Requirement: Mutating methods on WordDocument insert corresponding part paths into modifiedParts

Every method that mutates a typed field within `WordDocument` SHALL insert the corresponding OOXML part path into `modifiedParts` as part of the mutation. The mapping SHALL be:

- Document body mutations (`appendParagraph`, `insertParagraph`, `updateParagraph`, `deleteParagraph`, `replaceText`, `insertText`, `insertTable`, `updateCell`, `deleteTable`, `mergeCells`, `addRowToTable`, `addColumnToTable`, `deleteRowFromTable`, `deleteColumnFromTable`) → `"word/document.xml"`.
- Style mutations (`addStyle`, `updateStyle`, `deleteStyle`) → `"word/styles.xml"`.
- Numbering mutations (additions to `numbering.abstractNums`) → `"word/numbering.xml"`.
- Header mutations (`addHeader`, `updateHeader`) → `"word/<header.fileName>"` (using the header's `fileName` computed property which respects `originalFileName`).
- Footer mutations (`addFooter`, `updateFooter`) → `"word/<footer.fileName>"`.
- Image additions (entries appended to `images`) → `"word/media/<image.fileName>"` AND `"[Content_Types].xml"` (new image extension may need new Default entry) AND `"word/_rels/document.xml.rels"` (new image relationship).
- Comment mutations (additions/updates to `comments.comments`) → `"word/comments.xml"` AND `"word/commentsExtended.xml"` when `comments.hasExtendedComments == true`.
- Footnote mutations (additions/updates to `footnotes.footnotes`) → `"word/footnotes.xml"`.
- Endnote mutations (additions/updates to `endnotes.endnotes`) → `"word/endnotes.xml"`.
- Properties mutations (`setDocumentProperties`) → `"docProps/core.xml"`.

#### Scenario: appendParagraph marks document.xml dirty

- **WHEN** `doc.appendParagraph(Paragraph(text: "Hello"))` is called on a freshly loaded document
- **THEN** `doc.modifiedPartsView.contains("word/document.xml") == true`

#### Scenario: addHeader marks header file dirty using fileName

- **WHEN** `doc.addHeader(text: "Page 1", type: .first)` is called and the new header's `fileName` is `"headerFirst.xml"`
- **THEN** `doc.modifiedPartsView.contains("word/headerFirst.xml") == true`

#### Scenario: Multiple sequential mutations accumulate

- **WHEN** `doc.appendParagraph(...)` followed by `doc.addStyle(...)` is called
- **THEN** `doc.modifiedPartsView` contains both `"word/document.xml"` and `"word/styles.xml"`

### Requirement: External callers SHALL mark archive parts dirty when writing directly to archiveTempDir

When a downstream consumer (e.g., `che-word-mcp` MCP server) writes directly to a file in `archiveTempDir` (bypassing typed-model methods — e.g., editing `word/theme/theme1.xml` via raw XML manipulation), the consumer SHALL also call `doc.markPartDirty(<path>)` to insert the path into `modifiedParts`. The `WordDocument` SHALL expose `public mutating func markPartDirty(_ partPath: String)` for this purpose.

#### Scenario: External writer marks theme1.xml dirty

- **WHEN** `che-word-mcp`'s `writeThemeXML` helper writes new content to `archiveTempDir/word/theme/theme1.xml` and then calls `doc.markPartDirty("word/theme/theme1.xml")`
- **THEN** `doc.modifiedPartsView.contains("word/theme/theme1.xml") == true`

### Requirement: DocxWriter overlay mode skips writers for parts not in modifiedParts

When `WordDocument.archiveTempDir != nil` (overlay mode), `DocxWriter.write(_ document:, to dest:)` SHALL skip every typed-part writer whose corresponding part path is NOT in `document.modifiedParts`. Specifically:

- `writeDocument` skipped unless `modifiedParts.contains("word/document.xml")`.
- `writeStyles` skipped unless `modifiedParts.contains("word/styles.xml")`.
- `writeFontTable` skipped unless `modifiedParts.contains("word/fontTable.xml")`.
- `writeNumbering` skipped unless `modifiedParts.contains("word/numbering.xml")`.
- `writeSettings` skipped unless `modifiedParts.contains("word/settings.xml")`.
- `writeAppProperties` skipped unless `modifiedParts.contains("docProps/app.xml")`.
- `writeCoreProperties` skipped unless `modifiedParts.contains("docProps/core.xml")`.
- `writeHeader(header)` skipped unless `modifiedParts.contains("word/\(header.fileName)")`.
- `writeFooter(footer)` skipped unless `modifiedParts.contains("word/\(footer.fileName)")`.
- `writeFootnotes` / `writeEndnotes` / `writeComments` / `writeCommentsExtended` skipped per their respective paths.
- `writeContentTypes` skipped UNLESS `modifiedParts.contains("[Content_Types].xml")` OR new typed parts exist that aren't declared in the original Content_Types.
- `writeDocumentRelationships` skipped UNLESS `modifiedParts.contains("word/_rels/document.xml.rels")` OR new typed relationships exist.
- `writeRelationships` (top-level `_rels/.rels`) is read-only in overlay mode; never re-emitted.

In scratch mode (`archiveTempDir == nil`), every writer runs unconditionally — existing behavior preserved.

#### Scenario: No-op round-trip preserves all typed-managed parts byte-for-byte

- **WHEN** `var doc = try DocxReader.read(from: src)` followed immediately by `try DocxWriter.write(doc, to: dest)` (zero edits)
- **THEN** `doc.modifiedPartsView.isEmpty == true`
- **AND** for every typed-managed part path P (`document.xml`, `styles.xml`, `fontTable.xml`, `header*.xml`, `footer*.xml`, `comments.xml`, `footnotes.xml`, `endnotes.xml`, `numbering.xml`, `settings.xml`, `app.xml`, `core.xml`), the file at `dest`'s extracted path P has byte-equal content to `src`'s extracted path P

#### Scenario: Single edit triggers selective re-emission

- **WHEN** `doc.appendParagraph(Paragraph(text: "X"))` followed by `try DocxWriter.write(doc, to: dest)` runs on a Reader-loaded document
- **THEN** `doc.modifiedPartsView == ["word/document.xml"]`
- **AND** `dest`'s `word/document.xml` reflects the new paragraph
- **AND** `dest`'s `word/styles.xml`, `word/fontTable.xml`, `word/header*.xml`, `word/footer*.xml`, etc. all have byte-equal content to `src`'s corresponding files

### Requirement: writeContentTypes overlay mode includes overrides for typed parts the typed model now references

`DocxWriter.writeContentTypes(to:, document:, overlayMode: true)` SHALL re-emit `[Content_Types].xml` (using `ContentTypesOverlay`) when EITHER `modifiedParts.contains("[Content_Types].xml")` OR the typed model contains parts NOT declared in the original `[Content_Types].xml` (e.g., a freshly added image's media entry, or a new typed header from `addHeader`). The merged Content_Types SHALL preserve original Override entries for unknown PartNames AND emit Override entries for every PartName the typed model currently manages, including newly-added ones.

#### Scenario: insert_image triggers Content_Types refresh

- **WHEN** `doc.images.append(<new image with fileName imageNew.png>)` is called and `modifiedParts.insert("word/media/imageNew.png")` followed by `try DocxWriter.write(doc, to: dest)` runs
- **THEN** `dest`'s `[Content_Types].xml` contains an `<Override PartName="/word/media/imageNew.png"...>` entry that wasn't in `src`'s `[Content_Types].xml`
- **AND** all other original `<Override>` entries are preserved verbatim

### Requirement: MarkDirtyCoverageTests enumerates and validates every WordDocument mutating method

The `ooxml-swift` test suite SHALL contain `Tests/OOXMLSwiftTests/MarkDirtyCoverageTests.swift` with at least one test case per mutating method on `WordDocument` and its substructs (Body, Style, Header, Footer, etc.). Each test case SHALL: (a) load a fresh `WordDocument`, (b) call the mutating method with valid arguments, (c) assert the expected part path appears in `doc.modifiedPartsView`. The test file SHALL include a top-level comment listing all currently audited mutators as a maintenance audit reference for future PRs that add new mutators.

#### Scenario: appendParagraph coverage test

- **WHEN** the test case `testAppendParagraphMarksDocumentXMLDirty` runs
- **THEN** it loads a fresh document, calls `doc.appendParagraph(Paragraph(text: "test"))`, and asserts `doc.modifiedPartsView.contains("word/document.xml")`

#### Scenario: New mutator added without coverage test fails CI

- **WHEN** a developer adds a new mutating method to `WordDocument` without adding a corresponding `MarkDirtyCoverageTests` test case
- **THEN** the linter / coverage gate flags the missing test (out-of-band check; baseline is grep-based audit documented in test file header)
