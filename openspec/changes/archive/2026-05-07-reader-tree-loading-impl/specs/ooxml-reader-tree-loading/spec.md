## ADDED Requirements

### Requirement: WordDocument carries XmlTree per loaded OOXML part

`WordDocument` SHALL expose a public read-only stored property `xmlTrees: [String: XmlTree]` keyed by OOXML part path (e.g., `"word/document.xml"`, `"word/styles.xml"`). The dictionary SHALL be internally settable so `DocxReader` populates it; external mutation SHALL be prevented at the type system level.

`WordDocument` SHALL expose a public convenience accessor `partTree(at: String) -> XmlTree?` returning `xmlTrees[partPath]`.

`WordDocument`'s `Equatable` conformance SHALL exclude the `xmlTrees` field — two `WordDocument` values with byte-identical content but distinct `XmlTree` class instances SHALL compare equal.

#### Scenario: xmlTrees is publicly readable

- **GIVEN** a `WordDocument` returned by any `DocxReader.read(from:)` call
- **WHEN** `document.xmlTrees` is accessed
- **THEN** the returned dictionary SHALL be readable from outside the `OOXMLSwift` module

#### Scenario: xmlTrees is not externally mutable

- **GIVEN** a `WordDocument` returned by any `DocxReader.read(from:)` call
- **WHEN** external code attempts to assign `document.xmlTrees = [:]`
- **THEN** the compile SHALL fail (the property has internal-set visibility)

#### Scenario: partTree returns nil for unknown part path

- **GIVEN** a `WordDocument` returned by `DocxReader.read(from:)` on any docx
- **WHEN** `document.partTree(at: "word/this-part-does-not-exist.xml")` is called
- **THEN** the returned value SHALL be `nil`

#### Scenario: Equatable ignores xmlTrees

- **GIVEN** two `WordDocument` values `doc1` and `doc2` produced by reading the same source docx file twice
- **WHEN** they are compared with `==`
- **THEN** the comparison SHALL return `true` even though `doc1.xmlTrees["word/document.xml"]` and `doc2.xmlTrees["word/document.xml"]` are distinct `XmlTree` instances

### Requirement: DocxReader populates xmlTrees during read

`DocxReader.read(from: URL)` SHALL populate `document.xmlTrees[partPath]` by calling `XmlTreeReader.parse(_:)` on the bytes of every primary OOXML part it loads. Primary parts in scope:

- `word/document.xml`
- `word/styles.xml` (when present)
- `word/numbering.xml` (when present)
- `word/settings.xml` (when present)
- `word/comments.xml` (when present)
- `word/footnotes.xml` (when present)
- `word/endnotes.xml` (when present)
- Each `word/header*.xml` (one entry per header part)
- Each `word/footer*.xml` (one entry per footer part)
- Each `word/customXml/*.xml` (one entry per custom XML part)

Relationship and metadata parts (`[Content_Types].xml`, any `_rels/*.rels` part) SHALL NOT be loaded into `xmlTrees` — they are out of scope for typed-view wiring and remain handled by the existing `RelationshipsCollection` parser.

If `XmlTreeReader.parse(_:)` throws on any part, the throw SHALL propagate from `DocxReader.read(from:)` — Reader SHALL NOT silently swallow tree-parse failures.

#### Scenario: xmlTrees populated for document.xml

- **GIVEN** a docx file containing at minimum a `word/document.xml` part
- **WHEN** `DocxReader.read(from: docxURL)` is called
- **THEN** the returned `document.xmlTrees["word/document.xml"]` SHALL be a non-nil `XmlTree`
- **AND** the tree's `root` SHALL be an `XmlNode` whose `localName == "document"`

#### Scenario: xmlTrees populated for every primary part present in the source

