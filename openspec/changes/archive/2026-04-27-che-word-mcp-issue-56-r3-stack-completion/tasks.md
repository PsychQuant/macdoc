## 1. Pre-flight

- [x] 1.1 Confirm no in-flight branches touching `Hyperlink.swift`, `Document.swift`, `Paragraph.swift`, `Field.swift`, `Run.swift`, or `DocxReader.swift`. Coordinate on the #56 umbrella thread before starting.
- [x] 1.2 Create `packages/ooxml-swift/Tests/OOXMLSwiftTests/Issue56R3StackTests.swift` skeleton (empty `final class Issue56R3StackTests: XCTestCase {}` plus file-level header comment linking to `https://github.com/PsychQuant/che-word-mcp/issues/56#issuecomment-4321007538`). Confirm file compiles via `swift build`.
- [x] 1.3 Establish baseline: run `swift test` for `packages/ooxml-swift` and confirm 570 tests pass / 1 skipped / 0 failures. Run `swift test` for `mcp/che-word-mcp` and confirm 172 / 9 / 0. Record results in the task PR description.

## 2. R3-NEW-1: Hyperlink mutation API SHALL round-trip on source-loaded hyperlinks (Demote children priority)

- [x] 2.1 Add failing test `testReplaceText_OnSourceLoadedHyperlink_EmitsNewText` to `Issue56R3StackTests.swift`. Test loads a fixture .docx with a hyperlink, calls `document.replaceText("old", with: "new")`, saves to a temp URL, re-reads, and asserts new text is in the hyperlink XML. Confirm the test FAILS on `main` with "old" still present.
- [x] 2.2 Add failing test `testUpdateHyperlinkText_OnSourceLoadedHyperlink_EmitsNewText` for the `update_hyperlink` path. Confirm FAILS on main.
- [x] 2.3 In `packages/ooxml-swift/Sources/OOXMLSwift/Models/Hyperlink.swift`, change writer priority in `toXML()`: emit from `runs` when `runs` is non-empty; fall back to `children` only when `runs.isEmpty`. Satisfies the requirement Hyperlink mutation API SHALL round-trip on source-loaded hyperlinks. Implements design Decision: Demote `children` priority in `Hyperlink` writer instead of syncing mutators.
- [x] 2.4 Run both new tests; confirm PASS. Run full `swift test` suites for `ooxml-swift` and `che-word-mcp`; confirm baseline + 2 new tests, no regressions.
- [x] 2.5 Run scoped `/idd-verify #56` focused on hyperlink-mutation surface. Confirm zero P0 findings related to hyperlink mutation. Commit as `fix(#56-r3-NEW-1): demote Hyperlink.children priority so runs mutations round-trip`.

## 3. R3-NEW-2: ContentControl SHALL expose a position: Int field and emit in source order

- [x] 3.1 Add failing test `testParagraphLevelSDT_BetweenRuns_RoundTripsAtSourcePosition` that constructs a paragraph from XML `<w:p><w:r><w:t>A</w:t></w:r><w:sdt>...</w:sdt><w:r><w:t>B</w:t></w:r></w:p>`, parses, re-emits, and asserts SDT child appears between A and B. Confirm FAILS on main with SDT at end.
- [x] 3.2 Add `public var position: Int` (default 0) to `ContentControl` in `packages/ooxml-swift/Sources/OOXMLSwift/Models/Field.swift`. Update `init` to accept `position` parameter.
- [x] 3.3 In `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift`, modify `parseParagraph` so the `<w:sdt>` case calls `SDTParser.parseSDT(...)` with the current `childPosition` and assigns it to the resulting `ContentControl.position`. Satisfies the requirement ContentControl SHALL expose a position: Int field and emit in source order. Implements design Decision: Add `position: Int` to `ContentControl` and route `<w:sdt>` through positioned-entry sort.
- [x] 3.4 In `packages/ooxml-swift/Sources/OOXMLSwift/Models/Paragraph.swift`, add `<w:sdt>` (from `contentControls`) to the merged positioned-entry list inside `toXMLSortedByPosition`. Skip the existing post-content `contentControls` legacy emit when `hasSourcePositionedChildren == true`.
- [x] 3.5 Run new test; confirm PASS. Run full suites; confirm baseline + 3 new tests, no regressions.
- [x] 3.6 Run scoped `/idd-verify #56` focused on SDT order. Commit as `fix(#56-r3-NEW-2): add ContentControl.position so paragraph-level SDT round-trips at source position`.

## 4. R3-NEW-3: insertComment SHALL emit anchor markers on source paragraphs with existing comment markers

