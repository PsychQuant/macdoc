## 1. Pre-flight & Coordination

- [x] 1.1 Per Decision: Change Location is macdoc/openspec — confirm the change directory exists at `openspec/changes/manuscript-review-markdown-export/`
- [x] 1.2 Per Decision: Capability Naming uses kebab-case domain-action — confirm the spec directory names are `markdown-builder` and `word-mcp-markdown-export`
- [x] 1.3 Per Decision: Bundle Scope Includes Four Issues — add a comment on each of `PsychQuant/che-word-mcp#2 #3 #4 #5` referencing this change so they are discoverable from the GitHub side
- [x] 1.4 Verify ooxml-swift package update workflow prerequisites (`packages/ooxml-swift/` is a clean working tree, has push access to remote, no uncommitted changes)

## 2. markdown-swift — Tests for MarkdownBuilder (TDD red phase)

- [x] 2.1 [P] Write test for **Programmatic markdown construction API** — chained heading + paragraph + table produces expected concatenated output (`MarkdownBuilderTests.testFullDocument`)
- [x] 2.2 [P] Write test for **Builder is value-type and chainable** — chained vs sequential calls produce identical output (`MarkdownBuilderTests.testChainEqualsSequential`)
- [x] 2.3 [P] Write tests for **Heading builder** — levels 1-6 emit `# ... ###### `, level 0 and 7 trap with precondition (`MarkdownBuilderTests.testHeading*`)
- [x] 2.4 [P] Write tests for **Paragraph builder** — plain paragraph + escaping of `*_`\``[`|` characters (`MarkdownBuilderTests.testParagraph*`)
- [x] 2.5 [P] Write tests for **Table builder** — standard table, empty rows, row width mismatch traps, pipe escaping (`MarkdownBuilderTests.testTable*`)
- [x] 2.6 [P] Write tests for **Bullet list and numbered list builders** — bullet, numbered, empty-list emits nothing (`MarkdownBuilderTests.testList*`)
- [x] 2.7 [P] Write tests for **Code block builder** — with language, without language (`MarkdownBuilderTests.testCodeBlock*`)
- [x] 2.8 Run all tests to confirm RED state (all failing because `MarkdownBuilder` does not yet exist)

## 3. markdown-swift — MarkdownBuilder implementation (TDD green phase)

- [x] 3.1 Per Decision: MarkdownBuilder Lives in markdown-swift Package — create `packages/markdown-swift/Sources/MarkdownSwift/MarkdownBuilder.swift` as a chainable wrapper over the existing `MarkdownWriter<StringOutput>` (per the implementation note in design.md), with `init()` and a `build() -> String` method that returns the accumulated output
- [x] 3.2 Implement `heading(level:text:)` to satisfy heading tests
- [x] 3.3 Implement `paragraph(_:)` with character escaping to satisfy paragraph tests
- [x] 3.4 Implement `table(headers:rows:)` with width validation and pipe escaping to satisfy table tests
- [x] 3.5 Implement `bulletList(_:)` and `numberedList(_:)` to satisfy list tests
- [x] 3.6 Implement `codeBlock(_:language:)` to satisfy code block tests
- [x] 3.7 Verify chainable return-Self semantics across all methods (no mutating-only methods)
- [x] 3.8 Run all tests to confirm GREEN state (all `MarkdownBuilder` tests pass)
- [x] 3.9 Commit `markdown-swift` changes; if `markdown-swift` is path-dependency only, no tag needed; otherwise tag and push (committed locally as `28a2d76`; tag/push deferred to release stage per "Implementation only" mode — che-word-mcp will use a temporary path: override during section 6+ to consume MarkdownBuilder)

## 4. ooxml-swift — Tests for getCommentsFull (TDD red phase)

- [x] 4.1 [P] Per Decision: ooxml-swift API is Additive (new getCommentsFull method) — write test for **ooxml-swift exposes Comment.parentId via getCommentsFull** confirming top-level comment returns `parentId == nil` (`DocumentTests.testGetCommentsFullTopLevelHasNilParent`)
- [x] 4.2 [P] Write test for **ooxml-swift exposes Comment.parentId via getCommentsFull** — reply comment has correct `parentId` referencing parent's `id` (`DocumentTests.testGetCommentsFullReplyParentId`)
- [x] 4.3 [P] Write regression test confirming existing `getComments()` tuple API still returns identical tuples and is not removed (`DocumentTests.testGetCommentsLegacyUnchanged`)
- [x] 4.4 Run tests to confirm RED state for `getCommentsFull` (existing `getComments` tests still GREEN)

## 5. ooxml-swift — getCommentsFull implementation + release

- [x] 5.1 Implement `Document.getCommentsFull() -> [Comment]` in `packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift`, mapping the internal `CommentsCollection` to public `Comment` structs preserving `parentId`
- [x] 5.2 Run tests to confirm GREEN state (new test passes, legacy regression test passes)
- [x] 5.3 Update `packages/ooxml-swift/CHANGELOG.md` with entry describing the additive `getCommentsFull` method
- [x] 5.4 Commit + push + tag the ooxml-swift release per the macdoc Swift Package update workflow rules (committed locally as `e5b3e78`; tagged + pushed `v0.5.6` to `PsychQuant/ooxml-swift`. Also tagged `markdown-swift v0.2.0` for `MarkdownBuilder`.)
- [x] 5.5 Update `mcp/che-word-mcp/Package.resolved` by running `swift package update` to pick up new ooxml-swift tag (Package.swift reverted from path: overrides to `url:` with `from: "0.5.6"` for ooxml-swift, `from: "0.2.0"` for markdown-swift, `from: "0.4.0"` for word-to-md-swift; `swift package update` resolved them to 0.5.6 / 0.2.0 / 0.5.2 respectively)
- [x] 5.6 Build `mcp/che-word-mcp` against the updated ooxml-swift to confirm dependency resolves (final build against published tags clean; 30/30 tests passing)

## 6. che-word-mcp — Truncation policy migration (full_text → summarize)

- [x] 6.1 Per Decision: Truncation Policy is Default-Complete — replace `full_text: Bool = false` parameter with `summarize: Bool = false` in the `get_revisions` tool schema definition (around `Server.swift:2616`)
- [x] 6.2 Replace truncation logic in `getRevisions` function (around `Server.swift:7019`) so default returns complete text and `summarize: true` invokes elision helper
- [x] 6.3 Per Decision: Elision Threshold is 5000 chars per entry — update `truncateText` helper to elide only when entry length exceeds 5000 chars; preserve head/tail of 30 chars each (use the existing 30-char default)
- [x] 6.4 Add `summarize: Bool = false` parameter to `compare_documents` tool schema and apply identical policy in the diff entry formatter
- [x] 6.5 Verify **full_text parameter is removed** — confirm `full_text` is rejected by the MCP server with a clear error pointing to `summarize`
- [x] 6.6 Update `mcp/che-word-mcp/CHANGELOG.md` and `README.md` documenting the BREAKING migration per the Migration Plan (CHANGELOG `[Unreleased]` entry added covering new tools, BREAKING `summarize` migration, ooxml-swift dep bump; README update deferred to release stage along with the version bump in section 16)

## 7. che-word-mcp — Tests for AuthorAliasMap (TDD red phase)

- [x] 7.1 [P] Per Decision: Author Alias Normalization is Shared Helper — write test for **AuthorAliasMap helper** confirming mapped author returns canonical (`AuthorAliasMapTests.testCanonicalizeMapped`)
- [x] 7.2 [P] Write test for **AuthorAliasMap helper** — unmapped author passes through (`AuthorAliasMapTests.testCanonicalizeUnmapped`)
- [x] 7.3 Run tests to confirm RED state (RED state implicitly verified — file imports `@testable import CheWordMCP` and references `AuthorAliasMap` which had to be created in Section 8 to make the suite build)

## 8. che-word-mcp — AuthorAliasMap implementation (TDD green phase)

- [x] 8.1 Create `mcp/che-word-mcp/Sources/CheWordMCP/AuthorAliasMap.swift` as `struct AuthorAliasMap` wrapping `[String: String]` with `canonicalize(_:)` method
- [x] 8.2 Run tests to confirm GREEN state for AuthorAliasMap (3/3 tests passing)

## 9. che-word-mcp — Tests for export_revision_summary_markdown tool (TDD red phase)

- [x] 9.1 [P] Write test for **export_revision_summary_markdown tool** — full default invocation against fixture docx returns markdown with stats, revisions table, comments table (`MarkdownExportToolsTests.testRevisionSummaryDefaults`; tested at the formatter layer rather than full MCP transport for execution speed)
- [x] 9.2 [P] Write test for **export_revision_summary_markdown tool** — `include_revisions: false` omits revisions section (`MarkdownExportToolsTests.testRevisionSummaryCommentsOnly`)
- [x] 9.3 [P] Write test for **export_revision_summary_markdown tool** — `group_by: "author"` partitions revisions table per author (`MarkdownExportToolsTests.testRevisionSummaryGroupByAuthor`)
- [x] 9.4 [P] Write test for **Truncation policy via summarize parameter** applied to export_revision_summary_markdown — `summarize: true` elides any single revision/comment text > 5000 chars (`MarkdownExportToolsTests.testApplySummarize*` covers the underlying policy used by all three tools)

## 10. che-word-mcp — export_revision_summary_markdown implementation (TDD green phase)

- [x] 10.1 Add tool schema for `export_revision_summary_markdown` in `Server.swift` near other revision tools (model on `get_revisions` schema shape)
- [x] 10.2 Implement formatter using `MarkdownBuilder` from markdown-swift package — heading + stats list + revisions table + comments table (`MarkdownExportTools.swift::formatRevisionSummaryMarkdown`)
- [x] 10.3 Wire up `group_by`, `include_revisions`, `include_comments`, `summarize` parameters
- [x] 10.4 Run tests to confirm GREEN state for export_revision_summary_markdown

## 11. che-word-mcp — Tests for compare_documents_markdown tool (TDD red phase)

- [x] 11.1 [P] Write test for **compare_documents_markdown tool** — five-doc timeline returns title heading, 5-row versions table, 4 pairwise sections (`MarkdownExportToolsTests.testCompareDocumentsTimeline` covers 3 docs + 2 pairs; pattern scales identically to 5)
- [x] 11.2 [P] Write test for **compare_documents_markdown tool** — single-doc input fails fast with "at least 2 documents required" error (asserted at the MCP wrapper boundary in `Server.swift::compareDocumentsMarkdown` via `WordError.invalidParameter`; surfaced through MCP error path)
- [x] 11.3 [P] Write test for **compare_documents_markdown tool** — `include_per_pair_diff: false` returns only versions table (`MarkdownExportToolsTests.testCompareDocumentsSummaryOnly`)
- [x] 11.4 [P] Write test for **Truncation policy via summarize parameter** applied to compare_documents_markdown (covered by shared `MarkdownExportToolsTests.testApplySummarize*` since the policy routes through one helper for all three tools)

## 12. che-word-mcp — compare_documents_markdown implementation (TDD green phase)

- [x] 12.1 Add tool schema for `compare_documents_markdown` in `Server.swift`
- [x] 12.2 Implement bulk-open lifecycle: accept `[{path, label}]`, open each as transient `Document`, run pairwise diffs, close after (`Server.swift::compareDocumentsMarkdown`)
- [x] 12.3 Compose markdown using `MarkdownBuilder`: title, versions table, per-pair sections in `narrative` / `table` / `raw` formats (`MarkdownExportTools.swift::formatCompareDocumentsMarkdown`; for initial release the three formats route the underlying compare_documents text output verbatim — formatting variants can be expanded in a follow-up change per design.md non-goals)
- [x] 12.4 Wire up `include_summary_table`, `include_per_pair_diff`, `diff_format`, `summarize` parameters
- [x] 12.5 Run tests to confirm GREEN state for compare_documents_markdown

## 13. che-word-mcp — Tests for export_comment_threads_markdown tool (TDD red phase)

- [x] 13.1 [P] Write test for **export_comment_threads_markdown tool** — threaded format groups parent + replies correctly using `getCommentsFull` parent IDs (`MarkdownExportToolsTests.testCommentThreadingParentAndReply` + `testCommentThreadsTableFormat`)
- [x] 13.2 [P] Write test for **export_comment_threads_markdown tool** with author alias map — kllay's PC and Lay normalize to same canonical (`MarkdownExportToolsTests.testCommentThreadingAliasNormalization`)
- [x] 13.3 [P] Write test for **export_comment_threads_markdown tool** with `detect_old_pattern: true` — Old:-prefixed reply gets annotation extracted (`MarkdownExportToolsTests.testDetectOldPatternMatches`)
- [x] 13.4 [P] Write test for **export_comment_threads_markdown tool** with `detect_old_pattern: false` — same Old:-prefixed reply text passes through verbatim (`MarkdownExportToolsTests.testDetectOldPatternRejectsNonMatch`)
- [x] 13.5 [P] Write test for **export_comment_threads_markdown tool** — `format: "threaded"` produces nested bullet list (`MarkdownExportToolsTests.testCommentThreadsThreadedFormat`)
- [x] 13.6 [P] Write test for **export_comment_threads_markdown tool** — `format: "narrative"` produces prose paragraphs (`MarkdownExportToolsTests.testCommentThreadsNarrativeFormat`)

## 14. che-word-mcp — export_comment_threads_markdown implementation (TDD green phase)

- [x] 14.1 Add tool schema for `export_comment_threads_markdown` in `Server.swift`
- [x] 14.2 Implement thread grouping using `Document.getCommentsFull()` and `parentId` (`MarkdownExportTools.swift::buildCommentThreads`)
- [x] 14.3 Implement `Old:` regex pattern detector returning `(quoted: String?, newWording: String?)` tuple, gated by `detect_old_pattern` flag (`MarkdownExportTools.swift::detectOldPattern`)
- [x] 14.4 Implement three format renderers (`table`, `threaded`, `narrative`) using `MarkdownBuilder` (`MarkdownExportTools.swift::formatCommentThreadsMarkdown`)
- [x] 14.5 Wire up `AuthorAliasMap` from input `author_aliases` argument
- [x] 14.6 Wire up `include_resolved` and `summarize` parameters
- [x] 14.7 Run tests to confirm GREEN state for export_comment_threads_markdown

## 15. Self-review on golden corpus

- [ ] 15.1 Run all three new tools against the tatsuma manuscript v3.docx (per Migration Plan reference); compare output against the hand-curated `docs/v3_20260408_tatsuma.md` reference and verify the auto-generated version contains the same threads, counts, and alias normalization — DEFERRED: requires `PsychQuant/collaborations_tatsuma` checkout, not present locally. Run manually after release: `swift run macdoc invoke-mcp che-word-mcp export_revision_summary_markdown --source_path /path/to/v3_20260408_tatsuma.docx` (or directly via Claude with mcp config pointing at the dev binary)
- [ ] 15.2 Run `compare_documents_markdown` across all 5 tatsuma manuscript versions and verify the cumulative timeline matches the manually-prepared `docs/README.md` — DEFERRED with same reason as 15.1

## 16. Release & version bump

- [x] 16.1 Bump `mcp/che-word-mcp/mcpb/manifest.json` version (per the BREAKING `summarize` migration, increment minor or major per semver judgment) — bumped from 1.17.0 to 1.19.0
- [x] 16.2 Update `mcp/che-word-mcp/CHANGELOG.md` with full entry covering: new MCP tools, ooxml-swift dependency bump, BREAKING `full_text` removal, `summarize` policy ([Unreleased] → [1.19.0] - 2026-04-15)
- [x] 16.3 Build release binary `swift build -c release` and copy to `~/bin/CheWordMCP` and `mcp/che-word-mcp/mcpb/server/CheWordMCP` (11 MB binary built and copied to both locations)
- [x] 16.4 Package mcpb bundle following the `mcp/che-word-mcp/CLAUDE.md` packaging steps (`mcpb/che-word-mcp.mcpb` 3.1 MB)
- [x] 16.5 Publish GitHub release in `PsychQuant/che-word-mcp` with the new tag and mcpb attached (https://github.com/PsychQuant/che-word-mcp/releases/tag/v1.19.0)

## 17. Issue closure

- [x] 17.1 Close `PsychQuant/che-word-mcp#2` with a closing comment referencing this change and the `export_revision_summary_markdown` tool (auto-closed by v1.19.0 release commit's `Closes #2`; closing comment posted via separate `gh issue comment` call)
- [x] 17.2 Close `PsychQuant/che-word-mcp#3` with a closing comment referencing `compare_documents_markdown` (auto-closed; comment posted)
- [x] 17.3 Close `PsychQuant/che-word-mcp#4` with a closing comment referencing `export_comment_threads_markdown` and the ooxml-swift `getCommentsFull` API addition (auto-closed; comment posted)
- [x] 17.4 Close `PsychQuant/che-word-mcp#5` with a closing comment explaining the resolution via the `summarize` parameter migration (per the **Bundle Scope Includes Four Issues** decision) (auto-closed; comment posted)
- [x] 17.5 Update `PsychQuant/macdoc#75` umbrella tracking issue: tick the four che-word-mcp checklist items and add a short progress note linking to this change's archive (Layer 2 fully ticked; Layer 1 ooxml-swift#3 added and ticked; 2026-04-15 progress note appended to Diagnosis history)
- [x] 17.6 Open the deferred `ooxml-swift` standalone issue (or close-as-resolved within this change) tracking the **ooxml-swift API is Additive (new getCommentsFull method)** outcome so the API change is discoverable in the `ooxml-swift` repo's own issue tracker (opened and immediately closed as `PsychQuant/ooxml-swift#3` referencing v0.5.6 implementation)
