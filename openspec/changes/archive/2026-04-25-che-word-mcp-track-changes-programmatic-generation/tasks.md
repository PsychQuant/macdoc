## 1. Test Fixtures and Scaffolding

- [x] 1.1 [P] Create `packages/ooxml-swift/Tests/OOXMLSwiftTests/RevisionGenerationTests.swift` scaffold with helpers for building docs with track-changes enabled + multiple paragraphs + asserting Revision array contents + asserting writer XML output contains `<w:ins>` / `<w:del>` / `<w:moveFrom>` / `<w:moveTo>` / `<w:rPrChange>` / `<w:pPrChange>` markup with correct id / author / date attributes
- [x] 1.2 [P] Create `mcp/che-word-mcp/Tests/CheWordMCPTests/TrackChangesProgrammaticToolsTests.swift` scaffold with MCP tool invocation helpers + result-text JSON-substring assertions (mirrors `StylesNumberingSectionsToolsTests` shape) + helper to enable track changes in setup

## 2. ooxml-swift Revision Infrastructure Verification

- [x] 2.1 Verify Revision.toXML correctly emits `<w:ins>` wrapping multiple `<w:r>` siblings — write test that builds a Revision wrapping 3 runs and asserts the output XML structure has exactly one `<w:ins>` / `</w:ins>` pair containing 3 `<w:r>...</w:r>` blocks. If the existing toXML only handles single-run cases, extend it to support multi-run wrapping in this same task.
- [x] 2.2 [P] Verify Revision.toXML correctly substitutes `<w:t>` with `<w:delText>` when type is `.deletion` — assert the output of a deletion-typed Revision wrapping a run with text "World" produces `<w:del ...><w:r><w:delText xml:space="preserve">World</w:delText></w:r></w:del>` (no `<w:t>` element)

## 3. ooxml-swift WordDocument Methods + WordError

- [x] 3.1 WordDocument.allocateRevisionId — implement the `WordDocument exposes revision id allocator` requirement; scan `revisions.revisions` for max id (covers body + headers + footers + footnotes + endnotes since they all populate the same collection); return max+1 (or 1 when empty); mirrors v0.15.0 `allocateSdtId` shape
- [x] 3.2 [P] Add WordError.trackChangesNotEnabled case + private resolveAuthor helper — extend `packages/ooxml-swift/Sources/OOXMLSwift/Errors/WordError.swift` with `trackChangesNotEnabled` case; add private static `resolveAuthor(explicit:fallback:)` helper on Document.swift that returns explicit (if non-nil non-empty) or fallback or "Unknown"
- [x] 3.3 WordDocument.insertTextAsRevision — implement first half of `WordDocument exposes revision-generating mutations` requirement; guard isTrackChangesEnabled; allocate id; split run at position via existing TextReplacementEngine helpers (or inline if cleaner); append Revision(type:.insertion) to paragraph.revisions; mark word/document.xml dirty; throw invalidIndex on out-of-bounds paragraph_index or position
- [x] 3.4 WordDocument.deleteTextAsRevision — implement deletion variant; guard track changes enabled; identify runs covering [start, end) within single paragraph (throw invalidIndex when range exceeds paragraph text length); append Revision(type:.deletion) with the deleted text content captured in originalText field; writer's existing toXML handles `<w:t>` → `<w:delText>` substitution
- [x] 3.5 WordDocument.moveTextAsRevision — allocate two consecutive revision ids (N then N+1); append Revision(type:.moveFrom, id:N) at fromParagraph; append Revision(type:.moveTo, id:N+1) at toParagraph; return tuple (fromId:N, toId:N+1); guard track changes enabled
- [x] 3.6 WordDocument.applyRunPropertiesAsRevision — guard track changes enabled; capture target run's current RunProperties; assign newProperties to the run; append Revision(type:.formatChange) with previousFormat field set to the captured prior properties; writer emits `<w:rPrChange>` inside the run's `<w:rPr>`
- [x] 3.7 WordDocument.applyParagraphPropertiesAsRevision — same shape as 3.6 but for paragraph properties; appends Revision(type:.paragraphChange) with previousFormat captured; writer emits `<w:pPrChange>` inside the paragraph's `<w:pPr>`

