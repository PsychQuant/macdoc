## Context

che-word-mcp v3.11.0 closes 6 of 7 P0 issues from Office.js OOXML Roadmap ([che-word-mcp#43](https://github.com/PsychQuant/che-word-mcp/issues/43)). The remaining P0 — [#45 §2 程式化產生 Track Changes 修訂標記](https://github.com/PsychQuant/che-word-mcp/issues/45) — fills a gap that blocks the highest-leverage MCP/AI use case: AI assistants making auditable redline edits to legal contracts, academic manuscripts, and collaborative documents.

Today's gap: read-side is complete (`enable_track_changes`, `accept_revision`, `reject_revision`, `get_revisions` all work), but mutation tools (`insert_text`, `replace_text`, `format_text`) silently rewrite without producing `<w:ins>` / `<w:del>` markup. So Word UI shows AI edits as if a user typed them — defeats Track Changes' core purpose.

After v3.11.0 the foundation is ready: `RevisionType` enum has all 6 cases, `Revision.toXML` correctly emits `<w:ins>` / `<w:del>` (with `<w:delText>` substitution), `Paragraph.revisions: [Revision]` is the attachment point. What's missing is the **WRITE-side wrapper layer**: WordDocument methods that wrap mutations with revision metadata, plus MCP tool surfaces that expose them.

Stakeholders: che-word-mcp users running AI assistants on legal docs (contract redline workflows), academic manuscripts (peer review-style edits), enterprise documents (proposal collaboration). Closing this also brings Office.js Roadmap P0 set to 100% completion.

## Goals / Non-Goals

**Goals:**

- 3 new MCP tools (`insert_text_as_revision` / `delete_text_as_revision` / `move_text_as_revision`) + 2 extended args (`format_text` / `set_paragraph_format` gain `as_revision: bool`) cover all 5 OOXML revision types in scope.
- ooxml-swift v0.18.0 delivers 6 new WordDocument methods (5 revision generators + 1 id allocator) using the same dirty-tracking discipline established in v0.16.0.
- Round-trip fidelity verified by 2 new test fixtures: contract redline (insert + delete + format change), document migration (multi-author multi-revision interleaving).
- All revision generators reject when `track_changes_not_enabled` — no auto-enable side effects per user requirement.

**Non-Goals:**

- Cross-paragraph delete (paragraph mark deletion via `<w:pPr><w:rPr><w:del/></w:rPr></w:pPr>`).
- Auto-wrap mutations on track-changes-enabled — explicit per-call opt-in only.
- Auto-enable track changes when `as_revision: true` — error instead.
- `<w:numberingChange>` revision type — deprecated in OOXML in favor of `<w:rPrChange>`.
- Bulk reject by author/date — separate SDD.
- Concurrent revision conflict resolution — last write wins, documented limitation.

## Decisions

### Revision id allocation reuses v0.15.0 SDT max+1 pattern

**Decision:** `WordDocument.allocateRevisionId() -> Int` scans `revisions.revisions` collection for max id across all sources (body, header, footer, footnote, endnote) and returns max+1. Returns 1 when no revisions exist.

**Rationale:** Identical pattern to `allocateSdtId` (shipped v0.15.0). Deterministic, debuggable, matches Word's own allocator behavior. Random ids have birthday-problem collision risk that grows with revision count. The scan is O(n) per call but n is bounded by total revisions in document (typically 10-100, max ~1000 even in heavily-edited docs).

**Alternatives considered:**

- *Random 6-digit ids:* same problem as the v0.15.0 SDT case — collision probability grows with edit count. Rejected by analogy.
- *Cache the next id on Document open, increment on each call:* faster (O(1)) but introduces stale-cache risk if other code paths add revisions. Rejected — not worth the complexity.
- *UUID strings:* OOXML `w:id` is integer per spec. Rejected.

### Default author resolves through 3-tier fallback chain

**Decision:** All 5 revision generators accept optional `author: String?` parameter. Resolution order: (1) explicit arg if non-nil and non-empty; (2) `revisions.settings.author` (set when `enable_track_changes(author:)` was called); (3) literal `"Unknown"`.

**Rationale:** Matches MCP/AI workflow — an agent typically calls `enable_track_changes(author: "Claude AI")` once at session start, then makes many revision-generating calls without re-passing the author each time. But explicit per-call override stays available for multi-author scenarios (e.g., consolidating reviews from multiple stakeholders).

**Alternatives considered:**

- *Required author on every call:* clean signature but ergonomically tedious for the common case. Rejected.
- *Default to `"Unknown"` only:* loses the author info that `enable_track_changes` already captured. Rejected as wasteful.

### `as_revision: bool` is per-call opt-in, NOT auto-wrap on track-changes-enabled

**Decision:** Existing `format_text` and `set_paragraph_format` tools gain `as_revision: bool` arg with default `false`. When `false`, behavior matches v3.11.x exactly (silent format change). When `true`, the tool diverts to revision-generating path. The state of `is_track_changes_enabled` does NOT auto-promote `as_revision: false` calls to revision-wrapped output.

**Rationale:** Two reasons:
1. **Backwards compatibility**: v3.11.x callers with track changes enabled (e.g., for read-side workflows) would suddenly see their format calls produce revisions, surprising them.
2. **MCP/AI workflow ergonomics**: an agent doing mixed operations (some that should be revision-tracked, some that are infrastructure cleanup like font normalization) wants explicit control. Auto-wrap forces an "off then on" toggle dance every few calls.

The cost: callers must remember to pass `as_revision: true`. Mitigated by clear tool descriptions.

**Alternatives considered:**

- *Auto-wrap when track changes enabled:* matches Word UI behavior (when track changes is on, all edits become revisions). Rejected for MCP context where the caller has explicit programmatic control. Word's auto-wrap exists because the UI has no per-action opt-in affordance; MCP tools do.
- *Two separate tools (`format_text` and `format_text_as_revision`):* doubles tool count for marginal clarity. Rejected — the `as_revision` arg is a clean opt-in.

### `as_revision: true` requires track changes enabled, throws instead of auto-enabling

**Decision:** When `as_revision: true` is passed but `is_track_changes_enabled() == false`, the tool throws `track_changes_not_enabled` error rather than silently calling `enable_track_changes()` first.

**Rationale:** Avoids hidden side effects (per user instruction "我覺得需要避免副作用"). Auto-enable would silently mutate `word/settings.xml` and persist track changes state for the rest of the session. Caller might enable track changes for one revision-generating call and then forget to disable, resulting in subsequent normal edits unexpectedly being tracked.

The error message guides the caller: `"track_changes_not_enabled — call enable_track_changes first"`.

**Alternatives considered:**

- *Auto-enable + warn:* friendly DX but the warning gets lost in MCP response logs.
- *Allow even when disabled:* OOXML `<w:rPrChange>` without `<w:trackChanges/>` setting in settings.xml renders inconsistently across Word versions. Rejected.

### `move_text_as_revision` allocates adjacent ids, no shared linkage attribute

**Decision:** `move_text_as_revision` calls `allocateRevisionId()` twice (returns N then N+1). The `<w:moveFrom>` element gets id=N at the source paragraph; `<w:moveTo>` gets id=N+1 at the destination. They are NOT linked via a shared attribute (OOXML doesn't define one).

**Rationale:** Word UI links the visual move pair via document-order proximity + matching author/date metadata. The id pair being adjacent is a convention for our debugging, not a Word-required linkage. Word readers don't depend on adjacent ids — any pair of moveFrom/moveTo with matching author and date is treated as a move.

**Alternatives considered:**

- *Shared id (both = N):* INVALID OOXML — each revision element requires a unique `w:id`. Rejected.
- *Custom attribute like `w:moveLinkId`:* doesn't exist in OOXML schema. Rejected.

### Cross-paragraph delete is OUT OF SCOPE — single-paragraph only

**Decision:** `delete_text_as_revision(paragraph_index, start, end)` operates within a single paragraph only. The `[start, end)` range is interpreted as character offsets within the named paragraph's `getText()`. Inputs spanning paragraphs throw `out_of_bounds`.

The OOXML paragraph-mark deletion case (`<w:pPr><w:rPr><w:del/></w:rPr></w:pPr>` marks the paragraph break itself for deletion, merging with the next paragraph on Accept) is documented as a known limitation in the tool description. A follow-up issue tracks the edge case.

**Rationale:** OOXML's paragraph mark deletion is the trickiest revision shape in the spec. Implementing it requires:
1. New `Paragraph.markDeletedAsRevision` field on `ParagraphProperties`
2. Writer logic that emits `<w:pPr><w:rPr><w:del .../></w:rPr></w:pPr>` even when the paragraph itself stays
3. Reader logic to round-trip the deletion mark
4. UI semantic: this is "the next paragraph will be merged with this one" — not "this paragraph is deleted"

That's a 5-task subprocess for an edge case used in <5% of revision workflows. Out of scope for v3.12.0.

### Single internal engine — `insert_text` and `insert_text_as_revision` share run-splitting code

**Decision:** Add a new private method `WordDocument.insertTextAtRunPosition(text:atParagraph:atRunIndex:atOffset:asRevisionMetadata:RevisionMetadata?)` that handles run splitting. Both `insertText` (the existing public method) and `insertTextAsRevision` (the new public method) call this engine. The optional `RevisionMetadata` struct carries author/date/id when revision-wrapping is requested.

**Rationale:** Keeping two parallel implementations is inviting drift. The run-splitting logic (find the run covering offset, split into pre/new/post) is identical regardless of whether we wrap in revision metadata. Extract once, share.

**Alternatives considered:**

- *Parallel implementations:* clean separation but bug fixes need to land in two places.
- *Decorator pattern with closures:* over-engineered for a 2-caller case.

## Risks / Trade-offs

[Risk] Existing `Revision.toXML` may not correctly emit when wrapping multiple runs. The `<w:ins>` element should contain multiple `<w:r>` siblings when the inserted text spans multiple existing run boundaries. If `toXML` was only tested for single-run cases, we may need to extend it. Mitigation: Phase 1 task includes a verification unit test before building generators.

[Risk] `delete_text_as_revision`'s `[start, end)` character-offset interpretation may not align with `getText()` semantics if the paragraph contains hyperlinks (which contribute their own text). Mitigation: tool description explicitly states "offsets count run text only, not hyperlink text". Existing `replace_text` has the same convention.

[Risk] Date timezone — Word displays revision date in local timezone but stores ISO 8601 with offset. Default `Date()` at server time (UTC on most servers) may show oddly to users in different timezones. Mitigation: tool accepts optional `date` arg as ISO 8601 string for explicit control; default uses `Date()` (UTC).

[Trade-off] Bundling 5 generation methods into one SDD vs splitting (e.g., insert/delete v3.12.0, move v3.13.0, format v3.14.0). Bundling chosen because: (a) all 5 share the same `allocateRevisionId` + `resolveAuthor` infrastructure, (b) one release ceremony, (c) Office.js Roadmap closure is cleaner as a single milestone.

[Trade-off] `as_revision: bool` extends existing tools rather than spawning new tools. Cost: callers need to know about the new arg. Benefit: tool count stays manageable (218 → 221 instead of 218 → 224). Acceptable trade.

## Migration Plan

- ooxml-swift v0.17.x → v0.18.0 — minor version (additive API; existing methods unchanged).
- che-word-mcp v3.11.x → v3.12.0 — minor version (additive tools + extended args; default args preserve v3.11.x behavior). No callers break.
- Binary release triggers marketplace sync per common-release-flow rule.
- Rollback: revert che-word-mcp Package.swift's ooxml-swift dep to ^0.17.0. Re-build. No data migration concerns — new mutations only appear when the new tools are called.

## Open Questions

- Should `move_text_as_revision` accept a `link_id: String?` arg for callers who want a stable identifier across the move pair (for downstream tooling)? Out of OOXML schema but might be useful as a synthetic field stored alongside. Leaning no — let callers use author+date matching.
- For `applyRunPropertiesAsRevision`, do we need a separate variant per property type (`applyBoldAsRevision`, `applyColorAsRevision`, etc.) or is the generic `newProperties: RunProperties` sufficient? Leaning generic — same shape as existing non-revision `format_text` which accepts a property bag.
