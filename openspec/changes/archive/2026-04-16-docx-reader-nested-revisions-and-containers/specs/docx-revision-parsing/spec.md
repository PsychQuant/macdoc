## ADDED Requirements

### Requirement: DocxReader parses rPrChange formatting revisions

`DocxReader.parseRunProperties` SHALL detect `<w:rPrChange>` as a direct child of `<w:rPr>`. When found, it SHALL emit a `Revision` with:

- `id`: the integer value of `<w:rPrChange>`'s `w:id` attribute (or 0 if missing)
- `type`: `.formatChange`
- `author`: the string value of `<w:rPrChange>`'s `w:author` attribute (or `"Unknown"`)
- `date`: the ISO8601-parsed `<w:rPrChange>`'s `w:date` attribute (or current date)
- `previousFormatDescription`: a human-readable summary of the prior `<w:rPr>` nested inside `<w:rPrChange>` (e.g., `"bold, italic, 12pt Times New Roman"`)
- `originalText`: `nil`
- `newText`: `nil`

#### Scenario: Bold change under track changes emits formatChange revision

- **WHEN** a run's `<w:rPr>` contains `<w:rPrChange w:id="10" w:author="Alice" w:date="2026-04-16T14:00:00Z"><w:rPr><w:b/></w:rPr></w:rPrChange>`
- **THEN** a `Revision` is emitted with `type == .formatChange`, `author == "Alice"`, and `previousFormatDescription` containing `"bold"`

#### Scenario: No rPrChange emits no revision

- **WHEN** a run's `<w:rPr>` has no `<w:rPrChange>` child
- **THEN** no formatting revision is emitted for that run

<!-- @trace
source: docx-reader-nested-revisions-and-containers
updated: 2026-04-16
code:
  - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift
-->

---

### Requirement: DocxReader parses pPrChange paragraph property revisions

`DocxReader.parseParagraphProperties` SHALL detect `<w:pPrChange>` as a direct child of `<w:pPr>`. When found, it SHALL emit a `Revision` with:

- `id`: the integer value of `<w:pPrChange>`'s `w:id` attribute (or 0)
- `type`: `.paragraphChange`
- `author`: the string value of `<w:pPrChange>`'s `w:author`
- `date`: the ISO8601-parsed `<w:pPrChange>`'s `w:date`
- `previousFormatDescription`: a human-readable summary of the prior `<w:pPr>` nested inside `<w:pPrChange>` (e.g., `"alignment: center, spacing: 240"`)
- `originalText`: `nil`
- `newText`: `nil`

#### Scenario: Alignment change under track changes emits paragraphChange revision

- **WHEN** a paragraph's `<w:pPr>` contains `<w:pPrChange w:id="20" w:author="Bob"><w:pPr><w:jc w:val="center"/></w:pPr></w:pPrChange>`
- **THEN** a `Revision` is emitted with `type == .paragraphChange`, `author == "Bob"`, and `previousFormatDescription` containing `"center"`

#### Scenario: No pPrChange emits no revision

- **WHEN** a paragraph's `<w:pPr>` has no `<w:pPrChange>` child
- **THEN** no paragraph-change revision is emitted

<!-- @trace
source: docx-reader-nested-revisions-and-containers
updated: 2026-04-16
code:
  - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift
-->

---

### Requirement: Revision model gains previousFormatDescription field

`Revision` SHALL have a `previousFormatDescription: String?` property (default `nil`). This field is populated only for revisions of type `.formatChange` and `.paragraphChange`. For all other revision types, it SHALL be `nil`.

#### Scenario: formatChange revision has non-nil previousFormatDescription

- **WHEN** a `Revision` with `type == .formatChange` is emitted by the parser
- **THEN** `previousFormatDescription` is a non-empty string describing the prior formatting

#### Scenario: insertion revision has nil previousFormatDescription

- **WHEN** a `Revision` with `type == .insertion` is emitted by the parser
- **THEN** `previousFormatDescription == nil`

<!-- @trace
source: docx-reader-nested-revisions-and-containers
updated: 2026-04-16
code:
  - packages/ooxml-swift/Sources/OOXMLSwift/Models/Revision.swift
-->

---

## MODIFIED Requirements

### Requirement: Revision aggregation preserves revision order

The `WordDocument.revisions` array populated during `DocxReader.read` SHALL contain all `Revision` objects emitted from body paragraphs in document order (the paragraph index assigned to each revision SHALL match the `body.children` enumeration order of its source paragraph). **Additionally, revisions from container paragraphs (headers, footers, footnotes, endnotes) SHALL be appended after body revisions, grouped by container type (headers first, then footers, then footnotes, then endnotes), each group in document order.** All container-sourced revisions SHALL have their `source` field set to the corresponding `RevisionSource` case.

#### Scenario: Revisions in document order

- **WHEN** a document has two paragraphs — paragraph 0 contains an insertion, paragraph 2 contains a moveFrom — and the document is read via `DocxReader.read(from:)`
- **THEN** `document.revisions.revisions` contains two entries: the insertion with `paragraphIndex == 0` first, the moveFrom with `paragraphIndex == 2` second

#### Scenario: Multiple revisions in same paragraph preserve child order

- **WHEN** a single paragraph contains `<w:ins>` followed by `<w:moveTo>`
- **THEN** `paragraph.revisions` lists the insertion before the moveTo, and both carry the same `paragraphIndex`

#### Scenario: Container revisions follow body revisions

- **WHEN** a document has 1 body revision and 1 footnote revision
- **THEN** `document.revisions.revisions` lists the body revision first (with `source == .body`), then the footnote revision (with `source == .footnote(id: N)`)

#### Scenario: Nested formatting revisions included in aggregation

- **WHEN** a body paragraph has a run with `<w:rPrChange>` (formatting change)
- **THEN** the emitted `Revision(type: .formatChange)` appears in `document.revisions.revisions` at the position of its source paragraph, alongside any top-level revisions from the same paragraph

<!-- @trace
source: docx-reader-nested-revisions-and-containers
updated: 2026-04-16
code:
  - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift
-->
