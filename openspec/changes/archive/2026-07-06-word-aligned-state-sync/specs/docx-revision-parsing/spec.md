## ADDED Requirements

### Requirement: Revision elements preserved via tree on round-trip

`DocxReader.parseParagraph` SHALL parse known revision elements (`<w:ins>`, `<w:del>`, `<w:moveFrom>`, `<w:moveTo>`, `<w:rPrChange>`, `<w:pPrChange>`) into typed `Revision` accessors AND retain the underlying `XmlNode` representation. Round-trip with no mutations SHALL produce byte-equal revision markup in the output.

#### Scenario: Revision metadata survives round-trip

- **GIVEN** a paragraph containing `<w:ins w:id="42" w:author="Alice" w:date="2026-05-04T10:00:00Z"><w:r>...</w:r></w:ins>`
- **WHEN** the document is read and written with no mutations
- **THEN** the output contains the same `<w:ins>` element byte-equal to the input, including `w:id`, `w:author`, and `w:date` attributes

### Requirement: Unknown revision children are preserved verbatim

`DocxReader.parseParagraph` SHALL NOT surface unknown revision children as opaque `unknown` sentinel placeholders. Unknown children SHALL pass through to the `XmlNode` tree and round-trip byte-equal.

#### Scenario: w16 revision extension is preserved

- **GIVEN** a paragraph containing `<w16cid:commentsExtensible w16cid:durableId="123ABC"/>` (a future Word revision-extension namespace)
- **WHEN** the document is read and written with no mutations
- **THEN** the output contains the same `<w16cid:commentsExtensible>` element byte-equal to the input
- **AND** no typed model surfaces an `unknown` revision sentinel for this element

### Requirement: Nested property-change revisions round-trip via tree

Nested property-change revisions (`<w:rPrChange>` inside `<w:rPr>`, `<w:pPrChange>` inside `<w:pPr>`) SHALL round-trip byte-equal when unmodified, regardless of whether the typed `Revision` view exposes them.

#### Scenario: rPrChange survives round-trip

- **GIVEN** a run with `<w:rPr><w:rPrChange w:id="7" w:author="Alice"><w:rPr><w:b/></w:rPr></w:rPrChange></w:rPr>`
- **WHEN** the document is read and written with no mutations
- **THEN** the output contains the `<w:rPrChange>` element byte-equal to the input including its nested `<w:rPr>` snapshot

### Requirement: Revision-source typed view backed by tree

The existing `Revision.source` enum and `getRevisionsFull()` API SHALL continue to disambiguate where each revision originated (body vs. header vs. footer vs. footnote vs. endnote vs. comment). Their backing storage moves to the `XmlNode` tree; observable behavior of the typed API is unchanged.

#### Scenario: Revisions report container source after the change

- **GIVEN** a docx with revisions in body, header1, and footnote1
- **WHEN** `getRevisionsFull()` is called
- **THEN** the returned revisions carry `source` enum values matching their containers (`.body`, `.header(id: 1)`, `.footnote(id: 1)`) — identical observable behavior to the pre-change implementation