## 4. ooxml-swift v0.18.0 Release

- [x] 4.1 Run full ooxml-swift test suite (target: 525+ pass) + push commits + tag v0.18.0 + create GitHub release with description matching proposal Why section
- [x] 4.2 Bump `mcp/che-word-mcp/Package.swift` ooxml-swift dep from 0.17.0 to 0.18.0; run `swift package update`; verify build green

## 5. che-word-mcp Track Changes Tools

- [x] 5.1 [P] Tool insert_text_as_revision — implement the `insert_text_as_revision wraps inserted text in <w:ins>` requirement; guard track_changes_not_enabled (return error JSON, do NOT auto-enable); call WordDocument.insertTextAsRevision; return success message with allocated id
- [x] 5.2 [P] Tool delete_text_as_revision — implement the `delete_text_as_revision wraps deleted text in <w:del>` requirement; surface track_changes_not_enabled and out_of_bounds errors
- [x] 5.3 [P] Tool move_text_as_revision — implement the `move_text_as_revision emits paired moveFrom + moveTo` requirement; return success message including both allocated ids; surface error set
- [x] 5.4 Extend format_text with as_revision arg — implement the `format_text accepts as_revision arg` requirement; default false preserves v3.11.x behavior; when true diverts through WordDocument.applyRunPropertiesAsRevision; throws track_changes_not_enabled (no auto-enable)
- [x] 5.5 Extend set_paragraph_format with as_revision arg — implement the `set_paragraph_format accepts as_revision arg` requirement; same divert pattern as 5.4

## 6. End-to-end Tests + che-word-mcp v3.12.0 Release

- [x] 6.1 [P] Contract redline E2E test in `mcp/che-word-mcp/Tests/CheWordMCPTests/ContractRedlineE2ETests.swift` — build doc with paragraph "The contract amount is $100,000."; enable_track_changes(author: "Reviewer A"); insert_text_as_revision adding " (subject to escalation)" at end; delete_text_as_revision removing "$100,000" then insert "$120,000"; format_text bolding "contract" with as_revision: true; save and re-read via DocxReader; verify all 4 revisions present with correct types + author "Reviewer A" + ids allocated by max+1 strategy
- [x] 6.2 [P] Multi-author interleaving E2E test (same file) — enable_track_changes(author: "Author A"), insert revision; disable_track_changes; enable_track_changes(author: "Author B"); insert second revision (with explicit author override "Author C"); verify the 3 revisions have authors A, C, A's settings respectively (NOT B — because explicit arg overrides settings); verify ids are 1, 2, 3 in allocation order
- [x] 6.3 [P] Side-effect avoidance E2E test (same file) — verify format_text(as_revision: true) when track changes is OFF returns track_changes_not_enabled error AND document state is unchanged AND track changes remains OFF (no auto-enable side effect)
- [x] 6.4 Update `mcp/che-word-mcp/CHANGELOG.md` with v3.12.0 entry + bump `mcp/che-word-mcp/mcpb/manifest.json` to 3.12.0 + bump psychquant-claude-plugins plugin.json analog
- [x] 6.5 Build release binary `swift build -c release` + copy to `~/bin/CheWordMCP` and `mcp/che-word-mcp/mcpb/server/CheWordMCP` + repackage `mcpb/che-word-mcp.mcpb`
- [x] 6.6 Tag v3.12.0 + push + create GitHub release with description matching CHANGELOG + upload mcpb + binary assets
- [x] 6.7 Run `/plugin-tools:plugin-update che-word-mcp` to sync marketplace.json in psychquant-claude-plugins; verify `claude plugin list` shows v3.12.0
- [x] 6.8 Close issue #45 via `/issue-driven-dev:idd-close` — Closing Summary references this SDD's archive path; explicitly notes Office.js Roadmap P0 set is now 100% complete
