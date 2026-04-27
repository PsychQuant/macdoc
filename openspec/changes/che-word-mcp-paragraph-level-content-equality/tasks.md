## 1. Setup

- [x] 1.1 [P] Verify ooxml-swift main branch is clean and at v0.20.1 (post-sub-stack-C-CONT baseline) by running `git log --oneline -5` and confirming `Package.swift` references match
- [x] 1.2 [P] Read archived sub-stack C delta (`openspec/changes/archive/2026-04-27-che-word-mcp-issue-58-59-60-document-content-preservation/`) to internalize the typed + raw + matrix-pin pattern that sub-stack D and E must mirror
- [x] 1.3 Confirm `Issue58_60ContentPreservationTests.swift` matrix-pin §3.9 / §3.11 passes with current floors (`<w:lang ` 0.45, `w14:` 0.04, `sizeLossRatio` 0.175) before any changes — this is the baseline both sub-stacks ratchet from

## 2. Sub-stack D — paragraph-mark rPr (#65)

Implements: **ParagraphProperties SHALL preserve paragraph-mark RunProperties through round-trip**.
Decision reference: **Reuse parseRunProperties verbatim for paragraph-mark rPr** + **Emission position of nested rPr inside pPr**.

### 2.1 Model + parser

- [x] 2.1.1 Add `markRunProperties: RunProperties?` field to `ParagraphProperties` in `packages/ooxml-swift/Sources/OOXMLSwift/Models/Paragraph.swift` — backbone of "ParagraphProperties SHALL preserve paragraph-mark RunProperties through round-trip"; preserves backward compatibility (optional, default nil)
- [x] 2.1.2 Extend `parseParagraphProperties` (DocxReader.swift:1297) to look up the `<w:rPr>` direct child of `<w:pPr>` and call existing `parseRunProperties(from:)` to populate `markRunProperties` — zero schema duplication, all sub-stack C typed + raw passthrough comes for free
- [x] 2.1.3 Extend `ParagraphProperties.toXML()` to emit `<w:rPr>...</w:rPr>` inside `<w:pPr>` after the typed pPr children (pStyle, jc, spacing, ind, numPr) and before closing `</w:pPr>`, only when `markRunProperties` is non-nil

### 2.2 Tests (TDD: write RED first, then implement, then GREEN)

- [x] 2.2.1 Add payload-parity test `testParagraphMarkRunPropertiesPreservedThroughRoundtrip` to `Issue58_60ContentPreservationTests.swift` asserting `<w:lang>` actual content (val/eastAsia/bidi) survives — not just count parity
- [x] 2.2.2 Add fixture-based test for paragraph-mark rPr 4-axis `<w:rFonts>` round-trip (mirrors sub-stack C scenario for run-level rFonts)
- [x] 2.2.3 Add fixture-based test for paragraph-mark rPr `<w14:textOutline>` raw-children passthrough — proves the rawChildren path covers w14:* effects in the pPr context, not just rPr context
- [x] 2.2.4 Add negative test: paragraph WITHOUT `<w:pPr><w:rPr>` SHALL NOT emit empty `<w:rPr/>` in output (markRunProperties=nil → no emission)

### 2.3 Matrix-pin ratchet (sub-stack D portion)

- [x] 2.3.1 Ratchet matrix-pin `<w:lang ` floor in `Issue58_60ContentPreservationTests.swift` §3.9 from 0.45 → 0.95 (sub-stack of "testDocumentContentEqualityInvariant matrix-pin SHALL ratchet paragraph-level preservation floors")
- [x] 2.3.2 Ratchet `sizeLossRatio` ceiling from 0.175 → 0.10 in same file §3.11 (intermediate; sub-stack E will further lower to 0.05)
- [x] 2.3.3 Run full ooxml-swift test suite locally; expect 682 → 686 tests pass (4 new tests from §2.2)

### 2.4 Sub-stack D 6-AI verify gate

- [x] 2.4.1 Run R1 Requirements review against this proposal + delta specs; convergence criterion = no P0/P1 findings on requirements coverage
- [x] 2.4.2 Run R2 Logic review against the implementation diff (Paragraph.swift + DocxReader.swift); convergence criterion = no P0 logic findings
- [x] 2.4.3 Run R5 Devil's Advocate review predicting failure modes; convergence criterion = predicted modes either covered by tests in §2.2 or explicitly accepted in design.md Risks
- [x] 2.4.4 Run Codex methodology cross-check; convergence criterion = ≥ 3-of-4 reviewers PASS (precedent from sub-stack B-CONT-2-CONT allows 2-of-4 if R5/Codex time out)

### 2.5 Sub-stack D ship

Decision reference: **Ship D and E as separate releases (D first)** + **Matrix-pin floor ratchet schedule**.

