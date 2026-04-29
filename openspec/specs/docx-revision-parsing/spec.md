# docx-revision-parsing Specification

## Purpose

Defines the expected revision-type coverage of `DocxReader.parseParagraph` for body paragraphs — which OOXML revision elements are parsed into the public `Revision` model and how unknown elements are surfaced to callers. Scoped to the top-level paragraph switch (direct children of `<w:p>`); nested property-change revisions (`<w:rPrChange>`, `<w:pPrChange>`) and container paragraphs (headers, footers, footnotes, endnotes) extend this capability in a follow-up change.

## Requirements

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

### Requirement: Revision accept/reject SHALL find mixed-content wrappers across all document parts

When `Document.acceptRevision(id:)` or `Document.rejectRevision(id:)` is invoked for a revision whose `isMixedContentWrapper` flag is true, the helper SHALL walk every part-rooted paragraph collection — body (including nested tables and content-control children), every header, every footer, every footnote, every endnote — to locate the corresponding `unrecognizedChildren` entry whose opening tag matches the revision id. The helper SHALL return the originating part key (e.g., `word/document.xml`, `word/header1.xml`, `word/footnotes.xml`) so the caller can mark the correct part dirty.

If the helper cannot locate a matching `unrecognizedChildren` entry in any part, the caller SHALL throw `RevisionError.notFound(id)` instead of silently removing the typed `Revision` and returning success. The prior R3 behavior of removing the typed entry, marking `word/document.xml` dirty, and returning without finding the wrapper is forbidden because it produces ghost revisions on reload.

#### Scenario: acceptRevision on header-paragraph mixed-content wrapper unwraps in header part

- **GIVEN** a document whose `word/header1.xml` contains a paragraph with `<w:ins w:id="9" w:author="Bob"><w:hyperlink r:id="rId2"><w:r><w:t>head-link</w:t></w:r></w:hyperlink></w:ins>` and that revision was propagated to `document.revisions.revisions` with `isMixedContentWrapper == true`
- **WHEN** `document.acceptRevision(id: 9)` is invoked and the document is written back via `DocxWriter` then re-read via `DocxReader`
- **THEN** the re-read document's `word/header1.xml` paragraph contains the inner `<w:hyperlink>` content WITHOUT the `<w:ins>` wrapper
- **AND** `document.revisions.revisions` no longer contains a Revision with id == 9
- **AND** `document.modifiedParts` after acceptance includes `word/header1.xml` (not `word/document.xml`)

#### Scenario: rejectRevision on footnote mixed-content wrapper removes from footnotes part

- **GIVEN** a document whose `word/footnotes.xml` contains a paragraph with `<w:del w:id="11" w:author="Bob"><w:hyperlink r:id="rId3"><w:r><w:t>doomed</w:t></w:r></w:hyperlink></w:del>`
- **WHEN** `document.rejectRevision(id: 11)` is invoked, the document is round-tripped through `DocxWriter` then `DocxReader`
- **THEN** the re-read document's footnote paragraph does NOT contain `<w:del w:id="11"` and does NOT contain the inner hyperlink (deletion rejected restores deleted content; here `w:del` rejected means content stays but for a deletion-rejected wrapper unwrap behavior, see R3 spec — this scenario tests the wrapper is removed from the correct part)
- **AND** `document.revisions.revisions` no longer contains a Revision with id == 11
- **AND** `document.modifiedParts` after rejection includes `word/footnotes.xml`

#### Scenario: acceptRevision on missing wrapper raises notFound

- **GIVEN** a document where `document.revisions.revisions` contains a `Revision` with id == 99 but no paragraph in any part has a matching `unrecognizedChildren` entry whose opening tag contains `w:id="99"`
- **WHEN** `document.acceptRevision(id: 99)` is invoked
- **THEN** the call throws `RevisionError.notFound(99)`
- **AND** `document.revisions.revisions` is NOT mutated
- **AND** `document.modifiedParts` is NOT mutated

### Requirement: DocxReader SHALL propagate typed Revisions from block-level SDT children into document.revisions.revisions

When `DocxReader.read()` post-processes paragraphs to populate `document.revisions.revisions` from per-paragraph `revisions` arrays, the post-processor SHALL recurse into every `BodyChild.contentControl` to visit the content control's child paragraphs and tables, propagating any typed `Revision` entries found there. The R3-NEW-4 behavior of `case .contentControl: break` (skipping the recursion) is forbidden because it makes block-level SDT-wrapped revisions invisible to MCP `accept_revision` (the lookup `revisions.firstIndex(where: $0.id == id)` returns nil → throws notFound for revisions that physically exist in the model's per-paragraph storage).

