## ADDED Requirements

### Requirement: Issue #56 R5 stack regression tests SHALL exercise full save then re-read roundtrip

Every regression test added in `packages/ooxml-swift/Tests/OOXMLSwiftTests/Issue56R4StackTests.swift` for issue #56 R5 stack completion (one per P0 finding plus one per P1 finding from R4 verify) SHALL invoke a roundtrip helper that performs `DocxWriter().write(document, to: tmpURL)` followed by `DocxReader().read(from: tmpURL)` before making any assertion. Tests that assert only on the in-memory model (without writing then re-reading) are forbidden because the R2→R3→R4 cycle proved that in-memory-only assertions miss writer regressions.

A reusable helper SHALL be added at `packages/ooxml-swift/Tests/OOXMLSwiftTests/Helpers/RoundtripHelper.swift` exposing `func roundtrip(_ document: Document) throws -> Document` that:

- Writes the document to a unique temporary URL under `FileManager.default.temporaryDirectory`.
- Reads the document back from that URL.
- Cleans up the temporary file via `defer`.
- Returns the re-read document for caller assertions.

#### Scenario: R4 P0 #1 mixed-content header revision test asserts post-roundtrip

- **GIVEN** a test for the requirement "Revision accept/reject SHALL find mixed-content wrappers across all document parts" targeting a header-paragraph wrapper
- **WHEN** the test invokes `document.acceptRevision(id: 9)`
- **THEN** the test calls `let reread = try roundtrip(document)` after the accept call
- **AND** assertions are made against `reread.headers[0]` content (not against in-memory `document.headers[0]`)

### Requirement: Issue56R3StackTests SHALL gain RoundtripVariants test group exercising the same fixtures with save-reread

`packages/ooxml-swift/Tests/OOXMLSwiftTests/Issue56R3StackTests.swift` SHALL gain a parallel test group named `RoundtripVariants` (or method-name suffix `_RoundtripVariant`) wrapping each of the 12 R3 stack tests through the new `roundtrip(_:)` helper. The wrapper test SHALL perform the same setup and mutation as the in-memory R3 test, then call `roundtrip(document)` and re-assert. Any R3 test whose roundtrip variant fails SHALL be addressed by an R5 fix or documented as an explicit R5 limitation in `Issue56R4StackTests.swift`.

#### Scenario: R3-NEW-1 hyperlink replaceText roundtrip variant exists and passes

- **GIVEN** the existing R3 test `testReplaceTextInsideHyperlinkAppliesAndPersists`
- **WHEN** the R5 stack adds the parallel test `testReplaceTextInsideHyperlinkAppliesAndPersists_RoundtripVariant`
- **THEN** the variant performs the same `replaceText` call
- **AND** the variant calls `let reread = try roundtrip(document)` after the replaceText
- **AND** the variant asserts the replacement is present in `reread` (the on-disk written then re-read document)

<!-- @trace
source: che-word-mcp-issue-56-r4-stack-completion
updated: 2026-04-26
code:
  - packages/ooxml-swift/Tests/OOXMLSwiftTests/Helpers/RoundtripHelper.swift
  - packages/ooxml-swift/Tests/OOXMLSwiftTests/Issue56R4StackTests.swift
  - packages/ooxml-swift/Tests/OOXMLSwiftTests/Issue56R3StackTests.swift
-->
