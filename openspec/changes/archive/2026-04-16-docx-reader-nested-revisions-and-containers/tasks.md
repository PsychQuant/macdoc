## 1. Model changes (Revision.swift + Document.swift)

- [x] 1.1 Add `public enum RevisionSource: Equatable` to `Revision.swift` with cases `.body`, `.header(id: String)`, `.footer(id: String)`, `.footnote(id: Int)`, `.endnote(id: Int)` per Decision: RevisionSource Enum Cases
- [x] 1.2 Add `public var source: RevisionSource = .body` property to the `Revision` struct. Ensure existing `Revision` initializers default `source` to `.body` so no existing call site needs updating.
- [x] 1.3 Add `public var previousFormatDescription: String? = nil` property to the `Revision` struct per **Revision model gains previousFormatDescription field** requirement. (Note: existing `previousFormat: RunProperties?` field retained for structured access; the new field is a human-readable summary complement.)
- [x] 1.4 Add `public func getRevisionsFull() -> [Revision]` to `WordDocument` in `Document.swift`, returning `revisions.revisions` (full struct array) per Decision: getRevisionsFull Mirrors getCommentsFull Pattern. Existing `getRevisions()` tuple API unchanged.
- [x] 1.5 Build `swift build` to confirm model changes compile. No tests yet.

## 2. Part B — Nested revision tests (TDD red phase)

- [x] 2.1 [P] Write RED test `testParsesRPrChangeFormatRevision` in `NestedRevisionTests.swift` — constructs a `<w:p>` with `<w:r><w:rPr><w:rPrChange w:id="10" w:author="Alice"><w:rPr><w:b/></w:rPr></w:rPrChange></w:rPr><w:t>text</w:t></w:r>`, calls `parseParagraph`, asserts a `Revision(type: .formatChange, author: "Alice", previousFormatDescription: containing "bold")` is present per **DocxReader parses rPrChange formatting revisions** requirement.
- [x] 2.2 [P] Write RED test `testNoRPrChangeEmitsNoRevision` — constructs a run with plain `<w:rPr><w:b/></w:rPr>` (no rPrChange), asserts zero formatting revisions per the "no rPrChange" scenario.
- [x] 2.3 [P] Write RED test `testParsesPPrChangeParagraphRevision` in `NestedRevisionTests.swift` — constructs a `<w:p>` with `<w:pPr><w:pPrChange w:id="20" w:author="Bob"><w:pPr><w:jc w:val="center"/></w:pPr></w:pPrChange></w:pPr>`, calls `parseParagraph`, asserts a `Revision(type: .paragraphChange, author: "Bob", previousFormatDescription: containing "center")` per **DocxReader parses pPrChange paragraph property revisions** requirement.
- [x] 2.4 [P] Write RED test `testNoPPrChangeEmitsNoRevision` — constructs a paragraph with plain `<w:pPr><w:jc w:val="left"/></w:pPr>` (no pPrChange), asserts zero paragraph-change revisions.
- [x] 2.5 Run `swift test --filter NestedRevisionTests` to confirm RED state. (pPrChange + rPrChange tests failed for correct reasons — 0 revisions emitted; 3 passing tests covered negative/regression cases.)

## 3. Part B — Nested revision implementation (TDD green phase)

Implements Decision: rPrChange Detection Lives in parseRunProperties and Decision: pPrChange Detection Lives in parseParagraphProperties and Decision: previousFormatDescription is a Human-Readable String.

- [x] 3.1 Change `parseRunProperties` signature to add `inout [Revision]` accumulator parameter (or return revisions alongside RunProperties). Update all call sites (grep for `parseRunProperties` in `DocxReader.swift` — expect ~3 call sites).
- [x] 3.2 Inside `parseRunProperties`, after parsing the standard properties, check for `<w:rPrChange>` child. If present, extract `w:id`, `w:author`, `w:date` attributes, parse the nested `<w:rPr>` into a human-readable summary string (join names of present child elements: `w:b` → "bold", `w:i` → "italic", `w:sz` → "Npt" from val, `w:rFonts` → font name from `w:ascii` attr), and append `Revision(type: .formatChange, ..., previousFormatDescription: summary)` to the accumulator.
- [x] 3.3 Change `parseParagraphProperties` signature to add `inout [Revision]` accumulator parameter. Update all call sites (grep — expect ~2 call sites).
- [x] 3.4 Inside `parseParagraphProperties`, check for `<w:pPrChange>` child. If present, extract attributes, parse the nested `<w:pPr>` into a summary string (join names: `w:jc` → "alignment: val", `w:spacing` → "spacing: before/after", `w:ind` → "indent: left/right"), and append `Revision(type: .paragraphChange, ..., previousFormatDescription: summary)` to the accumulator.
- [x] 3.5 Thread the accumulator from `parseParagraph` → `parseRunProperties` / `parseParagraphProperties` → back to `paragraph.revisions.append(contentsOf:)`.
- [x] 3.6 Run `swift test --filter NestedRevisionTests` to confirm GREEN state for Part B tests. (5/5 GREEN. Implementation: pPrChange detected in parseParagraph after pPr block; rPrChange detected via `detectRPrChangeRevision` helper in `case "r":` block. Signatures NOT changed — used helper functions + direct paragraph.revisions.append instead of inout accumulator pattern, which is simpler and avoids cascading call-site changes.)

## 4. Part C — Container parsing tests (TDD red phase)