- [x] 4.1 Add failing test `testInsertComment_OnSourceParagraphWithExistingComments_EmitsNewAnchors` that loads a paragraph with `<w:commentRangeStart w:id="3"/>` markers, calls `document.insertComment(text: "second", paragraphIndex: 0)`, re-emits, and asserts both id=3 markers and id=4 markers are present. Confirm FAILS on main.
- [x] 4.2 Add `Document.insertCommentSyncingMarkers` helper in `packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift` that mirrors `appendBookmarkSyncingMarkers`: when target paragraph has source-loaded `commentRangeMarkers`, append matching `<w:commentRangeStart>` / `<w:commentRangeEnd>` / `<w:commentReference>` raw markers for the new commentId. Satisfies the requirement insertComment SHALL emit anchor markers on paragraphs that already have source-loaded comment markers. Implements design Decision: New `insertCommentSyncingMarkers` helper symmetric to `appendBookmarkSyncingMarkers`.
- [x] 4.3 Update existing `Document.insertComment` to delegate to the new helper.
- [x] 4.4 Run new test; confirm PASS. Run full suites; confirm baseline + 4 new tests, no regressions.
- [x] 4.5 Run scoped `/idd-verify #56` focused on comment-marker surface. Commit as `fix(#56-r3-NEW-3): insertComment syncs markers on source paragraphs with existing comments`.

## 5. R3-NEW-4: Mixed-content revision wrappers SHALL populate both raw and typed representations

- [x] 5.1 Add failing test `testMixedContentInsRevision_PopulatesBothRawAndTypedRevision` for the case `<w:ins w:id="5" w:author="Alice"...><w:hyperlink>...</w:hyperlink></w:ins>`. Assert both `paragraph.unrecognizedChildren` (with `<w:ins`) and `paragraph.revisions` (with id=5, type=.insertion, author="Alice") are populated. Confirm FAILS on main (revisions array is empty).
- [x] 5.2 Add failing test `testAcceptRevision_OnMixedContentWrapper_UnwrapsInnerContent` and `testRejectRevision_OnMixedContentWrapper_RemovesEntireWrapper`. Confirm both FAIL on main.
- [x] 5.3 In `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift`, modify the four revision wrapper cases (`<w:ins>` / `<w:del>` / `<w:moveFrom>` / `<w:moveTo>`) so the `hasNonRunChild` branch ALSO appends a `Revision` entry to `paragraph.revisions` (with `isMixedContentWrapper == true` marker) before `break`. Satisfies the requirement Mixed-content revision wrappers SHALL populate both raw and typed representations. Implements design Decision: P0-7 raw capture also populates typed `Revision` model.
- [x] 5.4 Add `isMixedContentWrapper: Bool` field to the `Revision` model. Update `Document.acceptRevision` / `Document.rejectRevision` to detect this flag and strip / unwrap the corresponding raw entry from `paragraph.unrecognizedChildren`.
- [x] 5.5 Run all 3 new tests; confirm PASS. Run full suites; confirm baseline + 7 new tests, no regressions.
- [x] 5.6 Run scoped `/idd-verify #56` focused on revision tooling surface. Commit as `fix(#56-r3-NEW-4): mixed-content revision wrappers populate typed Revision model alongside raw capture`.

## 6. R3-NEW-5: nextBookmarkId calibration SHALL scan all bookmark-bearing document parts

- [x] 6.1 Add failing test `testBookmarkInTableCell_CalibratesNextBookmarkId` (max id 99 in table cell, expect `nextBookmarkId == 100`). Confirm FAILS on main.
- [x] 6.2 Add failing test `testBookmarkInHeader_CalibratesNextBookmarkId` (body max 5, header max 50, expect `nextBookmarkId == 51`). Confirm FAILS on main.
- [x] 6.3 In `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift`, replace the top-level `body.children` calibration scan with a recursive walker that visits paragraphs in body (recursing into table cells and block-level SDT children), headers, footers, footnotes, and endnotes. For each visited paragraph, inspect both `bookmarks` and `bookmarkMarkers` for max id. Satisfies the requirement nextBookmarkId calibration SHALL scan all bookmark-bearing document parts. Implements design Decision: Recursive `nextBookmarkId` calibration across all bookmark-bearing parts.
- [x] 6.4 Run both new tests; confirm PASS. Run full suites; confirm baseline + 9 new tests, no regressions.
- [x] 6.5 Benchmark calibration cost on the 34-namespace builder fixture. If regression > 5ms vs main, add a fast-path that skips calibration when the document declares zero bookmarks (per `Risks / Trade-offs` mitigation).
- [x] 6.6 Run scoped `/idd-verify #56` focused on bookmark allocation. Commit as `fix(#56-r3-NEW-5): nextBookmarkId calibration recurses into tables, headers, footers, notes`.

## 7. R3-NEW-6: Direct-emit XML attribute values SHALL be escaped to prevent injection

