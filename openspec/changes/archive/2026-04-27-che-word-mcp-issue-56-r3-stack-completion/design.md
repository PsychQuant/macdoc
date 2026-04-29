## Context

`PsychQuant/che-word-mcp` issue 56 ("lossless `.docx` round-trip") has gone through three verification rounds. Round 2 (v3.13.2) verified 8 P0 + 5 P1 found in round 1. Round 3 (v3.13.3) verified the R2 fixes themselves and found **6 new P0 regressions caused by the R2 fixes**. The shared anti-pattern across all 6: each R2 fix solved "does X get emitted at all?" (the absence problem) but introduced one of two failure modes:

1. **Mutation desync**: A new representation was added (`children: [HyperlinkChild]`, `unrecognizedChildren` for revision wrappers) but existing mutation paths kept writing to the old representation, so source-loaded edits silently no-op'd.
2. **Order corruption**: Legacy collections were re-emitted in the sort path without a `position` field, so they always landed at the end of the paragraph instead of their source position.

This is the third attempt at closing #56. Continuing the bundle-of-fixes pattern (release v3.13.4 with all six fixes at once) has a high prior of producing a Round 4 with N more regressions. The design choice for this change is: **break the bundle**. Each of the 6 P0 fixes ships as an independent task with its own failing test, its own commit, and its own micro-verify pass before the next one starts. The R3 verification engine (`/idd-verify`) re-runs after each task instead of once at the end.

Stakeholders:

- `che-word-mcp` consumers (Claude Code MCP users) — currently exposed to silent data loss on `replace_text` / `update_hyperlink` / `insert_comment` against any source-loaded `.docx`.
- `ooxml-swift` downstream packages (`word-to-md-swift`, `word-builder-swift`) — depend on round-trip semantics being deterministic.
- Future #56-style verifications — this design establishes the precedent for cycle-breaking on deep P0 stacks.

## Goals / Non-Goals

**Goals:**

- Close #56 with zero new P0 regressions in Round 4.
- Each of the 6 P0 has an independent acceptance test that fails BEFORE the fix and passes AFTER.
- Verify after every task, not after the bundle, so a regression in task K is caught before tasks K+1...N start.
- Restore the `replace_text` / `update_hyperlink` / `insert_comment` mutation contract for source-loaded documents.
- Restore source-position fidelity for paragraph-level `<w:sdt>`.
- Restore typed `Revision` model coverage for mixed-content wrappers.
- Widen `nextBookmarkId` calibration to all bookmark-bearing locations (tables, headers, footers, footnotes, endnotes, block-level SDT children).
- Eliminate the XML-injection sink at `RunProperties.rStyle` emit.
- Add release-notes warning for the breaking `Hyperlink.id` format change introduced in P1-7.

**Non-Goals:**

- Architectural refactor of the `HyperlinkChild` / `unrecognizedChildren` / `commentRangeMarkers.isEmpty` patterns. We are only adding the missing sync paths, not re-designing the shape.
- Generalized XML escaping audit beyond `rStyle`. The audit of `color` / `fontName` / similar pre-existing direct-emit sites is acknowledged but follow-up.
- Backwards-compatibility shim for the `Hyperlink.id` format change. The change-notes warning is the chosen mitigation; no alias.
- The deferred P2 / P3 items from R3 (D-2, D-4, D-5, D-6, D-7, R-P3-1) — they remain in the issue body for a future change.
- Performance optimization. Some fixes (recursive `nextBookmarkId` scan, sync-on-mutate for hyperlinks) trade a small amount of CPU for correctness.

## Decisions

### Decision: Demote `children` priority in `Hyperlink` writer instead of syncing mutators

**Choice (refined during apply):** The writer compares the run-text derived from `children` against the run-text in `runs`. If they match, no mutation occurred → walk `children` to preserve source-document order between runs and non-run children (R2 P0-3 semantics). If they differ, an API mutation (`Hyperlink.text` setter / `replaceText` / `updateHyperlink`) has touched `runs` → walk `runs` so the mutation is visible on save. Pure "demote `children` priority" was rejected during apply because it regressed `testHyperlinkChildOrderPreservedAcrossRunAndNonRunChildren` (passive round-trip with mixed children flipped from A→SDT→B to A→B→SDT).

