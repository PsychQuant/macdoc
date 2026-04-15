## Why

`DocxReader.parseParagraph` in `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift` silently drops revision elements that are not `w:ins` or `w:del`. The `RevisionType` enum declares 7 cases; only 2 are actually emitted by the parser. All downstream consumers — including che-word-mcp v1.19.0's `get_revisions`, `compare_documents`, and the newly-shipped `export_revision_summary_markdown` / `compare_documents_markdown` / `export_comment_threads_markdown` tools — undercount revisions on any document that uses Word's tracked move feature.

This change closes Part A + Part D of [PsychQuant/ooxml-swift#1](https://github.com/PsychQuant/ooxml-swift/issues/1) (the first of a two-change sequence per the diagnosis on that issue):

- **A**: Top-level switch expansion — parse `w:moveFrom` and `w:moveTo` elements as `moveFrom` / `moveTo` revisions alongside the existing `ins` / `del` handling.
- **D**: Defensive debug logging — replace `default: break` with a configurable debug log so future parser gaps are discoverable instead of silent.

Parts B (nested `rPrChange` / `pPrChange` inside `w:rPr` / `w:pPr`) and C (containers: headers, footers, footnotes, endnotes) are deferred to a follow-up change `docx-reader-nested-revisions-and-containers` — they require deeper parser refactors and a new `Revision.source` enum, so they ship separately once Parts A+D have landed and validated in practice.

## What Changes

- **Parse `w:moveFrom`** in `DocxReader.parseParagraph` top-level switch. Mirrors `w:del` structure: extract nested `w:r` children, collect their text as `originalText`, emit `Revision(type: .moveFrom, ...)`.
- **Parse `w:moveTo`** in the same switch. Mirrors `w:ins`: extract nested `w:r` children, collect their text as `newText`, emit `Revision(type: .moveTo, ...)`.
- **Debug logging at `default: break`** — add a static `DocxReader.debugLoggingEnabled` flag (default `false`) that when enabled emits a log line `"DocxReader.parseParagraph: skipped unknown element <localName>"` via `print(...)` to stderr. Keeps the production path allocation-free (guard before interpolation) but makes parser gaps discoverable during development.
- **Test fixtures**: add a hand-built `.docx` fixture containing insertion, deletion, moveFrom, and moveTo revisions. Verify `parseParagraph` emits 4 `Revision` objects with correct types, authors, dates, and text fields.
- **New spec capability** `docx-revision-parsing` formally documents the expected revision-type coverage at the paragraph top-level and the unknown-element logging behavior. Change 2 will MODIFY this capability to cover nested types and container paragraphs.

## Non-Goals

<!-- Non-Goals live in design.md since design.md will be created. -->

## Capabilities

### New Capabilities

- `docx-revision-parsing`: Defines the expected revision-type coverage of `DocxReader.parseParagraph` for body paragraphs — which OOXML revision elements are parsed into the public `Revision` model and how unknown elements are surfaced. Scoped narrowly to the top-level paragraph switch (not nested property-change revisions, not container paragraphs — those extend this capability in a follow-up change).

### Modified Capabilities

(none)

## Impact

- **Affected specs**:
  - New: `openspec/specs/docx-revision-parsing/spec.md`
- **Affected code**:
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift` (~25 lines added in the switch statement + `debugLoggingEnabled` flag declaration)
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/Fixtures/revisions-moves.docx` (hand-built fixture with ins/del/moveFrom/moveTo)
  - New/Modified: `packages/ooxml-swift/Tests/OOXMLSwiftTests/RevisionParsingTests.swift` (new test file) OR extend existing `DocxReaderIntegrationTests.swift`
  - Modified: `packages/ooxml-swift/CHANGELOG.md` (new `[Unreleased]` entry)
- **Public API**:
  - No new public types. `Revision` and `RevisionType` unchanged.
  - New public static flag `DocxReader.debugLoggingEnabled: Bool` (default `false`) — additive, not breaking.
- **Downstream consumers**:
  - `che-word-mcp`: no code changes required. The additional `moveFrom` / `moveTo` revisions simply start appearing in `get_revisions` output for documents that use move tracking — this is the intended fix, surfacing data that was previously dropped.
  - Other ooxml-swift consumers: none currently depend on the specific count returned by `getRevisions()`, but any that do will see higher counts on move-tracked documents (still a strict superset of previous output).
- **Release**:
  - ooxml-swift v0.5.7 (patch bump — additive coverage fix, no API break, no behavior change for documents that don't use move tracking).
  - `che-word-mcp` does NOT need a simultaneous release — it consumes ooxml-swift via `from: "0.5.6"` which automatically accepts v0.5.7. A later `swift package update` in che-word-mcp's Package.resolved picks up the fix on next build.
