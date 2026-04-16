## Why

After Part A+D shipped in [ooxml-swift v0.5.7](https://github.com/PsychQuant/ooxml-swift/releases/tag/v0.5.7), `DocxReader` now parses 4 of 7 `RevisionType` cases (`ins`, `del`, `moveFrom`, `moveTo`) and has a debug logging flag for unrecognized elements. The remaining parser gap — Parts B and C of [PsychQuant/ooxml-swift#1](https://github.com/PsychQuant/ooxml-swift/issues/1) — is:

- **Part B**: `rPrChange` (run formatting change) and `pPrChange` (paragraph property change) are structurally nested inside `<w:rPr>` and `<w:pPr>` respectively, not at the top-level `<w:p>` switch. They are invisible to the current parser because `parseParagraphProperties` and `parseRunProperties` do not descend into change-tracking sub-elements.
- **Part C**: `DocxReader.read()` only walks `document.body.children`. Any revision inside a header, footer, footnote, or endnote is completely invisible — `document.headers`, `document.footers`, `document.footnotes`, `document.endnotes` remain empty on the read path (models exist but are write-only today). Academic manuscripts commonly have footnote revisions, header adjustments, and footer page-number changes under track changes.

This change closes Parts B+C, bringing revision coverage to 6/7 types (`rPrChange2` is retained in the enum but not emitted — awaiting real-world evidence per discuss conclusion) across all document containers. It also introduces `Revision.source` and `WordDocument.getRevisionsFull()` so callers can disambiguate "revision in body paragraph 5" from "revision in footnote paragraph 5".

## What Changes

### Part B — Nested revision parsing

- **`parseRunProperties` descends into `<w:rPrChange>`**: when a `<w:rPr>` element contains a `<w:rPrChange>` child, the parser emits a `Revision(type: .formatChange, ...)` carrying the `w:id`, `w:author`, `w:date` attributes from the change element. The prior formatting (the child `<w:rPr>` inside `<w:rPrChange>`) is stored in a new optional `Revision.previousFormatDescription: String?` field as a human-readable summary (e.g., "bold, italic 12pt").
- **`parseParagraphProperties` descends into `<w:pPrChange>`**: same pattern — emits `Revision(type: .paragraphChange, ...)` with prior properties summarized in `previousFormatDescription`.
- **`rPrChange2`**: enum case `.formatting` retained, parser does NOT emit it. No matching OOXML element has been confirmed in real-world documents.

### Part C — Container iteration

- **New internal parse functions**: `parseHeaderPart(from:relationships:styles:numbering:)`, `parseFooterPart(...)`, `parseFootnotesPart(...)`, `parseEndnotesPart(...)` in `DocxReader.swift`. Each reads the corresponding `word/*.xml` part from the ZIP, iterates its `<w:p>` children using the existing `parseParagraph` function, and populates the document model.
- **`document.headers`, `.footers`, `.footnotes`, `.endnotes`** populated on the read path (currently write-only). Each model type already exists in `Models/`.
- **Revision aggregation extended**: step 10 of `DocxReader.read()` (line 87–107) extended to walk paragraphs in headers, footers, footnotes, and endnotes after body paragraphs.

### New public API surface

- **`Revision.source: RevisionSource`** — new enum with cases `.body`, `.header(id: String)`, `.footer(id: String)`, `.footnote(id: Int)`, `.endnote(id: Int)`. Populated during revision aggregation. Existing revisions from body get `.body`.
- **`WordDocument.getRevisionsFull() -> [Revision]`** — additive API returning the full `Revision` struct (which now includes `source`). Mirrors the `getCommentsFull()` pattern from v0.5.6. Existing tuple-returning `getRevisions()` unchanged (does not expose `source` — backward compatible).
- **`Revision.previousFormatDescription: String?`** — optional field populated only for `.formatChange` and `.paragraphChange` types.

## Non-Goals

<!-- Non-Goals live in design.md since design.md will be created. -->

## Capabilities

### New Capabilities

- `docx-container-parsing`: Defines the expected container-reading coverage of `DocxReader.read()` — which OOXML parts (`word/header*.xml`, `word/footer*.xml`, `word/footnotes.xml`, `word/endnotes.xml`) are read and how their paragraph content populates the `WordDocument` model. Includes the `Revision.source` enum and `getRevisionsFull()` API for disambiguating where each revision originated.

### Modified Capabilities

- `docx-revision-parsing`: ADDS requirements for `rPrChange` and `pPrChange` nested revision parsing. MODIFIES the revision aggregation requirement to include container paragraphs. ADDS `Revision.previousFormatDescription` field to the existing revision model.

## Impact

- **Affected specs**:
  - New: `openspec/specs/docx-container-parsing/spec.md`
  - Modified: `openspec/specs/docx-revision-parsing/spec.md`
- **Affected code**:
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift`
    - `parseRunProperties`: detect `<w:rPrChange>` child, emit `Revision`
    - `parseParagraphProperties`: detect `<w:pPrChange>` child, emit `Revision`
    - New: `parseHeaderPart`, `parseFooterPart`, `parseFootnotesPart`, `parseEndnotesPart`
    - Step 10 revision aggregation: extended loop for container paragraphs with `source` assignment
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Revision.swift`
    - New: `RevisionSource` enum
    - New: `Revision.source: RevisionSource` property (default `.body`)
    - New: `Revision.previousFormatDescription: String?` property
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift`
    - New: `WordDocument.getRevisionsFull() -> [Revision]` (additive, mirrors `getCommentsFull`)
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/NestedRevisionTests.swift`
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/ContainerParsingTests.swift`
  - Modified: `packages/ooxml-swift/CHANGELOG.md`
- **Public API**:
  - New types: `RevisionSource` enum
  - New properties: `Revision.source`, `Revision.previousFormatDescription`
  - New method: `WordDocument.getRevisionsFull() -> [Revision]`
  - Existing `getRevisions()` tuple API: unchanged (no `source` field in tuple — backward compatible)
  - **Version**: ooxml-swift v0.6.0 (minor bump — new public types + new method, no breaking changes)
- **Downstream**:
  - `che-word-mcp`: no mandatory code changes. The additional revisions simply appear in `get_revisions` output. Optionally, `export_revision_summary_markdown` and `export_comment_threads_markdown` could call `getRevisionsFull()` to display `source` — but that's a separate follow-up, not part of this change.
  - ooxml-swift#1: fully closes upon completion of this change.