- **GIVEN** a docx file containing `word/document.xml`, `word/styles.xml`, `word/numbering.xml`, `word/settings.xml`, and at least one `word/header*.xml`
- **WHEN** `DocxReader.read(from: docxURL)` is called
- **THEN** `document.xmlTrees` SHALL contain non-nil entries for every primary part listed above
- **AND** the `<header*>` part path key SHALL match the actual filename (e.g., `"word/header1.xml"` if the file is `header1.xml`)

#### Scenario: Optional parts that are absent are not in xmlTrees

- **GIVEN** a docx file with no `word/footnotes.xml` part
- **WHEN** `DocxReader.read(from: docxURL)` is called
- **THEN** `document.xmlTrees["word/footnotes.xml"]` SHALL be `nil`
- **AND** `document.partTree(at: "word/footnotes.xml")` SHALL return `nil`

### Requirement: Default Reader behavior preserves v0.31.1 detached typed-view semantics

`DocxReader.read(from: URL)` (no `wireTreeBackedViews` parameter, equivalent to `wireTreeBackedViews: false`) SHALL leave every Reader-produced typed value (`Paragraph`, `Run`, `Table`, `TableRow`, `TableCell`, `SectionProperties`) in **detached mode** — i.e., `xmlNode == nil` on every typed value reachable from `document.body.children`, headers, footers, comments, footnotes, endnotes.

`document.xmlTrees` SHALL still be populated per the previous requirement, but typed values SHALL NOT be wired to it.

