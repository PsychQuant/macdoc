## Why

After PsychQuant/che-word-mcp#56 closed in v3.13.5, the byte-preservation invariant for **unmodified** OOXML parts holds (verified: 0-byte delta on no-op `DocxReader.read` → `DocxWriter.write` of the thesis fixture). But on any **body-mutating** save (`open → insert_paragraph → save`), `word/document.xml` shrinks **31.7%** (1473896 → 1006805 bytes). Anatomization of the 467KB delta reveals three independent silent-loss classes, all stemming from the same architectural cause: **the typed model is the bottleneck for round-trip fidelity, and "drop if not typed" is the wrong fallback policy.**

The three issues:

| Issue | Loss | Root cause |
|---|---|---|
| PsychQuant/che-word-mcp#58 (P3) | 1 of 45 bookmarks (TOC `_Toc<digits>` anchor) | `DocxReader.parseBodyChildren` switch only handles `p`/`tbl`/`sdt`; `default: continue` silently drops body-level `<w:bookmarkStart>` (and other EG_BlockLevelElts) |
| PsychQuant/che-word-mcp#59 (P3) | 334 chars of whitespace inside `<w:t xml:space="preserve">` | Foundation `XMLDocument` strips whitespace-only text nodes at parse time, regardless of `xml:space` attribute and `.nodePreserveWhitespace` option (verified via isolated micro-test) |
| PsychQuant/che-word-mcp#60 (P1) | ~74% of `<w:rFonts>` tags (4481/6015), ~99% of `<w:noProof>` (825/828), ~98% of `w14:*` namespace refs (2326/2359), ~78% of `<w:kern>` (1097/1404), 100% of `<w:lang>` (90/90) | `RunProperties` typed model lacks fields for `noProof`, `kern`, `lang` (3-axis), full `rFonts` 4-axis (`ascii`/`hAnsi`/`eastAsia`/`cs`); no raw-passthrough for `w14:*` namespace children |

#60 alone accounts for **>99% of the visible content loss on body-mutating save**. #58 + #59 combined are <0.1%. Without bundling these under one architectural fix, the v3.13.5 closing claim ("Lossless `<w:document>` round-trip") cannot be honored.

The shared meta-cause matters: R5-CONT-4's `testRevisionTypeMatrixAcceptRejectCompleteness` matrix-pin closed structural-symmetry convergence (accept↔reject + container relationships), but does not assert body-level content-equality. A new matrix-pin (`testDocumentContentEqualityInvariant`) lands as the cross-cutting invariant that catches all three classes simultaneously and prevents future regressions.

## What Changes

Three sub-stacks ship under the unifying principle "**if not typed, preserve as raw**", landed independently as v0.19.6 → v0.19.7 → v0.20.0, with the matrix-pin extension landing alongside sub-stack C:

**Sub-stack A — #58 BodyChild block-level marker preservation (~1 day, ships v0.19.6)**:
- Extend `BodyChild` enum with typed `case bookmarkMarker(BookmarkRangeMarker)` for known kinds AND generic `case rawBlockElement(RawElement)` catch-all for forward-compat with other EG_BlockLevelElts (`<w:moveFromRangeStart>`, body-level `<w:commentRangeStart>`, vendor extensions)
- Extend `DocxReader.parseBodyChildren` switch with explicit `case "bookmarkStart"` / `case "bookmarkEnd"` branches; convert `default: continue` to `default: rawBlockElement` passthrough
- Extend `DocxWriter.xmlForBodyChild` to emit the new cases
- Extend `nextBookmarkId` calibration walker to include body-level markers

**Sub-stack B — #59 whitespace overlay scan (~3 days, ships v0.19.7)**:
- Introduce new internal `WhitespaceOverlay` value type that scans raw `word/document.xml` byte stream pre-parse, capturing `<w:t xml:space="preserve">[whitespace]</w:t>` content keyed by element sequence index (in DOM document order)
- DocxReader plumbs the overlay through to `parseRun`, which consults the overlay when `t.stringValue.isEmpty` to recover whitespace bytes that Foundation `XMLDocument` discarded
- Same overlay approach extends to header/footer/footnote/endnote/comments parts (5 additional XMLDocument call sites), since the same Foundation parser limitation affects all