- [x] 7.1 Add failing test `testRStyle_WithEmbeddedQuoteAndAngleBracket_DoesNotInjectSiblings` per spec scenario. Confirm FAILS on main with `<injected/>` element appearing in re-parsed XML.
- [x] 7.2 Add `escapeXMLAttribute(_ value: String) -> String` private helper in `packages/ooxml-swift/Sources/OOXMLSwift/Models/Run.swift` (or a shared `XMLEscape.swift` if it benefits readability). Replace `&`, `<`, `>`, `"`, `'` with XML entities.
- [x] 7.3 Route `rStyle` emit in `RunProperties.toXML` through `escapeXMLAttribute(...)`. Satisfies the requirement Direct-emit XML attribute values SHALL be escaped to prevent injection. Implements design Decision: `escapeXML` at every direct attribute emit site, starting with `rStyle`.
- [x] 7.4 Audit all direct-emit attribute sites in `Run.swift`, `RunProperties.swift`, `Paragraph.swift`, `ParagraphProperties.swift`, `Hyperlink.swift`. For each site, either route through the helper or add an inline test-comment justifying escape-safe-by-construction. Document the audit table at the bottom of `Issue56R3StackTests.swift` as a comment block.
- [x] 7.5 Add corner-case tests for `&`, single quote, ampersand combinations against `color`, `fontName`, `rStyle`. Run full suites; confirm baseline + 10+ new tests, no regressions.
- [x] 7.6 Run scoped `/idd-verify #56` with the security reviewer prioritized. Commit as `fix(#56-r3-NEW-6): escape XML attribute values to close rStyle injection sink + audit color/fontName`.

## 8. P1 follow-ups (D-3, D-8)

- [x] 8.1 D-3: In `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift` `parseHyperlink`, capture `XMLElement.namespaces` into `rawAttributes` so vendor `xmlns:` declarations on `<w:hyperlink>` survive round-trip. Add test that loads `<w:hyperlink xmlns:vendor="..." vendor:custom="x">` and asserts both the namespace declaration and the prefixed attribute appear in the re-emitted XML.
- [x] 8.2 D-8: Update `packages/ooxml-swift/CHANGELOG.md` `[0.19.4]` section with a "Breaking changes" subsection documenting that `Hyperlink.id` format changed from `rId5` to `rId5@7` in v0.19.3 (P1-7 fix), and any caller storing pre-v0.19.3 ids should re-parse documents under v0.19.4 to refresh.
- [x] 8.3 Run full suites; confirm baseline + 11+ new tests, no regressions. Commit as `fix(#56-p1-D3): preserve vendor xmlns declarations on hyperlink round-trip` and `docs(#56-p1-D8): document Hyperlink.id format breaking change`.

## 9. Release

- [x] 9.1 Update `packages/ooxml-swift/CHANGELOG.md` with [0.19.4] entries for all six P0 fixes plus D-3 and D-8.
- [x] 9.2 Bump `packages/ooxml-swift` version tag and push: `git tag v0.19.4 && git push --tags`.
- [x] 9.3 In `mcp/che-word-mcp/Package.swift`, bump ooxml-swift dependency to `v0.19.4`. Run `swift package update` and `swift build`.
- [x] 9.4 Update `mcp/che-word-mcp/CHANGELOG.md` with [3.13.4] entry summarizing the six fixes.
- [x] 9.5 Update `mcp/che-word-mcp/mcpb/manifest.json` to version `3.13.4`.
- [x] 9.6 Run full `swift test` for che-word-mcp. Tag `v3.13.4` and push.
- [x] 9.7 `/plugin-tools:plugin-update che-word-mcp` to bump marketplace entry in `psychquant-claude-plugins`.

## 10. Final verify

- [x] 10.1 Run full `/idd-verify #56` (Agent Team + Codex). Per design Decision: Per-task verify gate, not bundle verify — this final pass is the regression-floor check, not the per-fix verify (those happened in tasks 2.5, 3.6, 4.5, 5.6, 6.6, 7.6). **R4 verify result: BLOCK** — 6 P0 + 7 P1 findings from independent reviewers. Posted to #56 (comment 4321562429). v0.19.4/v3.13.4 release halted; commits stay local. See `/tmp/verify_56_r4_merged.md`.
- [~] 10.2 If zero P0 findings, post the verify comment to issue #56 and run `/issue-driven-dev:idd-close #56`. **Skipped — verify BLOCKed; cannot close.**
- [x] 10.3 If new P0 findings appear in R4, do NOT bundle a v3.13.5 hot-fix. Open R5 stack-completion change with the R4 findings using the same per-task discipline established here. Update CHANGELOG and the cross-repo umbrella issue.
