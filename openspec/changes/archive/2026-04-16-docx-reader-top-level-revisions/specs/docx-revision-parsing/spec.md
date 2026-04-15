## ADDED Requirements

### Requirement: DocxReader parses w:ins insertion revisions

`DocxReader.parseParagraph` SHALL emit a `Revision` with `type == .insertion` for every `<w:ins>` element appearing as a direct child of a paragraph (`<w:p>`). The emitted revision SHALL carry:

- `id`: the integer value of the `w:id` attribute (or 0 if missing / non-numeric)
- `type`: `.insertion`
- `author`: the string value of the `w:author` attribute (or `"Unknown"` if missing)
- `date`: the ISO8601-parsed `w:date` attribute (or the current date if missing / unparseable)
- `originalText`: `nil`
- `newText`: concatenated text of all nested `<w:r>` children's runs

#### Scenario: Insertion with text content emits revision

- **WHEN** a paragraph XML contains `<w:ins w:id="1" w:author="Alice" w:date="2026-04-16T10:00:00Z"><w:r><w:t>hello</w:t></w:r></w:ins>`
- **THEN** `paragraph.revisions` contains exactly one `Revision` with `id == 1`, `type == .insertion`, `author == "Alice"`, `newText == "hello"`, `originalText == nil`

#### Scenario: Insertion with empty content emits no revision

- **WHEN** a `<w:ins>` element has no nested `<w:r>` children, or its children produce no text
- **THEN** no `Revision` is appended for that element

<!-- @trace
source: docx-reader-top-level-revisions
updated: 2026-04-16
code:
  - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift
-->

---

### Requirement: DocxReader parses w:del deletion revisions

`DocxReader.parseParagraph` SHALL emit a `Revision` with `type == .deletion` for every `<w:del>` element appearing as a direct child of a paragraph (`<w:p>`). The emitted revision SHALL carry:

- `id`: the integer value of the `w:id` attribute (or 0 if missing)
- `type`: `.deletion`
- `author`: the string value of the `w:author` attribute (or `"Unknown"` if missing)
- `date`: the ISO8601-parsed `w:date` attribute (or the current date if missing)
- `originalText`: concatenated text of all nested `<w:r><w:delText>` children
- `newText`: `nil`

#### Scenario: Deletion with delText emits revision

- **WHEN** a paragraph XML contains `<w:del w:id="2" w:author="Bob" w:date="2026-04-16T11:00:00Z"><w:r><w:delText>removed</w:delText></w:r></w:del>`
- **THEN** `paragraph.revisions` contains a `Revision` with `type == .deletion`, `author == "Bob"`, `originalText == "removed"`, `newText == nil`

#### Scenario: Deletion with empty content emits no revision

- **WHEN** a `<w:del>` element has no nested `<w:r><w:delText>` or the delText elements are empty
- **THEN** no `Revision` is appended for that element

<!-- @trace
source: docx-reader-top-level-revisions
updated: 2026-04-16
code:
  - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift
-->

---

### Requirement: DocxReader parses w:moveFrom revisions

`DocxReader.parseParagraph` SHALL emit a `Revision` with `type == .moveFrom` for every `<w:moveFrom>` element appearing as a direct child of a paragraph (`<w:p>`). The emitted revision SHALL carry:

- `id`: the integer value of the `w:id` attribute (or 0 if missing)
- `type`: `.moveFrom`
- `author`: the string value of the `w:author` attribute (or `"Unknown"` if missing)
- `date`: the ISO8601-parsed `w:date` attribute (or the current date if missing)
- `originalText`: concatenated text of all nested `<w:r>` children (representing the text that was moved out)
- `newText`: `nil`

The nested `<w:r>` children SHALL also be appended to `paragraph.runs` so document text extraction includes the moved-from content in its original position.

#### Scenario: moveFrom with text content emits revision

- **WHEN** a paragraph XML contains `<w:moveFrom w:id="3" w:author="Alice" w:date="2026-04-16T12:00:00Z"><w:r><w:t>moved source</w:t></w:r></w:moveFrom>`
- **THEN** `paragraph.revisions` contains a `Revision` with `id == 3`, `type == .moveFrom`, `author == "Alice"`, `originalText == "moved source"`, `newText == nil`

#### Scenario: moveFrom with multiple runs concatenates text

- **WHEN** `<w:moveFrom>` contains two `<w:r><w:t>` children with text `"first "` and `"second"`
- **THEN** the emitted `Revision.originalText` equals `"first second"`