This requirement preserves byte-equivalent observable behavior for downstream consumers (che-word-mcp's 297-test regression gate). External callers who do not pass `wireTreeBackedViews: true` SHALL see no behavior change versus ooxml-swift v0.31.1.

#### Scenario: default-mode body Paragraph is detached

- **GIVEN** a docx file containing at least one body-level paragraph
- **WHEN** `DocxReader.read(from: docxURL)` is called WITHOUT `wireTreeBackedViews:`
- **THEN** for every `BodyChild.paragraph(p)` in `document.body.children`, `p.xmlNode` SHALL be `nil`
- **AND** `p.id` SHALL be `nil`

#### Scenario: default-mode body Table is detached

- **GIVEN** a docx file containing at least one body-level table
- **WHEN** `DocxReader.read(from: docxURL)` is called WITHOUT `wireTreeBackedViews:`
- **THEN** for every `BodyChild.table(t)` in `document.body.children`, `t.xmlNode` SHALL be `nil`
- **AND** `t.id` SHALL be `nil`

### Requirement: wireTreeBackedViews opt-in mode wires body-level Paragraph and Table

`DocxReader.read(from: URL, wireTreeBackedViews: true)` SHALL, after constructing the typed model, walk the `<w:body>` direct children inside `xmlTrees["word/document.xml"]` and position-match against `document.body.children`. For each match:

- A `<w:p>` direct child of `<w:body>` matched with a `BodyChild.paragraph(var p)` entry SHALL set `p.xmlNode` to that `<w:p>` `XmlNode` and write the updated paragraph back into `document.body.children`.
- A `<w:tbl>` direct child of `<w:body>` matched with a `BodyChild.table(var t)` entry SHALL set `t.xmlNode` to that `<w:tbl>` `XmlNode` and write the updated table back.
- A `<w:sectPr>` direct child of `<w:body>` SHALL NOT be wired to any `body.children` entry (section-level metadata; out of scope for body wiring).
- Any other `<w:body>` direct child kind SHALL NOT crash; the cursor SHALL skip the corresponding `body.children` entry defensively.

Nested typed views (cell paragraphs, run-internal anything) SHALL NOT be wired by Reader. They SHALL be reached through the v0.31.1 mode-aware computed accessors (`TableCell.paragraphs` returns `[Paragraph(xmlNode:)]` per `<w:p>` child of the wrapped `<w:tc>`, etc.) at access time.

The opt-in wiring SHALL be additive — typed values still carry their legacy stored fields (text, properties, etc.) populated by the existing parser, but in tree-backed mode the mode-aware computed accessors shadow those legacy fields with tree-walked values.

#### Scenario: wireTreeBackedViews sets xmlNode on body Paragraphs

- **GIVEN** a docx file containing at least one body-level paragraph
- **WHEN** `DocxReader.read(from: docxURL, wireTreeBackedViews: true)` is called
- **THEN** for every `BodyChild.paragraph(p)` in `document.body.children`, `p.xmlNode` SHALL be a non-nil `XmlNode` whose `localName == "p"`
- **AND** that `XmlNode` SHALL be reachable from `document.xmlTrees["word/document.xml"].root` by walking children

#### Scenario: wireTreeBackedViews sets xmlNode on body Tables

- **GIVEN** a docx file containing at least one body-level table
- **WHEN** `DocxReader.read(from: docxURL, wireTreeBackedViews: true)` is called
- **THEN** for every `BodyChild.table(t)` in `document.body.children`, `t.xmlNode` SHALL be a non-nil `XmlNode` whose `localName == "tbl"`

#### Scenario: wireTreeBackedViews on cell-internal paragraph propagates via computed accessor

- **GIVEN** a docx file containing a body-level table with at least one cell containing at least one paragraph
- **WHEN** `DocxReader.read(from: docxURL, wireTreeBackedViews: true)` is called
- **AND** the body Table is accessed via `document.body.children[i].table?` (so it has `xmlNode != nil`)
- **AND** `table.rows[0].cells[0].paragraphs[0]` is accessed
- **THEN** the returned cell-internal Paragraph SHALL have `xmlNode != nil` (auto-propagated via the v0.31.1 `TableCell.paragraphs` mode-aware computed accessor)

#### Scenario: wireTreeBackedViews handles unexpected body child kinds without crashing

- **GIVEN** a docx file whose `<w:body>` contains a child element kind that the typed parser does not produce as a `body.children` entry (e.g., a stray `<w:proofErr>` or an unrecognized OOXML extension element)
- **WHEN** `DocxReader.read(from: docxURL, wireTreeBackedViews: true)` is called
- **THEN** the call SHALL NOT crash
- **AND** the body-level Paragraphs and Tables that DO have matching `<w:p>` / `<w:tbl>` `<w:body>` children SHALL still get their `xmlNode` set correctly

### Requirement: che-word-mcp regression gate stays green against the wired Reader

The full che-word-mcp test suite (297 production tests as of 2026-05-07) SHALL pass against an ooxml-swift containing this change after `Package.resolved` is bumped to v0.31.2. Zero test SHALL fail. Zero test SHALL exhibit observable output diff versus the pre-change baseline.

Because che-word-mcp call sites do NOT pass `wireTreeBackedViews:`, they hit the default-mode path; behavior MUST remain byte-equivalent to v0.31.1.

#### Scenario: che-word-mcp 297-test suite passes against v0.31.2

- **GIVEN** che-word-mcp's 297 production tests pinned to ooxml-swift v0.31.2 (this change)
- **WHEN** `swift test` runs in `mcp/che-word-mcp/`
- **THEN** the result SHALL be: 297 tests / 9 skipped / 0 failures
- **AND** zero observable output diff versus the v0.31.1 baseline

### Requirement: ReaderTreeLoadingTests pinned coverage

A new test file `Tests/OOXMLSwiftTests/ReaderTreeLoadingTests.swift` SHALL be added with at least 6 XCTestCase methods pinning the requirements above. The tests SHALL use the existing golden corpus fixtures (`multi-section-thesis.docx`, `vml-rich.docx`, `cjk-settings.docx`, `comment-anchored.docx` from `Tests/OOXMLSwiftTests/Fixtures/`) to avoid synthesizing new docx files.

The tests SHALL pass GREEN against the implementation in the same release (no `#if false` gate phase).

#### Scenario: ReaderTreeLoadingTests passes GREEN

- **WHEN** `swift test --filter ReaderTreeLoadingTests` runs against this change
- **THEN** every test method SHALL pass
- **AND** the test runner SHALL report at least 6 passing tests with 0 failures
