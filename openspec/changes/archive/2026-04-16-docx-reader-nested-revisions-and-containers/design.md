## Context

This is Change 2 of the two-change sequence resolving [`PsychQuant/ooxml-swift#1`](https://github.com/PsychQuant/ooxml-swift/issues/1). Change 1 (`docx-reader-top-level-revisions`, archived 2026-04-16 as ooxml-swift v0.5.7) shipped Parts A+D. This change ships Parts B+C.

Current parser state (at ooxml-swift v0.5.7, commit `b02fe4f`):

- Top-level paragraph switch handles `r`, `ins`, `del`, `moveFrom`, `moveTo`, `commentRangeStart`, with debug logging for unrecognized elements.
- `parseParagraphProperties` (around line 450) reads alignment, spacing, indentation, numbering, borders, tabs, keepNext, keepLines — but does NOT look for `<w:pPrChange>` children.
- `parseRunProperties` (around line 540) reads bold, italic, font, size, color, highlight, underline, strikethrough, vertAlign — but does NOT look for `<w:rPrChange>` children.
- `read()` only walks `document.body.children`. Headers, footers, footnotes, endnotes are not read from the ZIP.
- `Revision` model has no `source` field. `getRevisions()` returns a flat tuple without container info.

## Goals / Non-Goals

**Goals:**

- Parse `<w:rPrChange>` inside `<w:rPr>` and `<w:pPrChange>` inside `<w:pPr>`, emitting `Revision(type: .formatChange)` and `Revision(type: .paragraphChange)` respectively.
- Read `word/header*.xml`, `word/footer*.xml`, `word/footnotes.xml`, `word/endnotes.xml` from the .docx ZIP and populate the existing model types.
- Aggregate revisions from container paragraphs alongside body revisions, with a new `source` field for disambiguation.
- Provide `getRevisionsFull() -> [Revision]` additive API for callers needing the `source` field.
- Fully close ooxml-swift#1 upon completion.

**Non-Goals:**

- Not emitting `Revision(type: .formatting)` for `rPrChange2`. The enum case is retained; the parser skips it. If a real-world corpus containing `<w:rPrChange2>` is found, a follow-up patch adds the case.
- Not parsing `<w:hyperlink>` or `<w:sdt>` containers for revisions — these are listed in issue #1's container table but are inline elements within paragraphs, not separate document parts. They require a different approach (inline-within-paragraph descent) that is out of scope.
- Not extending the `getRevisions()` tuple to include `source`. The tuple is frozen for backward compatibility; callers wanting `source` use `getRevisionsFull()`.
- Not updating che-word-mcp MCP tools to display `source` in output. That is a separate downstream enhancement.
- Not refactoring `parseParagraphProperties` / `parseRunProperties` return types to carry revisions as output. Instead, these functions receive a mutable `inout [Revision]` accumulator parameter for emitted revisions — minimal signature change.

## Decisions

### Decision: rPrChange Detection Lives in parseRunProperties

When `parseRunProperties` encounters a `<w:rPr>` element that contains a `<w:rPrChange>` child, it emits a `Revision(type: .formatChange, ...)` into the accumulator. The `<w:rPrChange>` element's own `<w:rPr>` child (the prior formatting) is parsed into a human-readable summary stored in `Revision.previousFormatDescription`.

**Rationale**: `<w:rPrChange>` is structurally a child of `<w:rPr>`, not of `<w:p>`. The property parser is the natural scope — it already has the context of which run properties surround the change. Threading revisions out via an `inout [Revision]` parameter is the lowest-surface approach.

**Alternatives**:
- _Return revisions as part of RunProperties struct_ — rejected; RunProperties is a plain value struct used for serialization, adding revisions to it conflates model concerns.
- _Post-process: walk all runs after parsing and check for rPrChange_ — rejected; double-traversal and fragile coupling to the run tree shape.

### Decision: pPrChange Detection Lives in parseParagraphProperties

Same pattern as rPrChange but for `<w:pPrChange>` inside `<w:pPr>`. Emits `Revision(type: .paragraphChange, ...)`.

**Rationale**: Symmetric with the rPrChange approach. Both property parsers gain the same `inout [Revision]` accumulator pattern.

### Decision: previousFormatDescription is a Human-Readable String

`Revision.previousFormatDescription: String?` stores a prose summary of the prior formatting (e.g., `"bold, italic, 12pt Times New Roman"`). It is NOT a structured `RunProperties` / `ParagraphProperties` object.

**Rationale**: Returning a full structured object would require making `RunProperties` and `ParagraphProperties` `Equatable` and `public` at a deeper level. The downstream use case (MCP tools displaying "what formatting changed") needs a display string, not a diffable struct. If structured diffing is needed later, the raw XML is preserved in the `<w:rPrChange>` child and can be re-parsed.

**Alternatives**:
- _Store the previous RunProperties struct directly_ — rejected as scope creep; RunProperties has many optional fields and nesting it inside Revision expands the public surface significantly.
- _Store raw XML string_ — rejected as unhelpful for display; callers would need to parse XML to show anything useful.

### Decision: Container Parse Functions Mirror parseBody Structure

New internal functions `parseHeaderPart`, `parseFooterPart`, `parseFootnotesPart`, `parseEndnotesPart` each accept the raw XML `Data` from the ZIP and return the corresponding model type populated with parsed paragraphs. They reuse `parseParagraph` for each `<w:p>` child, just as the body parser does.

**Rationale**: The existing parseParagraph function handles all paragraph-level elements (runs, revisions, comments, etc.). Containers are structurally sequences of paragraphs. Reusing parseParagraph gives containers the same revision/comment/formatting coverage as body paragraphs for free.

**Alternatives**:
- _Full-fidelity container reader with custom per-container logic_ — rejected; containers share the paragraph structure. Custom logic is only needed for container-specific metadata (header type, footnote ID), which is a thin wrapper around the shared paragraph parser.

### Decision: RevisionSource Enum Cases

```swift
public enum RevisionSource: Equatable {
    case body
    case header(id: String)
    case footer(id: String)
    case footnote(id: Int)
    case endnote(id: Int)
}
```

**Rationale**: `header` and `footer` use `String` IDs because OOXML relationship IDs for headers/footers are strings like `"rId4"`. `footnote` and `endnote` use `Int` IDs because their XML uses numeric `w:id` attributes. The enum is `Equatable` for test assertions.

**Alternatives**:
- _Flat string source (e.g., "header:rId4")_ — rejected; parsing the string to extract the ID loses type safety.
- _Source as a separate struct with kind + id_ — rejected; enum is simpler and exhaustive-switch-friendly.

### Decision: getRevisionsFull Mirrors getCommentsFull Pattern

`WordDocument.getRevisionsFull() -> [Revision]` returns the full `Revision` structs from `document.revisions.revisions`. This mirrors the additive `getCommentsFull()` method introduced in v0.5.6. The existing tuple-returning `getRevisions()` remains unchanged.

**Rationale**: Consistency with the established pattern. Callers that need `source` use the new method; callers that don't want to update keep using the tuple.

### Decision: Minor Bump v0.6.0

This release introduces new public types (`RevisionSource`), new public properties (`Revision.source`, `Revision.previousFormatDescription`), and a new public method (`getRevisionsFull`). Per semver, new public API surface on a pre-1.0 package warrants a minor bump.

**Alternatives**:
- _Patch bump v0.5.8_ — rejected; new types cross the "additive-only" threshold that patches cover.

## Risks / Trade-offs

- **Risk**: `<w:rPrChange>` nesting varies between Word versions. Some put the prior `<w:rPr>` directly inside `<w:rPrChange>`, others wrap it differently.
  - **Mitigation**: Test against both Word 2019 and Word 365 output formats. Use `DocxReader.debugLoggingEnabled = true` during test to catch unexpected nesting.

- **Risk**: `parseRunProperties` currently returns `RunProperties`. Adding an `inout [Revision]` parameter changes its call signature. Every call site in `DocxReader.swift` must be updated.
  - **Mitigation**: Grep for all call sites before implementation. Expect ~3-5 call sites (one per parsed `<w:rPr>` in `parseRun`, possibly one in formatting detection). Same for `parseParagraphProperties`.

- **Risk**: Container parsing may surface revisions with unexpected `paragraphIndex` values — a header might have paragraph 0, which collides with body paragraph 0.
  - **Mitigation**: `Revision.source` disambiguates. The tuple API `getRevisions()` does not expose `source`, so callers who don't adopt `getRevisionsFull()` continue to see body-only revisions (aggregation step only includes body revisions in the tuple path, container revisions only in the full path). This preserves backward compatibility at the cost of omitting container revisions from the legacy API.

- **Risk**: reading `word/footnotes.xml` and `word/endnotes.xml` may fail if these parts don't exist in a given .docx (not all documents have footnotes).
  - **Mitigation**: Guard with `zip.fileExists(atPath:)` before attempting to read. Missing parts = empty arrays, not errors.

- **Trade-off**: `previousFormatDescription` is lossy (prose summary vs structured data). A future change that needs structured formatting diffs would need to re-parse the `<w:rPrChange>` XML.
  - **Mitigation**: Acceptable for the current use case (MCP tool display). If structured diff demand arises, a `previousRunProperties: RunProperties?` field can be added alongside the description without breaking existing code.

## Open Questions

- _(none — all key decisions resolved during `/spectra-discuss` phase)_