- [x] 4.1 [P] Write RED test `testReadsHeaderParagraphs` in `ContainerParsingTests.swift` — uses a DocxWriter-built document that has a header with a paragraph, round-trips via `DocxReader.read(from:)`, asserts `document.headers` is non-empty and contains the expected paragraph text per **DocxReader reads header parts from the ZIP** requirement.
- [x] 4.2 [P] Write RED test `testReadsFooterParagraphs` — same pattern for footers per **DocxReader reads footer parts from the ZIP** requirement.
- [x] 4.3 [P] Write RED test `testReadsFootnoteParagraphs` — uses a fixture with a footnote, asserts `document.footnotes` contains the user-authored entry (skips IDs 0/1) per **DocxReader reads footnotes from the ZIP** requirement.
- [x] 4.4 [P] Write RED test `testMissingFootnotesXMLIsNotAnError` — reads a document without `word/footnotes.xml`, asserts `document.footnotes` is empty and no error per the "missing footnotes" scenario.
- [x] 4.5 [P] Write RED test `testRevisionSourceBodyIsDefault` — reads a body revision via `getRevisionsFull()`, asserts `source == .body` per **RevisionSource enum disambiguates revision origin** requirement.
- [x] 4.6 [P] Write RED test `testGetRevisionsFullIncludesContainerRevisions` — reads a document with body + footnote revisions, calls `getRevisionsFull()`, asserts both appear with correct `source` per **getRevisionsFull returns Revisions with source** requirement.
- [x] 4.7 [P] Write RED test `testGetRevisionsTupleExcludesContainerRevisions` — same document, calls `getRevisions()` tuple API, asserts only body revisions per the backward-compat scenario.
- [x] 4.8 Run `swift test --filter ContainerParsingTests` to confirm RED state.

## 5. Part C — Container parsing implementation (TDD green phase)

Implements Decision: Container Parse Functions Mirror parseBody Structure.

- [x] 5.1 In `DocxReader.read(from:)`, after reading `word/document.xml`, add blocks to read `word/header*.xml`, `word/footer*.xml`, `word/footnotes.xml`, `word/endnotes.xml` from the ZIP. Guard each with `zip.fileExists(atPath:)` so missing parts are gracefully skipped.
- [x] 5.2 Implement `parseHeaderPart(from data: Data, relationshipId: String, relationships: ..., styles: ..., numbering: ...) -> Header` — parse the XML, iterate `<w:p>` children via `parseParagraph`, collect paragraphs into the `Header` model. Store `relationshipId` for the `RevisionSource.header(id:)`.
- [x] 5.3 Implement `parseFooterPart(...)` — mirror of header.
- [x] 5.4 Implement `parseFootnotesPart(from data: Data, ...) -> [Footnote]` — parse `<w:footnotes>`, iterate `<w:footnote>` children, skip IDs 0 and 1 (separator/continuation), parse `<w:p>` children inside each remaining footnote.
- [x] 5.5 Implement `parseEndnotesPart(...)` — mirror of footnotes, per **DocxReader reads endnotes from the ZIP** requirement.
- [x] 5.6 Populate `document.headers`, `document.footers`, `document.footnotes`, `document.endnotes` with the parsed results.
- [x] 5.7 Extend the revision aggregation step per the MODIFIED **Revision aggregation preserves revision order** requirement: (a) assign `source = .body` to existing body revisions, (b) walk header paragraphs with `source = .header(id:)`, (c) walk footer paragraphs with `source = .footer(id:)`, (d) walk footnote paragraphs with `source = .footnote(id:)`, (e) walk endnote paragraphs with `source = .endnote(id:)`. Append in that order. Container revisions follow body revisions; nested formatting revisions included alongside top-level revisions from the same paragraph.
- [x] 5.8 Ensure `getRevisions()` tuple API continues to return only `.body`-sourced revisions by filtering on `source == .body` in the mapping (or by maintaining a separate body-only collection). `getRevisionsFull()` returns the full unfiltered array.
- [x] 5.9 Run `swift test --filter ContainerParsingTests` to confirm GREEN state for Part C tests.

## 6. Regression + full suite

- [x] 6.1 Run `swift test` against the full `ooxml-swift` suite. All pre-existing 190 tests + new Part B + Part C tests SHALL pass. Investigate and fix any regressions before proceeding.
- [x] 6.2 Run `swift test` in `mcp/che-word-mcp` to confirm 30/30 still pass against the updated ooxml-swift (using path: override as in previous change).

## 7. CHANGELOG and release

Implements Decision: Minor Bump v0.6.0.

- [x] 7.1 Update `packages/ooxml-swift/CHANGELOG.md` with `[0.6.0] - YYYY-MM-DD` entry covering: rPrChange/pPrChange nested revision parsing, container reading (headers/footers/footnotes/endnotes), new `RevisionSource` enum, new `Revision.source` and `Revision.previousFormatDescription` properties, new `getRevisionsFull()` API. Link to `ooxml-swift#1`.
- [x] 7.2 Commit all changes with conventional-commit message referencing ooxml-swift#1 Part B + C.
- [x] 7.3 Tag `v0.6.0` and `git push origin main v0.6.0`.
- [x] 7.4 Optional: `swift package update` in che-word-mcp to verify v0.6.0 resolves.

## 8. Issue closure

- [x] 8.1 Close `PsychQuant/ooxml-swift#1` with a closing comment noting all 4 parts (A/B/C/D) are now shipped across v0.5.7 and v0.6.0.
- [x] 8.2 Update `PsychQuant/macdoc#75` umbrella: tick the `ooxml-swift#1` checkbox and add a 2026-04-MM progress note referencing v0.6.0.