<!-- @trace
source: docx-reader-top-level-revisions
updated: 2026-04-16
code:
  - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift
-->

---

### Requirement: DocxReader parses w:moveTo revisions

`DocxReader.parseParagraph` SHALL emit a `Revision` with `type == .moveTo` for every `<w:moveTo>` element appearing as a direct child of a paragraph (`<w:p>`). The emitted revision SHALL carry:

- `id`: the integer value of the `w:id` attribute (or 0 if missing)
- `type`: `.moveTo`
- `author`: the string value of the `w:author` attribute (or `"Unknown"` if missing)
- `date`: the ISO8601-parsed `w:date` attribute (or the current date if missing)
- `originalText`: `nil`
- `newText`: concatenated text of all nested `<w:r>` children (representing the text that was moved in)

The nested `<w:r>` children SHALL also be appended to `paragraph.runs` so document text extraction includes the moved-to content.

#### Scenario: moveTo with text content emits revision

- **WHEN** a paragraph XML contains `<w:moveTo w:id="4" w:author="Alice" w:date="2026-04-16T12:00:00Z"><w:r><w:t>moved destination</w:t></w:r></w:moveTo>`
- **THEN** `paragraph.revisions` contains a `Revision` with `id == 4`, `type == .moveTo`, `author == "Alice"`, `newText == "moved destination"`, `originalText == nil`

#### Scenario: moveTo and moveFrom pair share revision id

- **WHEN** a document has `<w:moveFrom w:id="5" .../>` in one paragraph and `<w:moveTo w:id="5" .../>` in another
- **THEN** two separate `Revision` objects are emitted (one per paragraph) both with `id == 5`, allowing callers to correlate source and destination by id

<!-- @trace
source: docx-reader-top-level-revisions
updated: 2026-04-16
code:
  - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift
-->

---

### Requirement: DocxReader surfaces unknown paragraph elements via debug logging

`DocxReader` SHALL expose a public static `debugLoggingEnabled: Bool` flag (default `false`). When `true`, `DocxReader.parseParagraph` SHALL write a single line to `FileHandle.standardError` for each direct child of `<w:p>` whose local name is not one of `r`, `ins`, `del`, `moveFrom`, `moveTo`, `commentRangeStart`, `commentRangeEnd`, `commentReference`, `pPr`, `bookmarkStart`, `bookmarkEnd`, `hyperlink`, `fldSimple`, `sdt`.

The log line format SHALL be: `"DocxReader.parseParagraph: skipped unknown element <localName>\n"`.

When the flag is `false` (default), no output is produced and parsing performance is unchanged (the guard SHALL be evaluated before any string interpolation).

#### Scenario: Default flag value produces no logs

- **WHEN** `DocxReader.debugLoggingEnabled` is left at its default `false` and a paragraph contains an unknown element
- **THEN** nothing is written to stderr and parsing completes normally with the unknown element silently skipped

#### Scenario: Enabled flag emits one line per unknown element

- **WHEN** a test sets `DocxReader.debugLoggingEnabled = true` and parses a paragraph containing a `<w:customElement/>` child
- **THEN** exactly one line `"DocxReader.parseParagraph: skipped unknown element customElement\n"` is written to stderr

#### Scenario: Known elements produce no log output when flag enabled

- **WHEN** the flag is `true` and a paragraph contains only `<w:r>`, `<w:ins>`, or other recognized elements
- **THEN** no log lines are emitted

<!-- @trace
source: docx-reader-top-level-revisions
updated: 2026-04-16
code:
  - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift
-->

---

### Requirement: Revision aggregation preserves revision order

The `WordDocument.revisions` array populated during `DocxReader.read` SHALL contain all `Revision` objects emitted from body paragraphs in document order (the paragraph index assigned to each revision SHALL match the `body.children` enumeration order of its source paragraph).

#### Scenario: Revisions in document order

- **WHEN** a document has two paragraphs — paragraph 0 contains an insertion, paragraph 2 contains a moveFrom — and the document is read via `DocxReader.read(from:)`
- **THEN** `document.revisions.revisions` contains two entries: the insertion with `paragraphIndex == 0` first, the moveFrom with `paragraphIndex == 2` second

#### Scenario: Multiple revisions in same paragraph preserve child order

- **WHEN** a single paragraph contains `<w:ins>` followed by `<w:moveTo>`
- **THEN** `paragraph.revisions` lists the insertion before the moveTo, and both carry the same `paragraphIndex`

<!-- @trace
source: docx-reader-top-level-revisions
updated: 2026-04-16
code:
  - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift
-->
