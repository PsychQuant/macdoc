## ADDED Requirements

### Requirement: DocxReader reads header parts from the ZIP

`DocxReader.read(from:)` SHALL read every `word/header*.xml` part referenced in `word/_rels/document.xml.rels` and populate `document.headers` with the parsed content. Each header SHALL have its paragraphs parsed via `parseParagraph`, gaining the same revision, comment, and formatting coverage as body paragraphs.

If no header relationships exist in the .docx, `document.headers` SHALL remain an empty array (not an error).

#### Scenario: Document with one header populates document.headers

- **WHEN** a .docx contains `word/header1.xml` with two paragraphs and the document is read via `DocxReader.read(from:)`
- **THEN** `document.headers` contains one `Header` with two parsed paragraphs

#### Scenario: Document without headers has empty headers array

- **WHEN** a .docx has no header relationship entries
- **THEN** `document.headers` is an empty array and no error is thrown

<!-- @trace
source: docx-reader-nested-revisions-and-containers
updated: 2026-04-16
code:
  - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift
-->

---

### Requirement: DocxReader reads footer parts from the ZIP

`DocxReader.read(from:)` SHALL read every `word/footer*.xml` part referenced in `word/_rels/document.xml.rels` and populate `document.footers` with the parsed content. Same paragraph-parsing depth as headers.

#### Scenario: Document with footer populates document.footers

- **WHEN** a .docx contains `word/footer1.xml` with one paragraph
- **THEN** `document.footers` contains one `Footer` with one parsed paragraph

#### Scenario: Missing footer part is skipped gracefully

- **WHEN** a relationship references `word/footer2.xml` but the file is missing from the ZIP
- **THEN** that footer is skipped without error and `document.footers` contains only successfully parsed footers

<!-- @trace
source: docx-reader-nested-revisions-and-containers
updated: 2026-04-16
code:
  - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift
-->

---

### Requirement: DocxReader reads footnotes from the ZIP

`DocxReader.read(from:)` SHALL read `word/footnotes.xml` (if present) and populate `document.footnotes` with the parsed content. Each footnote entry's `<w:p>` children SHALL be parsed via `parseParagraph`.

Footnote IDs 0 and 1 (separator and continuation separator) SHALL be skipped as they are structural markers, not user-authored content.

#### Scenario: Document with user footnotes populates document.footnotes

- **WHEN** a .docx contains `word/footnotes.xml` with entries at IDs 0, 1, and 2
- **THEN** `document.footnotes` contains only the entry with ID 2 (user-authored); IDs 0 and 1 are skipped

#### Scenario: Document without footnotes.xml has empty footnotes

- **WHEN** the ZIP does not contain `word/footnotes.xml`
- **THEN** `document.footnotes` remains empty and no error is thrown

<!-- @trace
source: docx-reader-nested-revisions-and-containers
updated: 2026-04-16
code:
  - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift
-->

---

### Requirement: DocxReader reads endnotes from the ZIP

`DocxReader.read(from:)` SHALL read `word/endnotes.xml` (if present) and populate `document.endnotes` with the parsed content. Same structural-ID skipping as footnotes (IDs 0 and 1 skipped).

#### Scenario: Document with endnotes populates document.endnotes

- **WHEN** a .docx has `word/endnotes.xml` with entries at IDs 0, 1, and 3
- **THEN** `document.endnotes` contains only the entry with ID 3

<!-- @trace
source: docx-reader-nested-revisions-and-containers
updated: 2026-04-16
code:
  - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift
-->

---

### Requirement: RevisionSource enum disambiguates revision origin

The ooxml-swift package SHALL expose a public `RevisionSource` enum:

```swift
public enum RevisionSource: Equatable {
    case body
    case header(id: String)
    case footer(id: String)
    case footnote(id: Int)
    case endnote(id: Int)
}
```

`Revision` SHALL gain a `source: RevisionSource` property (default `.body`). During the revision aggregation step of `DocxReader.read`, revisions from body paragraphs SHALL have `source == .body`, and revisions from container paragraphs SHALL have the corresponding container case with the container's ID.

#### Scenario: Body revision has source .body

- **WHEN** a revision is emitted from a body paragraph
- **THEN** `revision.source == .body`

#### Scenario: Footnote revision has source .footnote(id:)

- **WHEN** a revision is emitted from footnote ID 2's paragraph
- **THEN** `revision.source == .footnote(id: 2)`

#### Scenario: Header revision has source .header(id:)

- **WHEN** a revision is emitted from header relationship `rId4`
- **THEN** `revision.source == .header(id: "rId4")`

<!-- @trace
source: docx-reader-nested-revisions-and-containers
updated: 2026-04-16
code:
  - packages/ooxml-swift/Sources/OOXMLSwift/Models/Revision.swift
-->

---

### Requirement: getRevisionsFull returns Revisions with source

`WordDocument.getRevisionsFull() -> [Revision]` SHALL return every revision in the document (body + all containers) as complete `Revision` structs including the `source` field. The existing `getRevisions()` tuple API SHALL remain unchanged and SHALL continue to return only body-sourced revisions (preserving backward compatibility).

#### Scenario: getRevisionsFull includes container revisions

- **WHEN** a document has 2 body revisions and 1 footnote revision, and a caller calls `getRevisionsFull()`
- **THEN** the returned array has 3 elements: 2 with `source == .body` and 1 with `source == .footnote(id: N)`

#### Scenario: getRevisions tuple API excludes container revisions

- **WHEN** the same document is queried via the existing `getRevisions()` tuple API
- **THEN** the returned array has 2 elements (body-only), preserving backward-compatible behavior

<!-- @trace
source: docx-reader-nested-revisions-and-containers
updated: 2026-04-16
code:
  - packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift
-->