#### Scenario: Block-level SDT-wrapped revision surfaces in document.revisions.revisions

- **GIVEN** source XML with `<w:sdt><w:sdtContent><w:p><w:ins w:id="13"><w:hyperlink><w:r><w:t>x</w:t></w:r></w:hyperlink></w:ins></w:p></w:sdtContent></w:sdt>` as a body-level structured document tag
- **WHEN** `DocxReader.read()` parses the document
- **THEN** `document.revisions.revisions` contains a `Revision` with `id == 13`, `type == .insertion`, `isMixedContentWrapper == true`
- **AND** `document.acceptRevision(id: 13)` does NOT throw `notFound`
- **AND** after acceptance + roundtrip, the SDT's inner paragraph contains the unwrapped hyperlink without the `<w:ins>` wrapper

<!-- @trace
source: che-word-mcp-issue-56-r4-stack-completion
updated: 2026-04-26
code:
  - packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift
  - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift
-->

### Requirement: Mixed-content revision wrappers SHALL populate both raw and typed representations

When `DocxReader.parseParagraph` encounters a revision wrapper element (`<w:ins>`, `<w:del>`, `<w:moveFrom>`, or `<w:moveTo>`) that has at least one direct child element other than `<w:r>` (e.g., a nested `<w:hyperlink>`, a nested `<w:sdt>`, a nested bookmark marker), the parser SHALL:

1. Append the wrapper's verbatim XML string to `paragraph.unrecognizedChildren` for byte-equivalent emit (the existing P0-7 behavior).
2. ALSO append a `Revision` entry to `paragraph.revisions` with `id`, `type`, `author`, and `date` populated from the wrapper's attributes. `originalText` and `newText` SHALL be the concatenated text of all `<w:r>` descendants of the wrapper (best-effort plain-text extraction). This `Revision` entry SHALL carry a marker (e.g., `isMixedContentWrapper: Bool == true`) indicating that mutation operations on this entry must coordinate with `unrecognizedChildren` to maintain consistency.

`Document.acceptRevision` and `Document.rejectRevision` SHALL detect mixed-content wrapper revisions (via the marker) and, in addition to removing the typed `Revision` entry, strip the corresponding raw entry from `unrecognizedChildren` (or unwrap the inner content into the surrounding paragraph for `accept`).

#### Scenario: w:ins wrapping a hyperlink populates both representations

- **GIVEN** source paragraph XML containing `<w:ins w:id="5" w:author="Alice" w:date="2026-04-25T10:00:00Z"><w:hyperlink r:id="rId1"><w:r><w:t>linked</w:t></w:r></w:hyperlink></w:ins>`
- **WHEN** the paragraph is parsed by `DocxReader`
- **THEN** `paragraph.unrecognizedChildren` contains exactly one entry whose XML string starts with `<w:ins w:id="5"` and ends with `</w:ins>`
- **AND** `paragraph.revisions` contains exactly one `Revision` with `id == 5`, `type == .insertion`, `author == "Alice"`, `newText == "linked"`

#### Scenario: acceptRevision on mixed-content wrapper unwraps inner content

- **GIVEN** a paragraph with one mixed-content `<w:ins>` revision (id=5) wrapping a hyperlink, captured per the previous scenario
- **WHEN** `document.acceptRevision(id: 5)` is invoked and the document is re-emitted
- **THEN** the emitted XML contains the inner `<w:hyperlink>` content WITHOUT the `<w:ins>` wrapper
- **AND** `paragraph.revisions` no longer contains a Revision with id == 5
- **AND** `paragraph.unrecognizedChildren` no longer contains the `<w:ins>` raw entry

#### Scenario: rejectRevision on mixed-content insertion removes the entire wrapper and content

- **GIVEN** the same starting state as the acceptRevision scenario
- **WHEN** `document.rejectRevision(id: 5)` is invoked and the document is re-emitted
- **THEN** the emitted XML does NOT contain `<w:ins w:id="5"` and does NOT contain the inner hyperlink
- **AND** `paragraph.revisions` no longer contains a Revision with id == 5
- **AND** `paragraph.unrecognizedChildren` no longer contains the `<w:ins>` raw entry

<!-- @trace
source: che-word-mcp-issue-56-r3-stack-completion
updated: 2026-04-27
-->
