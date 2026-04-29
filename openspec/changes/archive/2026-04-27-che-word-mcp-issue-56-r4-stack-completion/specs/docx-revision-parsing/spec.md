## ADDED Requirements

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