**Sub-stack C — #60 RunProperties field-loss audit (~1-2 weeks, ships v0.20.0)**:
- Add typed fields to `RunProperties`: `noProof: Bool`, `kern: Int?`, `lang: LanguageProperties?` (3-axis: `val`/`eastAsia`/`bidi`)
- Audit `<w:rFonts>` parser to capture all 4 axes (`ascii`/`hAnsi`/`eastAsia`/`cs`); writer emits all 4
- Add `RunProperties.rawChildren: [RawElement]?` for unrecognized rPr direct children — primarily `w14:*` namespace effects (`<w14:textOutline>`, `<w14:glow>`, `<w14:shadow>`, `<w14:reflection>`, `<w14:textFill>`, `<w14:scene3d>`, etc.) but works as catch-all for any future vendor extensions
- Parser collects unknown rPr children; writer replays them in source-document order

**Cross-cutting matrix-pin extension (lands with sub-stack C)**:
- New test `testDocumentContentEqualityInvariant` in `Issue58_60ContentPreservationTests.swift` that asserts content equality across all three preservation classes for the thesis fixture: `<w:bookmarkStart>` count parity (catches #58 class), `<w:t>` total character count parity (catches #59 class), `<w:rFonts>`/`<w:noProof>`/`<w:lang>`/`<w:kern>`/`w14:*` count parity (catches #60 class)
- Test pattern follows R5-CONT-4 `testRevisionTypeMatrixAcceptRejectCompleteness` precedent

## Non-Goals

- Switching XML parser away from Foundation `XMLDocument` (rejected: 1-2 weeks of work + dependency churn for headers/footers/footnotes/endnotes/comments; whitespace overlay is contained, surgical, and doesn't risk v0.19.5 R5 stack stability)
- Closing the remaining 154KB element-overhead delta beyond the 313KB attribute loss (rejected: that delta is enclosing-tag bytes that drop naturally as attributes drop; once attributes preserve, element-overhead delta resolves to near-zero)
- Adding MCP tool surface for the new typed `RunProperties` fields (out of scope: existing `format_text` / `set_paragraph_format` MCP tools auto-benefit from preserved fields without API changes)
- Closing the inter-element whitespace formatting delta (1376 bytes — 0.1% of source; not user-visible)

## Capabilities

### New Capabilities

(none — all three issues extend existing capabilities)

### Modified Capabilities

- `ooxml-paragraph-child-schema-coverage`: Extended to include body-level child elements (currently scoped to `<w:p>` children); adds requirement for `BodyChild` enum to cover EG_BlockLevelElts members
- `ooxml-roundtrip-fidelity`: Extended with three new requirements covering the content-equality invariant for `<w:t>` whitespace, body-level markers, and `RunProperties` field preservation; adds matrix-pin test obligation
- `docx-container-parsing`: Extended via the whitespace overlay scope (header/footer/footnote/endnote/comments parts also gain whitespace preservation since Foundation `XMLDocument` limitation is parser-wide)

## Impact

- Affected specs:
  - `ooxml-paragraph-child-schema-coverage` (modified — body-level coverage)
  - `ooxml-roundtrip-fidelity` (modified — content-equality invariants + matrix-pin)
  - `docx-container-parsing` (modified — whitespace overlay)

- Affected code:
  - Modified:
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift (BodyChild enum extension; nextBookmarkId calibration)
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/RunProperties.swift (typed field additions; rawChildren passthrough)
    - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift (parseBodyChildren switch; parseRun whitespace consult; parseRunProperties audit; 10 XMLDocument(data:) call sites for overlay plumbing)
    - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxWriter.swift (xmlForBodyChild emit branches)
    - packages/ooxml-swift/CHANGELOG.md (v0.19.6 / v0.19.7 / v0.20.0 entries)
    - mcp/che-word-mcp/Package.swift (ooxml-swift dependency bumps for each sub-stack)
    - mcp/che-word-mcp/CHANGELOG.md (v3.13.6 / v3.13.7 / v3.14.0 entries)
    - mcp/che-word-mcp/mcpb/manifest.json (version bumps)
  - New:
    - packages/ooxml-swift/Sources/OOXMLSwift/IO/WhitespaceOverlay.swift (new internal type for sub-stack B)
    - packages/ooxml-swift/Tests/OOXMLSwiftTests/Issue58_60ContentPreservationTests.swift (matrix-pin + per-sub-stack tests)
  - Removed: (none)