**Why this over syncing mutators:** Codebase audit during apply found only **2 mutation sites** (`Document.replaceInParagraphSurfaces` for hyperlink runs and `Hyperlink.text` setter, which `Document.updateHyperlink` calls through). The "5+ touch points, future fragility" concern motivating the original demote-priority decision was based on an over-estimate. However, even with only 2 sites today, comparing run-text in the writer centralizes the rule at one location and is robust against new editors added in the future.

**Alternatives considered:**

- **Pure demote-priority** (`if !runs.isEmpty use runs else children`): Rejected — regresses R2 P0-3 source-order semantics on passive read→write round-trip with mixed `children`. Tested empirically during apply and confirmed.
- **Sync all mutators** (`Hyperlink.text` setter and `replaceInParagraphSurfaces` clear `children`): Workable since only 2 sites exist, but moves the safety guarantee to call sites where it can decay. Rejected in favor of writer-side detection.
- **Drop `children` entirely**: Loses ordered-children fidelity for source-loaded hyperlinks that have non-run XML in between runs. The R2 P0-3 fix exists precisely to preserve this order. Rejected.
- **Make `children` a computed property over `runs` + `rawChildren`**: Loses position information for runs interspersed with raw XML. Rejected.

**Trade-off:** Source-loaded hyperlinks with mixed run + non-run children whose run text is mutated via the API lose the relative position of the non-run children against the new run text (writer falls through to runs+rawChildren on detected mutation). This is acceptable because (a) such mutations are extremely rare in real .docx files, (b) the R3 evidence shows the silent-edit bug affects every source-loaded hyperlink text edit today, which is a much broader blast radius. Mutations to non-text properties of runs (bold, color) without text change are NOT detected as mutations and continue to walk `children`; if a future need arises to detect property-only mutations, extend the comparison to include run properties.

### Decision: Add `position: Int` to `ContentControl` and route `<w:sdt>` through positioned-entry sort

**Choice:** Add a `position: Int` field to `ContentControl` (initial value 0), have `DocxReader.parseParagraph` pass `childPosition` when constructing the `ContentControl`, and update `Paragraph.toXMLSortedByPosition` to include `<w:sdt>` in the merged positioned-entry list (alongside runs, hyperlinks, bookmarks, etc.).

**Why:** The existing `ooxml-paragraph-child-schema-coverage` spec already requires every `<w:p>` child to have a `position` field and be emitted in source order. `ContentControl` was the only positioned-paragraph child without it. The R3-NEW-2 finding is fundamentally a violation of the existing spec — this fix brings `ContentControl` into compliance with the spec rather than introducing a new pattern.

**Alternatives considered:**

- **Emit `contentControls` post-content but track relative position to other post-content entries**: Adds a second ordering system. Rejected — single positioned-entry sort is the established pattern.
- **Wrap `<w:sdt>` in `unrecognizedChildren` raw capture**: Loses MCP tool access (`list_content_controls`, `update_content_control_text`). Rejected.

### Decision: New `insertCommentSyncingMarkers` helper symmetric to `appendBookmarkSyncingMarkers`

**Choice:** Add a new `Document.insertCommentSyncingMarkers(text: String, paragraph: Paragraph)` helper that, when the target paragraph already has source-loaded `commentRangeMarkers`, also appends the corresponding `<w:commentRangeStart>` / `<w:commentRangeEnd>` / `<w:commentReference>` raw markers using the new commentId. The existing `Document.insertComment` SHALL delegate to this helper.

**Why:** The R2 fix for P0-5 added a `commentRangeMarkers.isEmpty` guard to avoid double-emit, but the symmetric `appendBookmarkSyncingMarkers` solution from P1-4 was not applied to comments. This is a parallel bug with a parallel solution — same shape as the bookmark fix, just for the comment surface.

**Alternatives considered:**

