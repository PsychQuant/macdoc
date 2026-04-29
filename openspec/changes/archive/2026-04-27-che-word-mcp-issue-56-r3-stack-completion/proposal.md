## Why

Round 3 verification of #56 (`PsychQuant/che-word-mcp` issue 56, [comment 4321007538](https://github.com/PsychQuant/che-word-mcp/issues/56#issuecomment-4321007538)) found **6 new P0 regressions** introduced by the v3.13.3 / ooxml-swift v0.19.3 fixes themselves. The R2 → R3 cycle exposed a shared anti-pattern: bundle-of-fixes that "save absence" (does X get emitted at all?) but break "preserve order / sync mutation paths" (does the editing API still work? does SDT keep its source position? does the typed model still see the wrapper?). Continuing the bundle-iteration loop has produced 8→6→? new P0 in two rounds — we need to break the chain by making each fix an independent, spec-defined task with isolated acceptance criteria.

## What Changes

Six P0 bug fixes (each must independently pass verification) plus three P1 follow-ups:

- **R3-NEW-1** Hyperlink mutation API must round-trip on source-loaded hyperlinks. `Hyperlink.text` setter, `replaceInParagraphSurfaces`, and `updateHyperlink` SHALL invalidate or sync the `children: [HyperlinkChild]` array so the writer reflects mutations. Recommend: drop `children` priority — emit `children` only when `runs.isEmpty`.
- **R3-NEW-2** Add `position: Int` to `ContentControl`. `DocxReader.parseParagraph` SHALL pass `childPosition` when calling `SDTParser.parseSDT`. `Paragraph.toXMLSortedByPosition` SHALL include `<w:sdt>` in the positioned-entry list so paragraph-level SDT round-trips at its source position.
- **R3-NEW-3** Add `insertCommentSyncingMarkers` symmetric to the existing `appendBookmarkSyncingMarkers`. When `insertComment` runs on a paragraph that already has source-loaded `commentRangeMarkers`, the new `commentId` SHALL produce matching `<w:commentRangeStart>` / `<w:commentReference>` / `<w:commentRangeEnd>` markers.
- **R3-NEW-4** Revision wrapper raw capture (introduced in P0-7) SHALL ALSO append a typed `Revision` entry to `paragraph.revisions`. MCP tools (`get_revisions` / `accept_revision` / `reject_revision` / `accept_all_revisions` / `reject_all_revisions`) SHALL see the wrapper via the typed model while raw XML drives byte-equivalent emit.
- **R3-NEW-5** `nextBookmarkId` calibration SHALL recursively scan `body.children` (including table cells and block-level SDT children) plus headers, footers, footnotes, and endnotes. Current implementation only walks top-level `body.children` `.paragraph` cases.
- **R3-NEW-6** `RunProperties.rStyle` value SHALL be XML-escaped at emit time. Audit pre-existing direct-emit attributes (`color`, `fontName`, etc.) for the same anti-pattern and escape them in the same fix.

P1 follow-ups bundled because they share the same surfaces:

- **D-3** `XMLElement.namespaces` SHALL flow into `rawAttributes` so vendor `xmlns:` declarations on `<w:hyperlink>` survive round-trip (Word otherwise rejects unbound prefix).
- **D-8** `Hyperlink.id` format change `rId5` → `rId5@7` (introduced in P1-7) is a breaking change for callers that stored old IDs — add release-notes warning.

**Non-Breaking**: All fixes restore intended behavior. R3-NEW-1 reverts a mis-prioritization in P0-3 rather than introducing new public API.

## Non-Goals

- **Not in scope**: D-2 (empty `<w:hyperlink/>` round-trip styling), D-4/D-5/D-6/D-7 (P2 cosmetics), R-P3-1 (`Hyperlink.text` setter loses Hyperlink style — pre-existing). These remain deferred follow-ups.
- **Not refactor**: We are NOT redesigning the `HyperlinkChild` / `unrecognizedChildren` / `commentRangeMarkers.isEmpty` patterns — only adding the missing sync paths. A future change can revisit the architecture once #56 is closed.
- **Not bundle**: Each P0 SHALL be a separately-verifiable task with its own scenario in the corresponding spec. Bundle-emit is what produced the R2 → R3 regression chain — explicitly avoiding it here.
- **Reject "wait for v0.20 architecture refactor"**: Production users of v3.13.3 hit silent edit-failure on every source-loaded hyperlink today (R3-NEW-1). Cannot defer.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `ooxml-roundtrip-fidelity`: Add requirements for hyperlink-mutation round-trip (R3-NEW-1), insertComment marker sync (R3-NEW-3), and XML attribute escaping at emit (R3-NEW-6).
- `ooxml-paragraph-child-schema-coverage`: Add requirement that `ContentControl` (`<w:sdt>`) carries `position: Int` matching the schema's existing "every legal child has position" rule (R3-NEW-2). Add requirement that `nextBookmarkId` calibration scope covers tables / block SDT / headers / footers / footnotes / endnotes (R3-NEW-5).
- `docx-revision-parsing`: Add requirement that mixed-content revision wrappers populate BOTH `paragraph.unrecognizedChildren` (verbatim) AND `paragraph.revisions` (typed model) so MCP tools can see them (R3-NEW-4).

## Impact

- Affected specs: `ooxml-roundtrip-fidelity`, `ooxml-paragraph-child-schema-coverage`, `docx-revision-parsing`
- Affected code:
  - Modified:
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Hyperlink.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Field.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Paragraph.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Run.swift
    - packages/ooxml-swift/IO/DocxReader.swift
    - packages/ooxml-swift/Tests/OOXMLSwiftTests/Issue56RoundtripCompletenessTests.swift
    - packages/ooxml-swift/CHANGELOG.md
    - mcp/che-word-mcp/Package.swift
    - mcp/che-word-mcp/CHANGELOG.md
    - mcp/che-word-mcp/mcpb/manifest.json
  - New:
    - packages/ooxml-swift/Tests/OOXMLSwiftTests/Issue56R3StackTests.swift
- Affected APIs: `Hyperlink.children` semantics (priority demoted), `ContentControl.position` (new field), `Document.insertComment` (now syncs markers), `paragraph.revisions` (now populated for raw-captured wrappers), XML attribute emit safety (escaping)
- Affected packages: `PsychQuant/ooxml-swift` v0.19.4, `PsychQuant/che-word-mcp` v3.13.4
- Affected marketplace: `psychquant-claude-plugins` plugin entry for `che-word-mcp`
