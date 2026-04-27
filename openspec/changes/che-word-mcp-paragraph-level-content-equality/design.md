## Context

Sub-stack C (#60, archived 2026-04-27 as `che-word-mcp-issue-58-59-60-document-content-preservation`) extended the `RunProperties` typed + raw architecture for run-level `<w:r><w:rPr>` and ratcheted the cross-cutting matrix-pin `testDocumentContentEqualityInvariant`. That ratchet exposed two pre-existing paragraph-level drops that fall **outside** #60's scope but are the next-largest contributors to the remaining 16.66% byte loss in the NTPU thesis fixture round-trip:

1. `<w:pPr><w:rPr>` — paragraph-mark formatting that controls the pilcrow ¶ glyph (font, size, color, language, kerning) is silently dropped in `parseParagraphProperties` (DocxReader.swift:1297). Accounts for ~50% of the residual `<w:lang>` loss.
2. `<w:p w14:paraId="..." w14:textId="...">` — Word's revision-tracking GUIDs that anchor paragraph identity for collaborative editing and comment threading are silently dropped in `parseParagraph` (DocxReader.swift:818). Accounts for ~95% of residual w14:* token loss (2214 of 2359 lost tokens).

Bringing both into the `if not typed, preserve as raw` architecture established by sub-stacks A/B/C is the prerequisite for the `docs/structural-editing-paradigm.md` §6.1 strong claim「edit 一個字 → document.xml shrinks <1%」moving from "deferred" to live.

Stakeholders: same as sub-stack C — ooxml-swift maintainer (Che Cheng), che-word-mcp downstream consumers, future MCP plugin marketplace users; no external API contract surface affected.

## Goals / Non-Goals

**Goals:**

- Extend modified-parts content-equality from run-level (already covered by sub-stack C) to **full paragraph + run scope** for `document.xml`
- Bring round-trip `document.xml` byte loss from 16.66% to ≤ 5% on the thesis fixture
- Ratchet matrix-pin `testDocumentContentEqualityInvariant` floors so any future paragraph-mark-rPr or paragraph-w14 regression fails CI
- Ship as two separate ooxml-swift + che-word-mcp release pairs (D before E), each with marketplace sync, mirroring the proven cadence from sub-stacks A → B → C

**Non-Goals:**

- Codex P1 cluster from sub-stack C verify (schema-order rawChildren tail-append, characterSpacing/textEffect parser-side gap, static `recognizedRprChildren` Set perf, ratio-floor maintenance burden) — separate follow-up SDD
- Other open che-word-mcp issues (#16, #61, #62, #63) — separate execution per the batch triage report on #65
- Style-level paragraph-mark rPr in `styles.xml` (where `Style.runProperties` already exists). This change scopes to per-paragraph mark formatting in `document.xml` only
- Strict ECMA-376 §17.3.1.27 schema-validator child-ordering compatibility for nested `<w:rPr>` inside `<w:pPr>` — the same deferred concern as sub-stack C; Word's leniency is sufficient for the use case
- Other w14:* paragraph attributes (`w14:smtClean`, `w14:checksum`) — not present in real-world fixtures we round-trip
- Changing `Paragraph` API surface beyond the two new optional fields — backward compatibility preserved

## Decisions

### Reuse parseRunProperties verbatim for paragraph-mark rPr

Sub-stack D adds `markRunProperties: RunProperties?` to `ParagraphProperties` and extends `parseParagraphProperties` (DocxReader.swift:1297) to look up `<w:pPr><w:rPr>` and call the existing `parseRunProperties(from:)` helper. This is intentional zero-duplication: `<w:rPr>` inside `<w:pPr>` uses the IDENTICAL CT_RPr schema as a regular run-level `<w:rPr>` per ECMA-376 §17.3.1.27, so all the typed extraction (4-axis rFonts, noProof, kern, 3-axis lang) and raw passthrough (rawChildren for w14:*) come for free.

**Alternatives considered:**

- *Inline reimplementation in parseParagraphProperties* — rejected. Two separate code paths for the same schema means future RunProperties extensions (e.g., when Codex P1 widens `recognizedRprChildren`) must be remembered in two places. The matrix-pin would catch divergence eventually but at the cost of a regression cycle.
- *Sharing via a CT_RPr-only protocol* — rejected. parseRunProperties already takes an `XMLElement` and returns `RunProperties`; calling it directly is the simplest reuse. A protocol layer would be premature abstraction for the only two call sites.

### Plain attribute passthrough for w14:paraId / w14:textId

Sub-stack E adds `w14ParaId: String?` and `w14TextId: String?` to `Paragraph` (typed as `String?`, not `UUID`). The values are 8-character hex GUIDs Word generates and refers to — we treat them as opaque tokens that round-trip byte-for-byte. parseParagraph extracts via the same XMLElement attribute lookup pattern already used for `w:rsidR` and friends.

**Alternatives considered:**

- *Typed UUID field* — rejected. Word's GUIDs are 8 hex chars (32 bits truncated), not RFC 4122 UUIDs. Parsing as UUID would fail or require synthetic padding, defeating the round-trip goal. String passthrough is correct.
- *Single struct `W14ParagraphIdentity { paraId, textId }`* — rejected. Both attributes are independent (Word can emit either alone), so two separate optionals match the actual data. A struct would force them to be set together.
- *Generic `w14Attributes: [String: String]`* — rejected. Only paraId/textId appear in real fixtures; a typed pair is more discoverable and avoids the question of how to round-trip unknown w14:* attributes (handled separately by rawElements at the element level if needed).

### Ship D and E as separate releases (D first)

Sub-stack D ships as ooxml-swift v0.20.2 + che-word-mcp v3.14.2 + marketplace sync, then sub-stack E ships as v0.20.3 + v3.14.3 + sync. Each ship runs through its own per-sub-stack 6-AI verify gate (R1 + R2 + R5 + Codex) before tagging.

**Alternatives considered:**

- *Single combined ship* — rejected. Two architecturally distinct sub-stacks (one extends typed+raw, one is plain attribute passthrough) sharing one matrix-pin ratchet would conflate "lang preservation" credit with "w14 preservation" credit, making regression triage harder. Separate ships preserve sub-stack isolation that has worked through #58/#59/#60.
- *D + E in one matrix-pin ratchet but two implementation commits* — rejected for the same reason. The matrix-pin is the audit trail; conflating ratchets blurs which sub-stack moved which floor.

### Matrix-pin floor ratchet schedule

After D lands: `<w:lang ` floor 0.45 → ~0.95; `sizeLossRatio` ceiling 0.175 → ~0.10. After E lands: `w14:` floor 0.04 → ~0.95; `sizeLossRatio` ceiling ~0.10 → ~0.05.

Each ratchet is an explicit XCTAssert tightening in `Issue58_60ContentPreservationTests.swift` §3.9 / §3.11, committed in the same ship as the implementation. Floors are derived from the actual measured retention ratio on the thesis fixture rounded down to the nearest 0.05 (matches the discipline established in sub-stack C).

### Emission position of nested rPr inside pPr

Sub-stack D emits `<w:rPr>` after the typed `<w:pPr>` children (pStyle, jc, spacing, ind, numPr, etc.) and before closing `</w:pPr>`. Word tolerates this position. Strict ECMA-376 §17.3.1.27 compliance is deferred (same as sub-stack C — see Non-Goals).

## Risks / Trade-offs

- **[Word rejects pPr with rPr in non-canonical child position]** → Mitigation: pre-flight test on Word for Mac + Word for Windows during sub-stack D verify gate; `recognizedPprChildren` Set discipline lesson from sub-stack C is already internalized — emit only what we typed-extract or raw-passthrough.

- **[w14:paraId namespace declaration missing in writer output]** → Mitigation: thesis fixture's `<w:document>` opening tag already declares `xmlns:w14="..."` (Word emits it on every `.docx`). DocxWriter preserves opening-tag verbatim, so namespace is implicit. Test fixture for sub-stack E SHALL include a w14-namespace-declared document to confirm.

- **[ratio-floor maintenance burden compounds]** → Mitigation: sub-stack C already absorbed 5 ratio-floor assertions. Two more (lang ratchet + w14 ratchet) brings total to 7 — acceptable; matrix-pin is the architectural payoff that justifies the discipline. If maintenance becomes painful, separate follow-up SDD addresses Codex P1 floor-derivation refactor.

- **[Per-sub-stack 6-AI verify timeout risk]** → Mitigation: smaller scope than C-CONT means each verify is shorter. If a verify times out (as happened in sub-stack B-CONT-2-CONT R5/Codex), accept 2-of-4 convergence per the precedent established there — methodology lesson from #59 still applies.

- **[Test fixture fragility]** → Mitigation: payload-parity tests (assert actual `<w:lang>`/w14:paraId content survives, not just count) per sub-stack C verify-gate methodology. Counter-parity-only tests are insufficient because pathological writers can emit `<w:lang/>` with empty content and pass count-parity while losing content.

## Migration Plan

Each sub-stack ships standalone:

**Sub-stack D**: bump ooxml-swift Package.swift to v0.20.2 → tag → release → push. Bump mcp/che-word-mcp Package.swift dep to v0.20.2, bump version to v3.14.2, regenerate mcpb manifest, tag, release with mcpb + raw binary assets. Run `/plugin-update che-word-mcp` to sync `psychquant-claude-plugins` marketplace.json + plugin.json + README.

**Sub-stack E**: same pattern, v0.20.3 + v3.14.3.

**Rollback**: each ship is an independent commit on main. Revert by tagging an .x patch that drops the new field's parse path while keeping the model field (preserves API). The model field stays optional (`String?` / `RunProperties?`), so callers that never set them are unaffected.

Documentation update (`docs/structural-editing-paradigm.md`) lands in a separate commit AFTER both sub-stacks ship and matrix-pin sizeLossRatio reaches ≤ 0.05. Reverting the doc update is independent of code rollback.

## Open Questions

- **Should `markRunProperties` mirror `Run.runProperties` getter naming, or be a distinct field name to signal "this is the pilcrow ¶ rPr, not the run rPr"?** Resolution path: pick `markRunProperties` (current proposal) — explicit naming wins over symmetry; future readers grepping for "mark" will find both this field and the OOXML spec's "paragraph mark" terminology.

- **Does any consumer in the macdoc monorepo currently read `ParagraphProperties` directly and would break on a new optional field?** Resolution path: grep + compile check during sub-stack D implementation; new optional field is API-additive, default `nil` matches pre-fix behavior, so consumers that ignore it continue working.

- **Should the matrix-pin ratchet land in the same commit as the implementation, or in a follow-up commit after measuring actual retention?** Resolution path: same commit. The ratchet IS the verification; separating would create a window where a regression slips through. Sub-stack C established this pattern.