- **Remove the `commentRangeMarkers.isEmpty` guard**: Reintroduces the double-emit P0 from R2. Rejected.
- **Have `insertComment` mutate the existing markers**: Confuses "insert new comment" with "modify existing comment range". Rejected.

### Decision: P0-7 raw capture also populates typed `Revision` model

**Choice:** When `DocxReader` captures a mixed-content revision wrapper into `paragraph.unrecognizedChildren` (R2 P0-7 path), it SHALL ALSO append a `Revision` entry to `paragraph.revisions`. The raw XML drives byte-equivalent emit; the typed entry drives MCP tooling visibility.

**Why:** R2 P0-7's `break` after `unrecognizedChildren.append` skipped the `paragraph.revisions.append` call, so MCP tools (`get_revisions` / `accept_revision` / etc.) couldn't see the wrapper. The user-visible bug: clicking "accept all revisions" in Word leaves these wrappers behind because the MCP server doesn't know they exist. Both representations need to coexist — one for byte-fidelity emit, one for tool-API visibility.

**Trade-off:** When MCP `accept_revision` is called for a captured wrapper, it can mark `paragraph.revisions[i]` as accepted but the raw XML in `unrecognizedChildren` is still emitted verbatim. Resolution: an `accept_revision` call on a raw-captured wrapper SHALL strip the `<w:ins>` / `<w:del>` outer wrapper from the corresponding `unrecognizedChildren` entry. This keeps both surfaces in sync.

### Decision: Recursive `nextBookmarkId` calibration across all bookmark-bearing parts

**Choice:** Replace the current top-level `body.children.compactMap { $0.case == .paragraph }` scan with a recursive walker that visits paragraphs in body, table cells (any nesting depth), block-level `<w:sdt>` children, headers, footers, footnotes, and endnotes — collecting the max bookmark ID across all of them.

**Why:** Bookmarks frequently land in tables (cross-references in academic documents) and headers/footers (page-anchored bookmarks). The R2 P1-1 fix only covered the simplest case. R3-NEW-5 upgrades this to P0 because any document with a table-bookmark causes the calibration to false-succeed (max from body is < real max), which triggers ID collision on the next `insert_bookmark` call.

**Trade-off:** The recursive scan is O(N) over all paragraphs vs O(N_body) before. For a typical 50-page academic .docx with tables, this is microseconds difference and negligible vs the parse cost.

### Decision: `escapeXML` at every direct attribute emit site, starting with `rStyle`

**Choice:** Introduce a `RunProperties` private helper `escapeXMLAttribute(_ value: String) -> String` and route the rStyle emit through it (`"<w:rStyle w:val=\"\(escapeXMLAttribute(rStyle))\"/>"`). Audit color / fontName / fontSize / etc. for the same direct-emit pattern and apply the helper. Document the audit results in `Issue56R3StackTests.swift`.

**Why:** R3-NEW-6 identifies an XML-injection sink: the rStyle value flows from source `XMLElement.attribute.stringValue` (auto-unescaped) through to `String` interpolation in toXML (no re-escape). A malicious source `<w:rStyle w:val='x"/><injected/><w:dummy w:val="y'/>` round-trips as additional sibling elements. The same anti-pattern likely exists in the other direct-emit sites — fix in batch to avoid leaving partial coverage.

**Alternatives considered:**

- **Use `XMLElement` API to construct the element**: Heavy-weight refactor for one-line emit sites. Defer to a future change.
- **Validate at parse time**: Doesn't help round-trip — escaped quotes auto-unescape and we still emit raw.

### Decision: Per-task verify gate, not bundle verify

**Choice:** After each P0 task completes (its test passes + a manual smoke check), run `/idd-verify #56` in scoped mode focusing only on that fix's regression surface. Do NOT proceed to the next task until verify is clean for the current task. This breaks the R2 → R3 chain where bundling 8 fixes hid the fact that fix-K introduced regression-K+1.

**Why:** The R3 evidence is conclusive: 4 of 4 R2 fix batches introduced new P0s. Bundle-emit verifies once at the end and catches the sum of regressions; per-task verify catches each as it lands, when the cause is unambiguous.

