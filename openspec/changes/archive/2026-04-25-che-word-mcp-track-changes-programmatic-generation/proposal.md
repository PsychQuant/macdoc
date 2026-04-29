## Why

che-word-mcp v3.11.0 closes 6 of 7 P0 issues from the Office.js OOXML Roadmap ([che-word-mcp#43](https://github.com/PsychQuant/che-word-mcp/issues/43)). The last P0 — [#45 §2 程式化產生 Track Changes 修訂標記](https://github.com/PsychQuant/che-word-mcp/issues/45) — fills a gap that blocks the most important MCP/AI use case: AI assistants making auditable redline edits.

Today che-word-mcp's Track Changes support is **read-only**:
- `enable_track_changes` / `disable_track_changes` / `is_track_changes_enabled` exist
- `accept_revision` / `reject_revision` / `accept_all_revisions` / `reject_all_revisions` exist
- `get_revisions` enumerates existing revisions

But mutation tools (`insert_text`, `replace_text`, `delete_paragraph`, `format_text`, `set_paragraph_format`) silently rewrite content — they don't produce `<w:ins>` / `<w:del>` / `<w:rPrChange>` / `<w:pPrChange>` markup. So when an AI assistant edits a contract, legal review, academic manuscript, or collaborative document, the changes appear as if a normal user typed them — there's no redline trail, no Accept/Reject UI affordance for the human reviewer.

For legal, contract, and academic 協作 scenarios this defeats Track Changes' core purpose.

**~80% of the infrastructure already exists** (RevisionType enum with all 6 cases, Revision.toXML emitting `<w:ins>` / `<w:del>` / `<w:delText>` correctly, Paragraph.revisions field, enableTrackChanges/acceptRevision/rejectRevision on WordDocument). What's missing is the **write-side wrapper layer**: WordDocument methods that wrap mutations with revision metadata, plus MCP tool surfaces that expose them.

Bundling this as a single SDD (rather than multiple PRs) lets one ooxml-swift release ship all 5 generation methods together with their corresponding MCP tools, completing the Office.js Roadmap P0 set in one cohesive milestone.

## What Changes

### Phase 1 — ooxml-swift v0.18.0 (model + 5 mutation methods)

- New `WordDocument.allocateRevisionId() -> Int` — scans `revisions.revisions` across body + headers + footers + footnotes + endnotes for max revision id, returns max+1 (mirrors `allocateSdtId` pattern from v0.15.0)
- New `WordDocument.insertTextAsRevision(text:atParagraph:position:author:date:)` — guards `isTrackChangesEnabled()`; allocates revision id; splits the run at `position`; wraps the new text run with a `Revision(type: .insertion, id, author, date, ...)` entry on the paragraph
- New `WordDocument.deleteTextAsRevision(atParagraph:start:end:author:date:)` — guards track changes enabled; identifies the run range covering `[start, end)` via existing `TextReplacementEngine` flatten-then-map logic; wraps the deleted runs with `Revision(type: .deletion, ...)`; writer substitutes `<w:t>` → `<w:delText>` automatically (existing Revision.toXML behavior)
- New `WordDocument.moveTextAsRevision(fromParagraph:fromStart:fromEnd:toParagraph:toPosition:author:date:)` — allocates two consecutive revision ids; emits paired `Revision(type: .moveFrom, id: N, ...)` at source and `Revision(type: .moveTo, id: N+1, ...)` at destination; writer emits `<w:moveFrom>` / `<w:moveTo>` blocks accordingly
- New `WordDocument.applyRunPropertiesAsRevision(atParagraph:atRunIndex:newProperties:author:date:)` — guards track changes; captures the run's current `RunProperties` as `previousFormat`; appends a `Revision(type: .formatChange, ...)` so the writer emits `<w:rPr>` containing `<w:rPrChange>` with the prior formatting
- New `WordDocument.applyParagraphPropertiesAsRevision(atParagraph:newProperties:author:date:)` — same shape but for `<w:pPrChange>` on `<w:pPr>`
- New `WordError.trackChangesNotEnabled` case for guard violations

The 5 new methods all call a private `resolveAuthor(_:)` helper that returns the explicit arg when present, falls back to `revisions.settings.author` otherwise, and only returns `"Unknown"` when both are absent.

### Phase 2 — che-word-mcp v3.12.0 (3 new MCP tools + 2 extended args)

**3 new tools:**

- `insert_text_as_revision(doc_id, paragraph_index, position, text, author?, date?)` — calls `WordDocument.insertTextAsRevision`; surfaces `track_changes_not_enabled` error
- `delete_text_as_revision(doc_id, paragraph_index, start, end, author?, date?)` — calls `WordDocument.deleteTextAsRevision`; surfaces `track_changes_not_enabled` and `out_of_bounds` errors
- `move_text_as_revision(doc_id, from_paragraph_index, from_start, from_end, to_paragraph_index, to_position, author?, date?)` — calls `WordDocument.moveTextAsRevision`; surfaces same error set

**2 extended args:**

- `format_text` gains `as_revision: bool` (default `false`); when `true`, the helper diverts to `WordDocument.applyRunPropertiesAsRevision` instead of the silent path; throws `track_changes_not_enabled` when track changes is off
- `set_paragraph_format` gains `as_revision: bool` (default `false`); same divert logic to `applyParagraphPropertiesAsRevision`

Default `false` preserves v3.11.x behavior exactly. `as_revision: true` requires `enable_track_changes` to have been called first — does NOT auto-enable (avoids side effects per design decision).

### Phase 3 — Release ceremony

- ooxml-swift v0.18.0 push + tag + GitHub release
- che-word-mcp v3.12.0 build, install, mcpb package, GitHub release
- psychquant-claude-plugins marketplace.json sync
- Close #45 via `/idd-close`
- **Office.js Roadmap P0 set is 100% complete after this release**

## Non-Goals

- **Cross-paragraph delete** (the `<w:pPr><w:rPr><w:del/></w:rPr></w:pPr>` paragraph-mark-deletion case) — `delete_text_as_revision` operates within a single paragraph only. Cross-paragraph delete is OOXML's trickiest revision shape (paragraph mark deletion merges paragraphs on Accept) and adds 2-3x complexity for an edge case. Documented as known limitation in tool description; follow-up issue tracks it.
- **Auto-wrap on track-changes-enabled** — `format_text(as_revision: false)` does NOT auto-promote to revision when track changes is on. Per-call opt-in matches MCP/AI workflow ergonomics where the agent often does mixed operations and wants explicit control.
- **Auto-enable track changes on `as_revision: true`** — throws `track_changes_not_enabled` instead. Avoids hidden side effects per user requirement.
- **Linked moveFrom/moveTo via shared id** — Word OOXML allocates separate ids for the move pair (visual linkage is via document-order proximity + author/date matching, not id). We allocate adjacent ids (N and N+1) for clarity but they remain independent revisions.
- **`<w:numberingChange>` revision type** — issue body lists this as a 6th revision type but the OOXML spec deprecated it in favor of `<w:rPrChange>` covering numbering property changes. Skipped unless a real-world need surfaces.
- **Revision rejection by author or date filter** — existing `reject_revision(id)` API is sufficient for v3.12.0; bulk-by-author/date is its own SDD.
- **Bidirectional revision conflict resolution** — when two callers concurrently mutate the same paragraph as revisions, the second write overwrites the first; no merge semantics. Documented as known limitation.

## Capabilities

### New Capabilities

- `che-word-mcp-tracked-changes-tools`: 3 new MCP tools for programmatic generation of `<w:ins>` / `<w:del>` / `<w:moveFrom>` + `<w:moveTo>` revisions, plus 2 extended args on existing format tools for `<w:rPrChange>` / `<w:pPrChange>` revisions

### Modified Capabilities

- `ooxml-document-part-mutations`: extends with 5 new WordDocument methods (`allocateRevisionId`, `insertTextAsRevision`, `deleteTextAsRevision`, `moveTextAsRevision`, `applyRunPropertiesAsRevision`, `applyParagraphPropertiesAsRevision`) covering revision-generation. All methods explicitly mark `word/document.xml` dirty.

## Impact

- Affected specs:
  - New: `openspec/specs/che-word-mcp-tracked-changes-tools/spec.md`
  - Modified: `openspec/specs/ooxml-document-part-mutations/spec.md`
- Affected code:
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift` (add 6 new methods — 5 generators + 1 id allocator)
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Errors/WordError.swift` (add `trackChangesNotEnabled` case)
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Revision.swift` (verify multi-run wrapping in toXML works; add helper if needed)
  - Modified: `mcp/che-word-mcp/Sources/CheWordMCP/Server.swift` (register 3 new tools + dispatcher cases + helper functions; extend `format_text` and `set_paragraph_format` with `as_revision: bool` arg)
  - Modified: `packages/ooxml-swift/Package.swift` (version bump to 0.18.0)
  - Modified: `mcp/che-word-mcp/Package.swift` (ooxml-swift dep bump to 0.18.0)
  - Modified: `mcp/che-word-mcp/mcpb/manifest.json` (version 3.12.0)
  - Modified: `mcp/che-word-mcp/CHANGELOG.md` (v3.12.0 entry)
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/RevisionGenerationTests.swift`
  - New: `mcp/che-word-mcp/Tests/CheWordMCPTests/TrackChangesProgrammaticToolsTests.swift`
  - New: `mcp/che-word-mcp/Tests/CheWordMCPTests/ContractRedlineE2ETests.swift`
