## ADDED Requirements

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