- [x] 2.5.1 Bump `packages/ooxml-swift/Package.swift` swift-tools-version comment block to v0.20.2; update CHANGELOG.md with sub-stack D entry
- [x] 2.5.2 Commit ooxml-swift changes with message referencing #65 and sub-stack D, push to main, tag `v0.20.2`, create GitHub release
- [x] 2.5.3 Bump `mcp/che-word-mcp/Package.swift` ooxml-swift dep to `from: "0.20.2"`; bump che-word-mcp version to `v3.14.2` in plugin.json + manifest.json + CHANGELOG.md
- [x] 2.5.4 Build che-word-mcp release binary; commit, push, tag `v3.14.2`, create GitHub release with mcpb + raw binary assets
- [x] 2.5.5 Run `/plugin-update che-word-mcp` to sync `psychquant-claude-plugins` marketplace.json + plugin.json + README narrative

## 3. Sub-stack E — paragraph w14 attributes (#66)

Implements: **Paragraph SHALL preserve w14:paraId and w14:textId attributes through round-trip** + **DocxReader SHALL extract w14:paraId and w14:textId attributes from body paragraphs**.
Decision reference: **Plain attribute passthrough for w14:paraId / w14:textId**.

### 3.1 Model + parser

- [x] 3.1.1 Add `w14ParaId: String?` and `w14TextId: String?` fields to `Paragraph` in `packages/ooxml-swift/Sources/OOXMLSwift/Models/Paragraph.swift` — backbone of "Paragraph SHALL preserve w14:paraId and w14:textId attributes through round-trip"; typed as String (not UUID) since Word's GUIDs are 8-char hex tokens, not RFC 4122
- [x] 3.1.2 Extend `parseParagraph` (DocxReader.swift:818) to extract both attributes from the `<w:p>` opening tag using the same XMLElement attribute lookup pattern already used for `w:rsidR` and friends — fulfills "DocxReader SHALL extract w14:paraId and w14:textId attributes from body paragraphs"
- [x] 3.1.3 Extend `Paragraph.toXML()` to emit `w14:paraId="..."` and `w14:textId="..."` attributes on the `<w:p>` opening tag when each field is non-nil

### 3.2 Tests (TDD: write RED first)

- [x] 3.2.1 Add payload-parity test `testParagraphW14AttributesPreservedThroughRoundtrip` asserting both attributes' actual values survive
- [x] 3.2.2 Add asymmetric test: paragraph with only `w14:paraId` (no `w14:textId`) round-trips with paraId preserved and textId absent
- [x] 3.2.3 Add negative test: paragraph WITHOUT w14:* attributes SHALL NOT emit empty/synthetic attributes
- [x] 3.2.4 Add header-paragraph extraction test confirming uniform application across body parts (header/footer/footnote/endnote share parseParagraph code path)

### 3.3 Matrix-pin ratchet (sub-stack E portion)

- [x] 3.3.1 Ratchet matrix-pin `w14:` floor in `Issue58_60ContentPreservationTests.swift` from 0.04 → 0.95 (continues "testDocumentContentEqualityInvariant matrix-pin SHALL ratchet paragraph-level preservation floors")
- [x] 3.3.2 Ratchet `sizeLossRatio` ceiling from 0.10 → 0.05 — final architectural target for the change
- [x] 3.3.3 Run full test suite; expect 686 → 690 pass (4 new tests from §3.2)

### 3.4 Sub-stack E 6-AI verify gate

- [x] 3.4.1 Run R1 Requirements review on sub-stack E delta + tests
- [x] 3.4.2 Run R2 Logic review on Paragraph.swift + DocxReader.swift attribute extraction diff; pay attention to w14: namespace declaration assumptions
- [x] 3.4.3 Run R5 Devil's Advocate predicting failure modes (e.g., what if w14:paraId is empty string; what if textId appears without paraId)
- [x] 3.4.4 Run Codex methodology check; convergence ≥ 3-of-4 PASS

### 3.5 Sub-stack E ship

- [x] 3.5.1 Bump ooxml-swift to v0.20.3; update CHANGELOG.md with sub-stack E entry
- [x] 3.5.2 Commit, push, tag `v0.20.3`, GitHub release
- [x] 3.5.3 Bump che-word-mcp dep to `from: "0.20.3"`; bump version to `v3.14.3` across plugin.json + manifest.json + CHANGELOG.md
- [x] 3.5.4 Build, commit, push, tag `v3.14.3`, GitHub release with assets
- [x] 3.5.5 Run `/plugin-update che-word-mcp` to sync marketplace

## 4. Documentation update (post-both-sub-stacks)

- [ ] 4.1 Update `docs/structural-editing-paradigm.md` §3.1 to record new sizeLossRatio achievement (16.66% → ≤ 5%)
- [ ] 4.2 Promote §6.1「edit 一個字 → document.xml shrinks <1%」demo from "deferred" to live (caveat removed) once §3.5.5 marketplace sync confirms
- [ ] 4.3 Update §10 to list TWO invariants with paragraph-level coverage explicit (replaces sub-stack-C-era「partial run-level coverage」note)
- [ ] 4.4 Commit doc update separately on macdoc main with message linking to closed #65 and #66

## 5. Issue closure

- [ ] 5.1 Close che-word-mcp #65 via `idd-close` after sub-stack D ships and matrix-pin ratchet lands
- [ ] 5.2 Close che-word-mcp #66 via `idd-close` after sub-stack E ships and matrix-pin ratchet lands
- [ ] 5.3 Cross-link both closures back to this Spectra change archive directory once `/spectra-archive` runs
