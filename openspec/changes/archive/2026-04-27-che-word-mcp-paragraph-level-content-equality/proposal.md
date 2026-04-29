## Problem

Sub-stack C (#60, closed via ooxml-swift v0.20.1 / che-word-mcp v3.14.1, Spectra change `che-word-mcp-issue-58-59-60-document-content-preservation` archived 2026-04-27) extended the `RunProperties` typed + raw architecture for run-level `<w:r><w:rPr>...</w:rPr></w:r>`. The cross-cutting matrix-pin `testDocumentContentEqualityInvariant` revealed two pre-existing paragraph-level drops that fall OUTSIDE #60 scope but are now blocking the next round-trip-loss reduction:

1. **Paragraph-mark rPr (#65)**: `<w:pPr><w:rPr>...</w:rPr></w:pPr>` — formatting that controls the pilcrow ¶ glyph appearance (font, size, color, language tag, kerning) — silently dropped at parse time. `ParagraphProperties` has no `markRunProperties: RunProperties?` field; `parseParagraphProperties` (DocxReader.swift:1297) extracts `<w:pPr>` direct children but ignores nested `<w:rPr>`. Accounts for ~50% of remaining `<w:lang>` loss in NTPU thesis fixture.

2. **Paragraph w14 attributes (#66)**: `<w:p w14:paraId="0AB12345" w14:textId="01234567">` — Word's revision-tracking GUIDs that anchor paragraph identity across edits, comments, and collaborative editing — silently dropped. `Paragraph` model has no field for them; `parseParagraph` (DocxReader.swift:818) extracts paragraph-level metadata but ignores w14:* attributes on `<w:p>`. Accounts for ~95% of remaining w14:* token loss (2214 of 2359 lost tokens).

Combined impact on NTPU thesis fixture round-trip (`document.xml`):
- Pre-fix v0.19.x: 32% byte loss
- Post-sub-stack-C-CONT v0.20.1: 16.66% byte loss (improvement of 14.25 percentage points from typed + raw rPr extraction)
- **After this change (target)**: < 5% byte loss — enabling the `docs/structural-editing-paradigm.md` §6.1 strong claim「edit 一個字 → document.xml shrinks <1%」to ship

## Root Cause

Two distinct silent-drop paths discovered by the sub-stack C matrix-pin extension:

**Root cause #65**: `parseParagraphProperties` only extracts the typed `<w:pPr>` direct children it knows about (`<w:pStyle>`, `<w:jc>`, `<w:spacing>`, `<w:ind>`, `<w:numPr>`, etc.). The `<w:rPr>` direct child of `<w:pPr>` (which represents paragraph-mark formatting per ECMA-376 §17.3.1.27 CT_PPrBase) is silently ignored. There is no schema-level reason for this — the rPr inside pPr uses the IDENTICAL CT_RPr schema as a regular run-level `<w:rPr>`, meaning `parseRunProperties` (already extended in sub-stack C) can be reused verbatim.

**Root cause #66**: `parseParagraph` (DocxReader.swift:818) extracts attributes via discrete lookups for known w-namespace attributes but never iterates the w14: namespace. The `Paragraph` model has no field to store w14:paraId / w14:textId. Writer emits `<w:p>` opening tag without these attributes. Note: `parseComments` at DocxReader.swift:3165 already extracts `w14:paraId` from `<w:p>` inside `<w:comment>` for comment threading — proving the extraction is mechanically trivial; just never wired into the body parser.

Both root causes were uncovered by sub-stack C's matrix-pin extension `testDocumentContentEqualityInvariant` §3.9 with preservation-class-3 ratio-floor assertions. The matrix-pin caught these as out-of-scope drops requiring this follow-up SDD.

## Proposed Solution

Bundle both fixes into one Spectra change with two architecturally cohesive sub-stacks. Each sub-stack runs through its own per-task verify gate + 6-AI verify (matching the methodology that converged in #58/#59/#60).

### Sub-stack D — paragraph-mark rPr (#65)

Mirror sub-stack C's `RunProperties` typed + raw architecture at the paragraph level:

1. Add `markRunProperties: RunProperties?` field to `ParagraphProperties` (Paragraph.swift)
2. Extend `parseParagraphProperties` (DocxReader.swift:1297) to look up `<w:pPr><w:rPr>` direct child and call existing `parseRunProperties(from: rPr)` — direct reuse of sub-stack C's extraction (typed rFonts/noProof/kern/lang + rawChildren passthrough)
3. Extend `ParagraphProperties.toXML()` (Paragraph.swift) to emit `<w:rPr>...</w:rPr>` inside `<w:pPr>` at the appropriate ECMA-376 source-order position (after typed pPr children, before closing `</w:pPr>`)

### Sub-stack E — paragraph w14 attributes (#66)

Plain attribute passthrough for opaque GUIDs:

1. Add `w14ParaId: String?` and `w14TextId: String?` fields to `Paragraph` (Paragraph.swift)
2. Extend `parseParagraph` (DocxReader.swift:818) to extract both attributes from the `<w:p>` opening tag
3. Extend `Paragraph.toXML()` to emit both attributes on the `<w:p>` opening tag when set

### Cross-cutting matrix-pin extension

Each sub-stack ratchets matrix-pin floors as part of its verify gate (mirrors how #58/#59/#60 matrix-pin ratchets worked):

- Sub-stack D ratchets: `<w:lang ` floor 0.45 → ~0.95; size-loss ceiling 0.175 → ~0.10
- Sub-stack E ratchets: `w14:` floor 0.04 → ~0.95; combined with D, size-loss ceiling reaches ~0.05

After both sub-stacks land, the matrix-pin enforces the architectural goal: **modified parts content-equality across the FULL paragraph + run scope**.

### Methodology continuity

Each sub-stack ships independently as separate ooxml-swift release + che-word-mcp release + marketplace sync, following the proven pattern from #58/#59/#60. Per-sub-stack 6-AI verify gates expected to converge in 1 cycle each (smaller scope than C-CONT-style architectural extensions).

## Non-Goals

- **Codex P1s from sub-stack C verify** (schema-order rawChildren tail-append, characterSpacing/textEffect parser-side gap, static `recognizedRprChildren` Set perf, ratio-floor maintenance burden) — separate follow-up SDD; not in scope
- **Other open issues**: #61 (anchor parameter parity for insert_paragraph/insert_equation), #62 (caption-to-SEQ helper), #63 (replace_text bracket bug), #16 (PDF native image input) — separate execution per batch triage report on #65
- **Style-level paragraph-mark rPr**: this change extends `ParagraphProperties` for per-paragraph mark formatting in `document.xml`. Style-definition-level paragraph-mark rPr in `styles.xml` (where Style.runProperties already exists) is out of scope — would be a separate concern if styles.xml round-trip ever becomes load-bearing
- **Schema validation of `<w:rPr>` child ordering inside `<w:pPr>`**: ECMA-376 §17.3.1.27 has child-order constraints; sub-stack D emits in the simple "after typed pPr children" position which Word tolerates. Strict schema-validator compatibility for nested rPr is out of scope (same deferred concern as Codex P1 for sub-stack C)
- **Other paragraph attributes**: w14:paraId / w14:textId are the highest-impact paragraph attributes (revision tracking). Other w14:* paragraph attributes (e.g., w14:smtClean, w14:checksum) are not currently used in real-world fixtures; out of scope

## Success Criteria

Verifiable conditions after both sub-stacks land:

1. **Sub-stack D verification**: `<w:pPr><w:rPr>` round-trips byte-equivalent (or content-equivalent) for the thesis fixture. Specifically:
   - `<w:lang>` retention ratio ≥ 0.95 in matrix-pin (was 0.45 pre-fix)
   - New test `testParagraphMarkRunPropertiesPreservedThroughRoundtrip` (payload-parity, asserts actual `<w:lang>`/`<w:rFonts>`/`<w:noProof>` content survives)
   - Suite: 682 → 683/0/1

2. **Sub-stack E verification**: `<w:p>` w14:paraId / w14:textId round-trip preserved. Specifically:
   - `w14:` retention ratio ≥ 0.95 in matrix-pin (was 0.04 pre-fix)
   - New test `testParagraphW14AttributesPreservedThroughRoundtrip` (payload-parity, asserts both attributes survive)
   - Suite: 683 → 684/0/1

3. **Combined size-loss ceiling**: thesis fixture `document.xml` round-trip size loss ≤ 5% (was 16.66% post-sub-stack-C-CONT)
   - Matrix-pin floor `sizeLossRatio` 0.175 → 0.05

4. **Sub-stack regression**: prior sub-stack A/B/C closures intact through both sub-stacks (Document.swift / WhitespaceOverlay.swift / RunProperties unchanged in the implementation diffs)

5. **6-AI verify PASS** on each sub-stack ship cycle (1 cycle expected per sub-stack — smaller scope than #58/#59/#60 sub-cycles)

6. **Documentation**: `docs/structural-editing-paradigm.md` §3.1 / §6.1 / §10 updated to reflect the now-achievable < 5% loss claim. The 强版 demo「edit 一個字 → document.xml shrinks <1%」moves from "deferred" to live.

## Impact

- **Affected specs**:
  - `ooxml-roundtrip-fidelity` — adds 2 new SHALL clauses (paragraph-mark rPr round-trip, paragraph w14 attribute round-trip) + 2 new scenarios under existing matrix-pin requirement
  - `docx-container-parsing` — adds 1 new SHALL clause (paragraph-level attribute extraction includes w14:*)

- **Affected code**:
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Paragraph.swift` (add markRunProperties to ParagraphProperties + add w14ParaId/w14TextId to Paragraph; extend toXML for both)
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift` (extend parseParagraphProperties at line 1297 + parseParagraph at line 818)
  - Modified: `packages/ooxml-swift/Tests/OOXMLSwiftTests/Issue58_60ContentPreservationTests.swift` (add 2 new payload-parity tests + ratchet matrix-pin floors §3.9 / §3.11)
  - Modified: `packages/ooxml-swift/CHANGELOG.md` (add v0.20.2 + v0.20.3 entries — sub-stacks D + E)
  - Modified: `mcp/che-word-mcp/Package.swift` + `CHANGELOG.md` + `mcpb/manifest.json` (dep bumps for v3.14.2 + v3.14.3 ships)
  - Modified: `docs/structural-editing-paradigm.md` (§3.1 + §6.1 + §10 updates after both sub-stacks land)

- **Affected MCP plugin marketplace**: bumps `psychquant-claude-plugins` `marketplace.json` + `plugin.json` + README narrative for che-word-mcp v3.14.2 + v3.14.3 ships

- **Affected releases**:
  - ooxml-swift v0.20.2 (sub-stack D) + v0.20.3 (sub-stack E)
  - che-word-mcp v3.14.2 (sub-stack D) + v3.14.3 (sub-stack E)
  - All include mcpb + raw binary GitHub release assets

## Capabilities

### New Capabilities

(none — this change extends existing capabilities)

### Modified Capabilities

- `ooxml-roundtrip-fidelity`: extends modified-parts content-equality from run-level to paragraph-level
- `docx-container-parsing`: extends paragraph parser scope to include w14:* attributes