**Trade-off:** 6× more verify rounds. Each round is ~5 minutes (Codex + 5 Claude reviewers in parallel). Total cost: ~30 minutes additional, vs ~6+ hours of R3-style debugging when bundle verification catches a regression and we have to bisect to find the cause.

## Risks / Trade-offs

- **[Risk]** Demoting `children` priority means source-loaded hyperlinks with mixed run + non-run XML lose their non-run children's relative position after API mutation. → Mitigation: detect this case in `update_hyperlink`/`replace_text`, log a warning, document in CHANGELOG. Real-world incidence is low (we have no example in the test fixture corpus).
- **[Risk]** Adding `position` to `ContentControl` breaks any consumer that constructs `ContentControl(...)` positionally. → Mitigation: `position` defaults to 0 in the initializer, so call sites that don't care don't break.
- **[Risk]** `accept_revision` on a raw-captured wrapper has a non-obvious "strip wrapper from unrecognizedChildren" side-effect. → Mitigation: document in `accept_revision` docstring and in the `docx-revision-parsing` spec scenario.
- **[Risk]** Recursive `nextBookmarkId` scan has higher-than-expected cost on documents with deeply-nested tables or many SDT blocks. → Mitigation: benchmark on the existing builder fixture (34-namespace document); if regression > 5ms add a fast-path that short-circuits when no bookmarks exist.
- **[Risk]** XML escape helper applied non-uniformly (rStyle escaped but color not) leaves a half-fix that confuses future readers. → Mitigation: the audit task explicitly enumerates every direct-emit attribute site and either escapes or documents why escape is unnecessary.
- **[Risk]** Per-task verify gate slows down throughput. → Mitigation: the cost is small relative to the cost of debugging regressions found in bundle verify (R3 took 30+ minutes to author six regression reports).
- **[Trade-off]** This change does NOT alias the v0.19.3 `Hyperlink.id` format `rId5@7`. Callers that stored old `rId5` IDs and look them up after upgrade get nil. Acceptable because v0.19.3 is < 7 days old at write time; almost no production storage exists.

## Migration Plan

1. **Pre-flight**: Confirm no in-flight changes touching `Hyperlink.swift`, `Document.swift`, `Paragraph.swift`, `Field.swift`, `Run.swift`, or `DocxReader.swift` are open in other branches. Coordinate on `#56` umbrella.
2. **Per-task loop** (6× iterations, one per P0):
   - Write failing acceptance test in `Issue56R3StackTests.swift`.
   - Confirm test fails on `main`.
   - Implement fix in the smallest scope possible.
   - Confirm test passes.
   - Run full `swift test` for `ooxml-swift` and `che-word-mcp`. Confirm 570 + 172 baseline.
   - Run scoped `/idd-verify #56` focusing on the current fix's surface.
   - Commit with message `fix(#56-r3-NEW-K): <description>`.
3. **P1 follow-ups** (D-3, D-8) batched in one commit at the end.
4. **Release**: Tag `ooxml-swift` `v0.19.4`, bump `che-word-mcp` Package.swift to `v0.19.4`, tag `che-word-mcp` `v3.13.4`. Update CHANGELOGs.
5. **Marketplace sync**: `/plugin-tools:plugin-update che-word-mcp` to bump `psychquant-claude-plugins` marketplace entry.
6. **Final verify**: Full `/idd-verify #56` (Agent Team + Codex). Expect zero P0 findings. If clean, `/issue-driven-dev:idd-close #56`.
7. **Rollback**: If R4 finds new P0, do NOT bundle a v3.13.5 hot-fix. Open R5 stack-completion change with the R4 findings, and apply the same per-task discipline.

## Open Questions

- Should the `accept_revision` strip-wrapper-from-`unrecognizedChildren` side-effect be documented as a separate `docx-revision-parsing` requirement, or as a scenario under the existing `accept_revision` requirement in `che-word-mcp-tracked-changes-tools`? Resolution at specs-writing time.
- For the rStyle XML-escape audit: should we ship the audit results as a markdown table in `Issue56R3StackTests.swift` comment block, or as a separate `docs/security/xml-escape-audit.md`? Defer to apply-time judgment.
