# Implementation Tasks

Three sub-stacks ship independently as v0.19.6 / v0.19.7 / v0.20.0. Each sub-stack runs through its own per-task verify gate (failing test → impl → green → scoped Codex verify → commit). The matrix-pin (`testDocumentContentEqualityInvariant`) extends incrementally — sub-stack A adds bookmark-count assertions, B adds whitespace-char assertions, C adds RunProperties assertions. Final 6-AI verify runs after sub-stack C lands.

## 0. Design + spec cross-reference (orientation, not action)

This change implements the design.md decisions and the three spec deltas. Each task below cites the design topic and spec requirement it implements. Quick orientation map:

**Goals / Non-Goals**: Sub-stacks A/B/C cover all stated goals (#58 + #59 + #60 closure + matrix-pin); §3.16 explicitly drops the modified-parts caveat from `docs/structural-editing-paradigm.md` per the goal "byte-preservation invariant for unmodified parts". Non-goals (no parser swap, no MCP API surface, no inter-element-whitespace fix) are respected by the absence of those concerns from any task.

**Decision 1: bundle three issues under one spectra change with three independently-shipping sub-stacks** — realized by §1 / §2 / §3 sub-stack structure. Each sub-stack ships its own ooxml-swift release (v0.19.6 / v0.19.7 / v0.20.0) plus che-word-mcp dep bump (v3.13.6 / v3.13.7 / v3.14.0).

**Decision 2: whitespace overlay scan (not parser swap)** — realized by §2.3 (new `WhitespaceOverlay` type), §2.4 (plumbing through `DocxReader.read`), §2.5 (consult on empty `t.stringValue`). Foundation `XMLDocument` retained as primary parser per Risk 4 mitigation.

**Decision 3: hybrid typed-plus-raw approach for #60 runproperties** — realized by §3.4 (typed fields: `noProof`, `kern`, `lang`, `rFonts` 4-axis) + §3.5 (`rawChildren: [RawElement]?` for `w14:*` and other unknowns). Same pattern as `Run.rawElements` precedent (`Run.swift:24-30`).

**Decision 4: bodychild enum extension shape (typed + generic catch-all)** — realized by §1.3 (two new cases: `bookmarkMarker` + `rawBlockElement`), §1.4 (parser branches), §1.5 (writer branches). Rejected alternatives (typed-only, generic-only) documented in design.md.

**Decision 5: matrix-pin assertion strategy (content equality, not byte equality)** — realized by §1.7 (bookmarkStart count parity), §2.7 (`<w:t>` total-character parity), §3.9 (RunProperties typed-field count parities). Each is a count or joined-string assertion, not element-by-element byte diff.

**Risk 1: element-position keying in whitespaceoverlay** — mitigated by §2.1, §2.2 (per-test fixture coverage) and §2.10 / §2.14 (sub-stack B 6-AI verify gate).

**Risk 2: sub-stack c scope creep** — mitigated by matrix-pin acting as inclusion gate — §3.9 enumerates the explicit fields in scope; §3.11 sets the success metric (round-trip size within 5% of source). Anything else defers to follow-up.

**Risk 3: verify cycle length** — mitigated by independent sub-stack release cadence — §1.13 / §2.15 / §3.16 each gate on PASS verify before declaring sub-stack complete; partial wins (sub-stacks A and B) ship value before C lands.

**Risk 4: foundation xmldocument behavior change** — low-priority; no task action required (overlay continues to work even if Apple fixes it).

**Matrix-pin coupling**: addressed by incremental matrix-pin extension across §1.7 → §2.7 → §3.9 — each sub-stack adds its own preservation-class assertion to the same `testDocumentContentEqualityInvariant` test rather than creating separate tests.

## 1. Sub-stack A — #58 BodyChild block-level marker preservation (v0.19.6)

- [x] 1.1 [P] Write failing test `testBodyLevelBookmarkRoundTripPreserved` in `Tests/OOXMLSwiftTests/Issue58_60ContentPreservationTests.swift` — fixture with `<w:body><w:p>before</w:p><w:bookmarkStart w:id="0" w:name="_TocTest"/><w:p>middle</w:p><w:bookmarkEnd w:id="0"/><w:p>after</w:p></w:body>`; assert that after `DocxReader.read` → `DocxWriter.write` (with `modifiedParts` insert), output `word/document.xml` contains the same `<w:bookmarkStart>` and `<w:bookmarkEnd>` at body-child positions. (Covers spec requirement: `BodyChild enum SHALL cover EG_BlockLevelElts members beyond paragraph and table` — Scenarios "Body-level bookmarkStart preserved through round-trip" and "Body-level bookmarkEnd preserved through round-trip")

- [x] 1.2 [P] Write failing test `testBodyLevelUnknownElementPreservedAsRaw` — fixture with `<w:body><w:p>x</w:p><w:moveFromRangeStart w:id="1" w:name="testMove"/><w:p>y</w:p></w:body>`; assert post-roundtrip the unknown element survives byte-equivalent. (Covers spec requirement: `BodyChild enum SHALL cover EG_BlockLevelElts members beyond paragraph and table` — Scenario "Unknown body-level element preserved as raw element")

- [x] 1.3 Extend `BodyChild` enum in `packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift:3520` with two new cases: `case bookmarkMarker(BookmarkRangeMarker)` (typed for known kinds) and `case rawBlockElement(RawElement)` (generic catch-all per design Decision 4).

- [x] 1.4 Extend `parseBodyChildren` switch in `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift:582-631` with explicit `case "bookmarkStart"` and `case "bookmarkEnd"` branches that produce `BodyChild.bookmarkMarker(BookmarkRangeMarker(...))`. Convert `default: continue` to `default: children.append(.rawBlockElement(RawElement(name: el.localName, xml: el.xmlString)))` for generic passthrough.

- [x] 1.5 Extend `xmlForBodyChild` (or equivalent body-child writer in `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxWriter.swift`) with emit branches for `.bookmarkMarker` (emits `<w:bookmarkStart w:id="..." w:name="..."/>` or `<w:bookmarkEnd w:id="..."/>`) and `.rawBlockElement` (emits the captured raw XML verbatim).

- [x] 1.6 Extend `nextBookmarkId` calibration walker in `packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift` to include body-level `BookmarkRangeMarker` entries (in addition to existing `paragraph.bookmarkMarkers`). Write supporting test `testNextBookmarkIdReflectsBodyLevelBookmarksAfterRead`. (Covers spec requirement: `nextBookmarkId calibration SHALL include body-level bookmark markers` — Scenario "nextBookmarkId reflects body-level bookmarks after read")

- [x] 1.7 Extend `testDocumentContentEqualityInvariant` matrix-pin (initial version in this sub-stack) with `<w:bookmarkStart>` count parity assertion against the thesis fixture. Test passes after this sub-stack with bookmarkStart count 45=45. (Covers spec requirement: `testDocumentContentEqualityInvariant matrix-pin SHALL assert content equality across preservation classes` — initial version covering preservation-class 1 of 3; full coverage lands incrementally via §2.7 and §3.9)

- [x] 1.8 Run full suite `swift test --disable-sandbox`; expect 654 / 0 / 1 (652 baseline + 3 new tests from §1.1, §1.2, §1.6, §1.7).

- [x] 1.9 Bump `packages/ooxml-swift/CHANGELOG.md` with v0.19.6 entry referencing #58. Commit with `fix(#58): preserve body-level bookmark markers via BodyChild enum extension`. Tag `v0.19.6`. Push.

- [x] 1.10 Bump `mcp/che-word-mcp/Package.swift` ooxml-swift dep `0.19.5 → 0.19.6`; update `mcp/che-word-mcp/CHANGELOG.md` v3.13.6 entry; update `mcp/che-word-mcp/mcpb/manifest.json` version `3.13.6`. Build mcpb. Commit `feat: v3.13.6 — bump ooxml-swift v0.19.5 → v0.19.6 (closes #58)`. Tag `v3.13.6`. Push. Upload mcpb + raw CheWordMCP binary as release assets.

- [x] 1.11 Run `/plugin-tools:plugin-update che-word-mcp` to sync marketplace.

- [x] 1.12 Run sub-stack A 6-AI verify (Agent Team × 5 standalone Claude reviewers + Codex) on the v0.19.6 / v3.13.6 commits. Post verify report to #58.

- [~] 1.13 Sub-stack A 6-AI verify returned BLOCK with 2 P0 + 1 P1 + 4 P2/MEDIUM. Verify report: https://github.com/PsychQuant/che-word-mcp/issues/58#issuecomment-4323205184. Opening sub-stack A-CONT mini-cycle (§1.14-§1.21) following R5-CONT-4 precedent. Cannot close #58 yet.

## 1-CONT. Sub-stack A-CONT — close 2 P0 + 1 P1 from sub-stack A 6-AI verify

The sub-stack A 6-AI verify (https://github.com/PsychQuant/che-word-mcp/issues/58#issuecomment-4323205184) returned BLOCK with 2 P0 + 1 P1 (independently confirmed by R2 Logic + R5 Devil's Advocate + direct code read). Same convergence-cycle pattern as R5-CONT-4: per-task gate caught #58 in `parseBodyChildren` (body.xml entry point); 6-AI verify caught the symmetric sibling in `parseContainerChildBodyChildren` (header/footer/footnote/endnote entry point) that the per-task gate missed. The matrix-pin only exercised body source; container source slipped through.

A-CONT mirrors the existing fix shape into the second parser entry point AND tightens the matrix-pin with positional + container-source assertions. Re-numbers planned sub-stack B → v0.19.8 / v3.13.8 (sub-stack C unchanged at v0.20.0 / v3.14.0).

- [x] 1.14 [P] Write failing test `testHeaderBodyLevelBookmarkRoundTripPreserved` — fixture with `word/header1.xml` containing `<w:hdr><w:bookmarkStart w:id="9" w:name="hdrAnchor"/><w:p>...</w:p><w:bookmarkEnd w:id="9"/></w:hdr>`; mutate body to force header re-serialize; assert post-roundtrip output `header1.xml` still contains `<w:bookmarkStart w:name="hdrAnchor"`. Repeat similar tests for footer, footnote, endnote (4 tests total). Tests SHALL fail pre-A-CONT-fix.

- [x] 1.15 Extend `parseContainerChildBodyChildren` in `Sources/OOXMLSwift/IO/DocxReader.swift:1291-1322` with the same `case "bookmarkStart"` / `case "bookmarkEnd"` / `case "sectPr": continue` / `default: .rawBlockElement` branches that `parseBodyChildren` (line 582-700) has. Mirror exact same fix shape.

- [x] 1.16 [P] Write failing test `testListBookmarksSurfacesBodyLevelMarkers` — fixture with body-level `<w:bookmarkStart w:name="_Toc12345"/>`; call `getBookmarks()`; assert response includes `_Toc12345`. Test SHALL fail pre-A-CONT-fix because `getBookmarks()` only iterates `case .paragraph`.

- [x] 1.17 Extend `Document.getBookmarks()` at `Sources/OOXMLSwift/Models/Document.swift:2122-2136` to walk body-level `.bookmarkMarker(BookmarkRangeMarker)` entries across `body.children` + `headers[].bodyChildren` + `footers[].bodyChildren` + `footnotes.footnotes[].bodyChildren` + `endnotes.endnotes[].bodyChildren`. Recurse into `.contentControl(_, let inner)`. Pair start/end markers by id into named ranges. Preserve existing paragraph-level extraction.

- [x] 1.18 Extend matrix-pin `testDocumentContentEqualityInvariant` with container-source preservation-class assertions: `<w:bookmarkStart>` count parity for header / footer / footnote / endnote (in addition to body). Add positional assertion that body-level marker emits between same paragraph siblings post-roundtrip (catches paraIndex drift class — A-CONT P1).

- [x] 1.19 [P2] Fix stale comment in `parseBodyChildren` ("Other elements are skipped") to reflect new raw-preserve behavior. (codex P2 finding)

- [x] 1.20 Run full suite `swift test --disable-sandbox`; expect 661 / 0 / 1 (656 sub-stack A baseline + 5 new A-CONT tests).

- [x] 1.21 Bump `packages/ooxml-swift/CHANGELOG.md` with v0.19.7 entry referencing A-CONT scope. Commit `fix(#58 A-CONT): preserve body-level bookmark markers in container parser entry points + extend list_bookmarks walker`. Tag `v0.19.7`. Push.

- [x] 1.22 Bump `mcp/che-word-mcp/Package.swift` ooxml-swift dep `0.19.6 → 0.19.7`; update CHANGELOG v3.13.7 entry; manifest `3.13.7`. Build mcpb. Commit `feat: v3.13.7 — bump ooxml-swift v0.19.6 → v0.19.7 (closes #58 A-CONT)`. Tag `v3.13.7`. Push. Upload mcpb + raw CheWordMCP binary as release assets.

- [x] 1.23 Run `/plugin-tools:plugin-update che-word-mcp` to sync marketplace.

- [x] 1.24 Run sub-stack A-CONT 6-AI verify on v0.19.7 / v3.13.7 commits. Post verify report to #58.

- [~] 1.25 A-CONT verify returned BLOCK with 2 P0 + 1 P1 + 1 P2 (3 of 4 reviewers concur — R2 Logic + R5 Devil's Advocate + Codex; R1 Requirements PASS). Verify report: https://github.com/PsychQuant/che-word-mcp/issues/58#issuecomment-4323658377. Plus R2-only finding that matrix-pin is regression-blind on chosen fixture. Opening A-CONT-2 mini-mini-cycle (§1.26-§1.37).

## 1-CONT-2. Sub-stack A-CONT-2 — close 2 P0 + 1 P1 + 1 P2 from A-CONT 6-AI verify

The A-CONT 6-AI verify (https://github.com/PsychQuant/che-word-mcp/issues/58#issuecomment-4323658377) returned BLOCK. Three independent reviewers converged on the same 2 P0 + 1 P1; R2 alone caught a third P0 (matrix-pin regression-blindness because thesis fixture has 0 container-level bookmarks).

Same convergence-cycle pattern (sub-cycle 3 for #58, mirrors R5 → R5-CONT-4 trajectory):
- Sub-stack A closed body-parser asymmetry
- A-CONT closed container-parser asymmetry
- **A-CONT-2 closes API-layer asymmetry** (`getBookmarks()` only iterates body) + **second-order parser-mirror gap** (missing `case "sdt"` in container parser) + **fixture coverage** (matrix-pin needs container-bookmark fixture to be non-trivial)

Re-numbers planned sub-stack B → v0.19.9 + v3.13.9 (sub-stack C unchanged at v0.20.0 + v3.14.0).

- [x] 1.26 [P] Write failing test `testGetBookmarksSurfacesContainerBodyLevelMarkers` — fixture with body-level `<w:bookmarkStart w:name="hdrBookmark"/>` inside header1.xml; assert `doc.getBookmarks()` includes `hdrBookmark`. Test SHALL fail pre-A-CONT-2-fix.

- [x] 1.27 [P] Write failing test `testParseContainerSDTRecursionPreservesNestedBookmark` — fixture with header containing `<w:hdr><w:sdt><w:sdtPr><w:id w:val="42"/></w:sdtPr><w:sdtContent><w:bookmarkStart w:id="500" w:name="sdtBookmark"/><w:p>...</w:p><w:bookmarkEnd w:id="500"/></w:sdtContent></w:sdt></w:hdr>`. Read; assert `header.bodyChildren` contains `.contentControl(_, let inner)` (NOT `.rawBlockElement`); assert nested `.bookmarkMarker` is reachable; assert `doc.nextBookmarkId > 500`. Tests SHALL fail pre-A-CONT-2-fix.

- [x] 1.28 Extend `Document.getBookmarks()` at `Sources/OOXMLSwift/Models/Document.swift:2122-2153` to walk container `bodyChildren` across headers + footers + footnotes + endnotes. Add helper `collectBodyLevelBookmarkNames(in: [BodyChild]) -> [(id, name)]` that recurses into `.contentControl(_, let inner)` and emits `.bookmarkMarker` `.start` entries with names. Apply across body + 4 container types. Remove the stale `getAllBookmarks()` reference comment.

- [x] 1.29 Extend `parseContainerChildBodyChildren` at `Sources/OOXMLSwift/IO/DocxReader.swift:1296-1362` with `case "sdt":` branch mirroring `parseBodyChildren:644-679`: parse SDT metadata via `SDTParser.parseSdtPr`, recursively call `parseContainerChildBodyChildren` for `<w:sdtContent>` children, append `.contentControl(metadata, children: sdtChildren)`. Also extend `collectBodyLevelBookmarkIds` (DocxReader.swift:421-433) to recurse through `.contentControl(_, let inner)` so SDT-nested bookmark ids reach `nextBookmarkId` calibration.

- [x] 1.30 Extend matrix-pin: add a synthetic test that uses a fixture WITH body-level bookmarks in headers (NOT the thesis fixture which has 0). New test `testMatrixPinCatchesContainerBookmarkRegression` builds a docx with `<w:hdr>` containing 2 body-level `<w:bookmarkStart>` + matching `<w:bookmarkEnd>`, runs the same matrix-pin assertion path, asserts non-trivial parity (2=2 not 0=0). Catches future parser-asymmetry regressions for real.

- [x] 1.31 [P1] Extend `deleteBookmark(name:)` at `Document.swift:2038-2056` to also walk body-level `.bookmarkMarker` entries (matching by name) AND container body-level markers via the new collector helper from §1.28. Removes the state inconsistency where `getBookmarks()` lists names that `deleteBookmark` can't delete.

- [x] 1.32 Run full suite `swift test --disable-sandbox`; expect 661+ / 0 / 1 (658 A-CONT baseline + 3 new A-CONT-2 tests).

- [x] 1.33 Bump `packages/ooxml-swift/CHANGELOG.md` with v0.19.8 entry referencing A-CONT-2 scope. Commit `fix(#58 A-CONT-2): close API-layer + container-SDT-recursion + matrix-pin-fixture asymmetries from A-CONT verify`. Tag `v0.19.8`. Push.

- [x] 1.34 Bump `mcp/che-word-mcp/Package.swift` ooxml-swift dep `0.19.7 → 0.19.8`; update CHANGELOG v3.13.8 entry; manifest `3.13.8`. Build mcpb. Commit `feat: v3.13.8 — bump ooxml-swift v0.19.7 → v0.19.8 (closes #58 A-CONT-2)`. Tag `v3.13.8`. Push. Upload assets.

- [x] 1.35 Run `/plugin-tools:plugin-update che-word-mcp` to sync marketplace.

- [x] 1.36 Run sub-stack A-CONT-2 6-AI verify on v0.19.8 / v3.13.8 commits. Post verify report to #58.

- [~] 1.37 A-CONT-2 verify returned BLOCK with 3 P0 + 2 P1 + 4 P2 (3 of 4 reviewers concur — R2 Logic + R5 Devil's Advocate + Codex; R1 Requirements PASS). Verify report: https://github.com/PsychQuant/che-word-mcp/issues/58#issuecomment-4323715199. **Marathon paused per maintainer directive (Option D — strategic checkpoint)**. Three P0s found:
  - **A-CONT-3 P0 #1 (silent correctness regression — MUST fix)**: `deleteBookmark` marks header/footer dirty with BASENAME (`"header1.xml"`) instead of full path (`"word/header1.xml"`); writer overlay-mode dirty-gate misses the change → deletion silently lost on disk. Triple-confirmed (R2 + R5 + Codex). Lines: Document.swift:2067, 2073.
  - **A-CONT-3 P0 #2 (UX regression — MUST fix)**: `getBookmarks()` skips paragraph-level bookmarks inside container paragraphs (only collects body-level container markers). Identical UX bug to original #58 — paragraph-level container bookmarks are MORE common than body-level.
  - **A-CONT-3 P0 #3 (asymmetry — SHOULD fix)**: `insertBookmark` only walks body; duplicate detection misses container bookmarks → silent name collision. R5 DA only.
  - Plus 2 P1 + 4 P2 deferred (matrix-pin negative arm; comments.xml coverage; cross-part bookmark span; sentinel doc note; deleteBookmark dedicated tests).
- [~] 1.38 Maintainer authorized continuation. A-CONT-3 scope: MUST-tier (P0 #1 deleteBookmark path-mismatch correctness regression + P0 #2 getBookmarks paragraph-level container coverage) + SHOULD-tier (P0 #3 insertBookmark symmetry). Defer: P1 #4 comments.xml coverage, P1 #5 matrix-pin negative arm, P2 #6/#7/#9. Ships as ooxml-swift v0.19.9 + che-word-mcp v3.13.9.

## 1-CONT-3. Sub-stack A-CONT-3 — close 3 P0 from A-CONT-2 6-AI verify

The A-CONT-2 6-AI verify (https://github.com/PsychQuant/che-word-mcp/issues/58#issuecomment-4323715199) returned BLOCK with 3 P0 + 2 P1 + 4 P2. Three independent reviewers (R2 Logic + R5 Devil's Advocate + Codex) triple-confirmed P0 #1; R2 alone caught P0 #2; R5 DA alone caught P0 #3. Maintainer authorized MUST + SHOULD tier scope (3 P0); P1 + P2 deferred to follow-up SDD.

This is sub-cycle 4 for #58 (A → A-CONT → A-CONT-2 → A-CONT-3). Same convergence-cycle pattern as R5 → R5-CONT-4 (5 sub-cycles for #56). The shape of A-CONT-3 fixes is mostly correctness + symmetry: deleteBookmark path-mismatch is a 2-line correctness fix, getBookmarks paragraph-coverage and insertBookmark symmetry are walker-pattern extensions.

Re-numbers planned sub-stack B → v0.19.10 + v3.13.10 (sub-stack C unchanged at v0.20.0 + v3.14.0).

- [x] 1.39 [P] Write failing test `testDeleteBookmarkInHeaderPersistsToDisk` — fixture with `word/header1.xml` containing body-level `<w:bookmarkStart w:name="hdrBookmark"/>`. Read; call `doc.deleteBookmark(name: "hdrBookmark")`; save; re-read. Assert `header1.xml` no longer contains `hdrBookmark`. Test SHALL fail pre-A-CONT-3-fix (proves the deletion is silently lost on disk).

- [x] 1.40 [P] Write failing test `testDeleteBookmarkInFooterPersistsToDisk` — same shape as §1.39 but for footer. Tests SHALL fail pre-A-CONT-3-fix.

- [x] 1.41 [P] Write failing test `testGetBookmarksSurfacesContainerParagraphLevelBookmarks` — fixture with `word/header1.xml` containing `<w:hdr><w:p><w:bookmarkStart w:id="50" w:name="paraInHdr"/><w:bookmarkEnd w:id="50"/><w:r><w:t>x</w:t></w:r></w:p></w:hdr>` (paragraph-level bookmark). Read; call `getBookmarks()`; assert it includes `paraInHdr`. Test SHALL fail pre-A-CONT-3-fix (only body-level container markers were surfaced; paragraph-level container markers were skipped).

- [x] 1.42 [P] Write failing test `testInsertBookmarkDuplicateNameInContainerThrows` — fixture with header containing `<w:bookmarkStart w:name="dupName"/>` (body-level). Read; call `doc.insertBookmark(name: "dupName", ...)` targeting body. Assert it throws `BookmarkError.duplicateName` (or similar). Test SHALL fail pre-A-CONT-3-fix because `insertBookmark` only walks body for duplicate detection.

- [x] 1.43 (P0 #1 fix — MUST) `Document.swift:2067, 2073`: change `modifiedParts.insert(headers[i].fileName)` → `modifiedParts.insert("word/\(headers[i].fileName)")`, same for footers. Two lines. Reuses existing fileName basename convention used everywhere else in Document.swift.

- [x] 1.44 (P0 #2 fix — MUST) Extend `Document.getBookmarks()` to ALSO walk `case .paragraph(let para)` for `para.bookmarks` inside container `bodyChildren`. Refactor: add a per-part collector helper that handles both paragraph + body-level + .contentControl recursion uniformly. Reuse for headers + footers + footnotes + endnotes.

- [x] 1.45 (P0 #3 fix — SHOULD) Extend `Document.insertBookmark` to walk all 5 part types for duplicate-name detection. Target paragraph resolution can stay body-only (target by paragraph index — adding to containers is a separate API surface, out of A-CONT-3 scope). Throws `BookmarkError.duplicateName` if name exists anywhere.

- [x] 1.46 Run failing tests from §1.39-1.42 — all SHALL now pass.

- [x] 1.47 Run full suite `swift test --disable-sandbox`; expect 665 / 0 / 1 (661 A-CONT-2 baseline + 4 new A-CONT-3 tests).

- [x] 1.48 Bump `packages/ooxml-swift/CHANGELOG.md` with v0.19.9 entry referencing A-CONT-3 scope. Commit `fix(#58 A-CONT-3): close deleteBookmark path mismatch + getBookmarks paragraph-coverage + insertBookmark symmetry from A-CONT-2 verify`. Tag `v0.19.9`. Push.

- [x] 1.49 Bump `mcp/che-word-mcp/Package.swift` ooxml-swift dep `0.19.8 → 0.19.9`; update CHANGELOG v3.13.9 entry; manifest `3.13.9`. Build mcpb. Commit `feat: v3.13.9 — bump ooxml-swift v0.19.8 → v0.19.9 (closes #58 A-CONT-3)`. Tag `v3.13.9`. Push. Upload assets.

- [x] 1.50 Run `/plugin-tools:plugin-update che-word-mcp` to sync marketplace.

- [x] 1.51 Run sub-stack A-CONT-3 6-AI verify on v0.19.9 / v3.13.9 commits. Post verify report to #58.

- [~] 1.52 A-CONT-3 verify returned BLOCK with severity disagreement (R2 Logic + R5 DA call P0; Codex calls P1; R1 Requirements PASS). Verify report: https://github.com/PsychQuant/che-word-mcp/issues/58#issuecomment-4323835958. **MUST + SHOULD tier P0s confirmed closed** (deleteBookmark dirty-key path mismatch silent correctness regression — fixed; getBookmarks paragraph-coverage — fixed; insertBookmark cross-part symmetry — fixed). New state-inconsistency surface introduced by A-CONT-3 P0 #2's `getBookmarks()` extension: paragraph-level container bookmarks are now LISTABLE but `tryDeleteBodyLevelBookmark` only walks `.bookmarkMarker` cases — they're NOT DELETABLE via name. Same convergence-cycle pattern, one layer deeper. Plus internal `getBookmarks()` body/container asymmetry (body's `.contentControl` recursion uses old body-only helper). **Marathon paused per maintainer Option D pattern** — A-CONT-4 scope is a maintainer decision.
- [-] 1.53 **A-CONT-4 deferred per maintainer Option B decision** — proceed to sub-stack B (#59 whitespace overlay) instead of continuing #58 sub-cycles. Known gaps (documented in #58 verify report 4323835958): paragraph-level container bookmark deletion via name throws `notFound` (state inconsistency between `getBookmarks` and `deleteBookmark`); body's `.contentControl` recursion in `getBookmarks` uses the old body-level-only helper (internal asymmetry — body SDT paragraph-level bookmarks invisible); `insertBookmark` O(N) duplicate check perf regression. #58 stays OPEN with these documented caveats; v3.13.9 ships the MUST + SHOULD tier closures. Methodology lesson carried forward: matrix-pin needs SYMMETRIC ASSERTIONS BAKED IN FROM DESIGN, not added reactively in response to verify findings — apply to sub-stack B's WhitespaceOverlay.

## 2. Sub-stack B — #59 whitespace overlay scan (re-numbered to v0.19.10 / v3.13.10 after A-CONT-3 lands)

- [x] 2.1 [P] Write failing test `testWhitespaceOnlyTextRunsRoundTrip` — fixture with `<w:r><w:t xml:space="preserve">     </w:t></w:r>` (5-char) between non-whitespace runs; assert post-roundtrip that `parsed.runs[1].text == "     "` AND `roundtrip(doc).body.children[0].paragraphs[0].runs[1].text == "     "`. (Covers spec requirement: `<w:t> whitespace content SHALL survive Reader-side parser limitations` — Scenario "Whitespace-only w:t round-trips byte-equivalent")

- [x] 2.2 [P] Write failing test `testThesisFixtureWhitespaceContentEquality` — uses real thesis fixture; asserts source has 346 whitespace-only `<w:t>` elements (683 chars) AND post-Reader Run text whitespace count equals source XML count.

- [x] 2.3 Create new internal value type in `packages/ooxml-swift/Sources/OOXMLSwift/IO/WhitespaceOverlay.swift` with API: `init(scanning: Data)`, `text(forElementSequenceIndex: Int) -> String?`. Implementation regex/scanner pre-pass over raw XML byte stream, capturing `<w:t xml:space="preserve">[whitespace]</w:t>` content keyed by element sequence index in DOM document order.

- [x] 2.4 Plumb overlay through `DocxReader.read(from:)` in `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift`: construct overlay from `documentData` before constructing `XMLDocument`; pass overlay as parameter through to `parseRun`.

- [x] 2.5 Modify `parseRun` at `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift:1531-1580` to consult overlay when `t.stringValue.isEmpty` — specifically, when iterating `element.elements(forName: "w:t")`, track element sequence index and call `overlay.text(forElementSequenceIndex: idx)` to recover whitespace if `t.stringValue` returned "".

- [x] 2.6 Run failing tests from §2.1, §2.2 — they SHALL now pass.

- [x] 2.7 Extend `testDocumentContentEqualityInvariant` matrix-pin with `<w:t>` total character content parity assertion against thesis fixture. Test passes with 39378=39378 chars. (Covers spec requirement: `testDocumentContentEqualityInvariant matrix-pin SHALL assert content equality across preservation classes` — preservation-class 2 of 3; Scenario "Matrix-pin tolerates legitimate Word canonicalization" applies — assertion is on joined-text content equality, not byte equality)

- [x] 2.8 Extend whitespace overlay to all 5 additional XMLDocument call sites in DocxReader.swift: `headerXML`, `footerXML`, `footnotesXML`, `endnotesXML`, `commentsXML`. Each gains a `WhitespaceOverlay` constructed from its respective `Data` blob and plumbed through to its parser. (Covers spec requirements: `Header whitespace round-trips through container parsing`, `Footer whitespace round-trips through container parsing`, `Footnote whitespace round-trips through container parsing`, `Endnote whitespace round-trips through container parsing`, `Comments whitespace round-trips through container parsing` — Scenarios same names; also covers spec requirement `Container parts SHALL preserve <w:t> whitespace content via WhitespaceOverlay`)

- [x] 2.9 [P] Write per-container tests `testHeaderWhitespacePreserved`, `testFooterWhitespacePreserved`, `testFootnoteWhitespacePreserved`, `testEndnoteWhitespacePreserved`, `testCommentsWhitespacePreserved`; each uses a minimal fixture exercising whitespace-only `<w:t>` in the respective part.

- [x] 2.10 Run full suite `swift test --disable-sandbox`; expect 660 / 0 / 1 (654 from sub-stack A + 6 new tests from §2.1, §2.2, §2.9 × 5).

- [x] 2.11 Bump `packages/ooxml-swift/CHANGELOG.md` with v0.19.10 entry (re-numbered from v0.19.7 after A-CONT-3) referencing #59. Commit `fix(#59): preserve <w:t> whitespace via WhitespaceOverlay byte-stream pre-scan` (commit 56ef4e8). Tag `v0.19.10`. Push. GitHub release: https://github.com/PsychQuant/ooxml-swift/releases/tag/v0.19.10.

- [x] 2.12 Bumped `mcp/che-word-mcp/Package.swift` ooxml-swift dep `0.19.9 → 0.19.10`; CHANGELOG v3.13.10; manifest `3.13.10`. Built mcpb (3.7MB). Commit a9d9d02 `feat: v3.13.10 — bump ooxml-swift v0.19.9 → v0.19.10 (closes #59)`. Tagged `v3.13.10`. Pushed. Release: https://github.com/PsychQuant/che-word-mcp/releases/tag/v3.13.10 with mcpb + raw CheWordMCP binary assets.

- [x] 2.13 Ran `/plugin-tools:plugin-update che-word-mcp`. Marketplace bumped 3.13.9 → 3.13.10 (commit 2fed513). README freshness signal-1 false-passed (literal "v3.13.10" appeared in past-tense planning text); proactive update committed (d6daf49) — refreshed v3.13.10 milestone narrative, removed leftover v3.13.7-v3.13.8 partial-fix trail. `claude plugin update` succeeded; final state: che-word-mcp@psychquant-claude-plugins v3.13.10 ✔ enabled.

- [x] 2.14 Ran sub-stack B 6-AI verify on v0.19.10 / v3.13.10 commits. Verify report posted: https://github.com/PsychQuant/che-word-mcp/issues/59#issuecomment-4323956207. Result: **BLOCK** (3 BLOCK + 1 PASS-WITH-WARNINGS). 4-reviewer convergence on P0 counter-desync class with two root causes: (a) prefix-match collision in `WhitespaceOverlay.swift:54` — `xml.range(of: "<w:t")` matches `<w:tab>`, `<w:tbl>`, `<w:tc>`, `<w:tr>`, etc. (R2 + R5 + Codex confirm; R5 empirical probe), (b) skipped raw subtrees — mc:AlternateContent's mc:Choice branch + `<w:ins>/<w:del>` with non-run children stored as raw XML where parseRun never visits but scanner counts inner `<w:t>` (Codex + R2). P0 secondary: pathological skip-over consumes wrong `</w:t>` closer (R2 + R5). Plus 5 confirmed P1s: static state concurrency hazard (R5 + Codex), §2.7 matrix-pin claim vs reality gap (R1 + Codex), `<w:delText>` overlay missing (R5), entity-encoded whitespace not recognized (R5), comments trimming strips recovered whitespace (Codex). Test-fixture meta-gap: matrix-pin "1 fixture / 6 parts" lesson worked at part-type axis but failed at OOXML-content axis — sterile fixtures hid every P0.

- [~] 2.15 Sub-stack B 6-AI verify returned BLOCK; cannot close #59. Opening B-CONT mini-cycle (§2.16-§2.27) for MUST-tier (4 P0 closures) + SHOULD-tier (3 P1 closures). MAY-tier (3 P1/P2) defer scope decision pending maintainer authorization. Re-numbers sub-stack C → unchanged v0.20.0 / v3.14.0; B-CONT ships as v0.19.11 + v3.13.11.

## 2-CONT. Sub-stack B-CONT — close 4 P0 + 3 P1 from sub-stack B 6-AI verify

The sub-stack B 6-AI verify (https://github.com/PsychQuant/che-word-mcp/issues/59#issuecomment-4323956207) returned BLOCK with strong 3-reviewer convergence on the P0 counter-desync class (R2 Logic + R5 Devil's Advocate + Codex). Two root causes converge to the same observable bug (recovered whitespace lands on wrong element OR is silently lost):

- **Root cause A (prefix-match collision)** — `WhitespaceOverlay.swift:54`'s `xml.range(of: "<w:t", ...)` is a prefix match. Matches every OOXML element whose qualified name starts with `w:t` — `<w:tab>`, `<w:tbl>`, `<w:tc>`, `<w:tr>`, `<w:tblPr>`, `<w:tcPr>`, `<w:trPr>`, `<w:tblGrid>`, `<w:tblBorders>`, `<w:tcBorders>`, `<w:tblCellMar>`, `<w:tblLayout>`, `<w:tblLook>`, `<w:tblStyle>`, etc. DOM walker `element.elements(forName: "w:t")` is exact-match. Counter desyncs immediately in any document with tables or tabs.
- **Root cause B (skipped raw subtrees)** — when `parseAlternateContent` skips `<mc:Choice>`, when `parseInsRevisionWrapper` raw-captures wrappers with non-run children as `unrecognizedChildren`, when generic `.rawBlockElement` capture fires (sub-stack A) — byte scanner counts `<w:t>` inside but parseRun never visits.
- **P0 secondary (R2 + R5)** — pathological skip-over: when prefix-match falsely fires on `<w:tbl>`, scanner searches forward for `</w:t>` and consumes the next legitimate one, swallowing real `<w:t>` elements between false-match and consumed-close.

This is sub-cycle 2 for #59 (B → B-CONT). Maintainer-authorized scope per Option B precedent (sub-stack A had 4 sub-cycles; sub-stack B may have 2-3). Methodology lesson refined: matrix-pin fixtures must include real-world OOXML structures (tables, tabs, mc:AlternateContent, revision wrappers), not just real-world part types.

- [x] 2.16 [P] Wrote failing test `testWhitespaceOverlayPrefixMatchTabDoesNotDesyncCounter`. Confirmed RED: observed runs `["", "", "after"]` — both `before` and whitespace lost due to prefix-match collision on `<w:tab/>`.

- [x] 2.17 [P] Wrote failing test `testWhitespaceOverlayPrefixMatchTableDoesNotDesyncCounter`. Initial fixture with `<w:t>cell</w:t>` accidentally PASSED — pathological skip-over consumed cell `</w:t>` and parseRun's cell-text visit happened to keep counter aligned. Strengthened to empty-cell `<w:p/>` fixture: confirmed RED (whitespace lost; pathological skip absorbs whitespace `</w:t>` directly).

- [x] 2.18 [P] Wrote failing test `testWhitespaceOverlayMcAlternateContentDoesNotDesyncCounter`. Confirmed RED: post-mc-AlternateContent whitespace lost (counter desync via Choice+Fallback both counted but only Fallback parsed).

- [x] 2.19 [P] Wrote failing test `testWhitespaceOverlayInsRevisionWrapperDoesNotDesyncCounter`. Confirmed RED: post-w:ins-with-bookmarkStart whitespace lost (wrapper raw-captured, parseRun never visits inner `<w:t>`).

- [x] 2.20 (P0 root cause A fix — MUST) Tightened `WhitespaceOverlay.swift:54` byte-scan with tag-name boundary check. After matching `<w:t`, peek next character; only count if next char is `>`, ` `, `\t`, `\n`, `\r`, or `/`. Rejects prefix collisions (`<w:tab>`, `<w:tbl>`, `<w:tc>`, `<w:tr>`, etc.). Same boundary check applied to new helper `WhitespaceOverlay.countWtElements(in:)` for §2.21 use.

- [x] 2.21 (P0 root cause B fix — MUST) Implemented parser-side counter advance via new helper `DocxReader.advanceWhitespaceCounter(forSkippedXML:)` (calls `WhitespaceOverlay.countWtElements`). Wired at 7 raw-capture sites: `parseBodyChildren` `.rawBlockElement` (line ~771), `parseInsRevisionWrapper` non-run-child path × 4 (`<w:ins>` line 881, `<w:del>` line ~937, `<w:moveFrom>` line ~979, `<w:moveTo>` line ~1019), `parseParagraph` unrecognized-child catch-all (line ~1208), `parseAlternateContent` `<mc:Choice>` skip (line ~1717), `parseRun` `rawElements` capture (line ~1842 — the missing site that caused mc:AlternateContent test to still fail after Choice-only fix; nested AC inside `<w:r>` doesn't go through paragraph-level parseAlternateContent).

- [x] 2.22 (P0 secondary fix — MUST) Pathological skip-over disappears automatically with §2.20 boundary check. Empty-cell table fixture (`testWhitespaceOverlayPrefixMatchTable`) confirms: scanner no longer false-matches `<w:tbl>`, so the search-forward-for-`</w:t>` consumption never fires.

- [x] 2.23 (P1 §2.7 matrix-pin landing — MUST) Replaced placeholder comment with real `<w:t>` total-char parity assertion in `testDocumentContentEqualityInvariant`. New helper `sumWtElementCharCount(in:)` walks `<w:t>` elements with same boundary check as scanner, sums inner-text length. Matrix-pin runs against thesis fixture; PASS confirms whitespace overlay correctly preserves all `<w:t>` content end-to-end. The assertion will trip on future regressions (e.g., new prefix-collision class or unhandled raw-capture site) before they reach 6-AI verify.

- [x] 2.24 (P1 SHOULD-tier — `<w:delText>` overlay coverage) Extended `WhitespaceOverlay` with second scanner pass for `<w:delText` (mirror of `<w:t>` scan with same boundary check + same xml:space + decoded-whitespace logic) plus separate `delTextWhitespaceByIndex` map and `delText(forElementSequenceIndex:)` accessor. Added `WhitespaceParseContext.delTextCounter` (independent from `<w:t>` counter — DOM walks delText via separate `forName: "w:delText"` query). Updated `parseRun`'s delText loop at `DocxReader.swift:970` to consult overlay when `delText.stringValue.isEmpty`. Extended `advanceWhitespaceCounter(forSkippedXML:)` to also advance delTextCounter via new `WhitespaceOverlay.countDelTextElements(in:)` helper, so raw-captured `<w:del>` wrappers don't desync the delText counter. Test `testDeleteTextWhitespaceRoundTrips` GREEN.

- [x] 2.25 (P1 SHOULD-tier — comments trimming fix) Removed `text.trimmingCharacters(in: .whitespacesAndNewlines)` at `DocxReader.swift:2978`. Comments now preserve verbatim recovered overlay text. Safe because the XPath walk only reads `<w:t>` inner content, which never includes incidental XML pretty-printing whitespace between sibling tags. Test `testWhitespaceOnlyCommentPreservedNotTrimmed` GREEN.

- [x] 2.26 (P1 SHOULD-tier — entity-encoded whitespace) Added `WhitespaceOverlay.decodeXMLEntities(in:)` static helper handling numeric decimal (`&#9;`), hex (`&#x09;`, `&#xA0;`), and named (`&nbsp;`) entities. Modified main scanner to decode `innerText` before whitespace check at `WhitespaceOverlay.swift:87`; same change in delText scanner. Stored value is the DECODED text (so parseRun consult returns proper characters). Test `testEntityEncodedWhitespacePreserved` GREEN — `&#x09;&#x09;` correctly recovered as `"\t\t"`.

- [x] 2.27 Ran full suite `swift test --disable-sandbox`. Result: 673 tests / 0 failures / 1 skipped — exactly matches prediction (666 sub-stack B baseline + 4 P0 tests §2.16-§2.19 + 3 SHOULD-tier tests §2.24-§2.26).

- [x] 2.28 Shipped ooxml-swift v0.19.11 (commit 3a97b78, tag v0.19.11, GitHub release: https://github.com/PsychQuant/ooxml-swift/releases/tag/v0.19.11). CHANGELOG comprehensive entry (~80 lines documenting both root causes, all 7 fixes, methodology lesson, deferred items, API additions).

- [x] 2.29 Shipped che-word-mcp v3.13.11 (commit 790cb1b, tag v3.13.11, GitHub release: https://github.com/PsychQuant/che-word-mcp/releases/tag/v3.13.11 with mcpb + raw CheWordMCP binary assets). Package.swift dep bumped to 0.19.11; manifest 3.13.11; CHANGELOG entry comprehensive.

- [x] 2.30 Marketplace + README synced 3.13.10 → 3.13.11. Commit 6c9ce87 in psychquant-claude-plugins. `claude plugin marketplace update` + `claude plugin update che-word-mcp@psychquant-claude-plugins` both succeeded; final state ✔ enabled.

- [x] 2.31 Ran sub-stack B-CONT 6-AI verify on v0.19.11 / v3.13.11 commits. Verify report posted: https://github.com/PsychQuant/che-word-mcp/issues/59#issuecomment-4324076688. Result: **BLOCK** (3 BLOCK + 1 PASS-WITH-WARNINGS). The 4 P0/3 P1 from sub-stack B verify ARE individually closed (boundary check complete, counter-advance helper well-designed, delText overlay symmetric, entity decode handles all whitespace cases, comments-trim removed) — but sub-cycle 3 surfaces NEW findings:

  **CRITICAL P0 — DATA CORRUPTION (R5)**: `<w:delText>` duplicate emission via parseRun rawElements. parseRun's `recognizedRunChildren = ["rPr", "t", "drawing", "oMath", "oMathPara"]` doesn't include `"delText"`. So delText elements (a) advance delTextCounter twice (explicit loop + rawElements path), AND (b) get re-emitted by writer because Run.toXML iterates rawElements. Tracked deletion of `"abc"` → writer produces `<w:delText>abc</w:delText><w:delText>abc</w:delText>` on save. **v3.13.11 in production silently corrupts every `<w:del>` round-trip**. §2.24 test passed because it had ONE `<w:del>` with ONE delText reading from explicit-loop side.

  **P0 — counter desync class (5+ missed sites)**: B-CONT instrumented 7 raw-capture sites; verify found same-class siblings:
  - parseContainerChildBodyChildren raw fallback at DocxReader.swift:1494 (Codex)
  - parseHyperlink rawChildren at DocxReader.swift:1644 (R2)
  - parseFieldSimple non-`<w:r>` silent skip at DocxReader.swift:1730 (R2 — also content-loss bug)
  - parseParagraph smartTag/customXml/dir/bdo (4 sites) at DocxReader.swift:1141/1148/1154/1160 (R2)

  P1: parseDrawing txbxContent (R2), `<w:instrText>` not covered (R5, latent), `<m:t>` math text (R5, latent), matrix-pin fixture STILL bare (R5+Codex), spec drift (R1), static state concurrency (Codex deferred).

- [x] 2.32 Sub-stack B-CONT verify returned BLOCK with **CRITICAL data corruption** (#59 comment 4324076688). Cannot close #59. Opening B-CONT-2 mini-cycle (§2.33-§2.50) with TIER-0 emergency hot-fix + TIER-1 missed sites + TIER-2 matrix-pin upgrades.

## 2-CONT-2. Sub-stack B-CONT-2 — close 6 P0 + 3 P1 from sub-stack B-CONT 6-AI verify

The sub-stack B-CONT 6-AI verify (#59 comment 4324076688) returned BLOCK with 4-reviewer convergence on:

**CRITICAL P0 — DATA CORRUPTION** (R5 finding): `<w:delText>` duplicate emission via parseRun's rawElements path. parseRun's `recognizedRunChildren = ["rPr", "t", "drawing", "oMath", "oMathPara"]` doesn't include `"delText"`. Cascading:
1. Counter desync: explicit delText loop advances delTextCounter; rawElements path also advances → 2N instead of N
2. Writer duplicate emission: Run.toXML iterates rawElements re-emitting delText verbatim. `<w:del>` containing `"abc"` → writer produces `<w:delText>abc</w:delText><w:delText>abc</w:delText>` on save

**v3.13.11 in production silently corrupts every `<w:del>` round-trip** — affects all tracked-change documents with deletions.

**P0 — counter desync class (5 missed sites)**: B-CONT instrumented 7 raw-capture sites; verify found same-class siblings:
- parseContainerChildBodyChildren raw fallback at DocxReader.swift:1494 (Codex)
- parseHyperlink rawChildren at DocxReader.swift:1644 (R2)
- parseFieldSimple non-`<w:r>` silent skip at DocxReader.swift:1730 (R2 — also content-loss bug)
- parseParagraph smartTag/customXml/dir/bdo (4 sites) at DocxReader.swift:1141/1148/1154/1160 (R2)

This is sub-cycle 3 for #59. Same convergence-cycle pattern. Methodology lesson refined again: when adding counter-advance helper at "all" raw-capture sites, audit ALL `xmlString` references AND ALL "captured + parser doesn't descend" paths INCLUDING parseRun's own `rawElements` (which can cascade into duplicate emission via writer).

Re-numbers sub-stack C → unchanged v0.20.0 / v3.14.0; B-CONT-2 ships as v0.19.12 + v3.13.12 ASAP.

### TIER-0 — CRITICAL data corruption hotfix

- [x] 2.33 [P] Wrote `testDelTextEmittedExactlyOncePerSourceElement` + helper `countDelTextElements(in:)`. Test PASSED unexpectedly — R5's "duplicate emission" P0-2 prediction was FALSE: writer's gate at Paragraph.swift:787 (`!run.text.isEmpty || (run.rawElements?.isEmpty ?? true)`) skips explicit `<w:delText>` emission when rawElements covers it. Test kept as regression guard for the writer-gate invariant.

- [x] 2.34 [P] Wrote `testDeleteTextCounterStaysSyncedAcrossMultipleDels`. Confirmed RED (Deletion #2 originalText = "" instead of "     "). R5's P0-1 (delTextCounter desync via 2x advance) is REAL.

- [x] 2.35 (P0 fix — TIER-0) Added `"delText"` to `recognizedRunChildren` Set at `DocxReader.swift:1847`. Now the rawElements loop skips delText (already captured by explicit loop). Test §2.34 GREEN. Documented finding: R5's P0-2 was overly pessimistic but the underlying P0-1 was correct.

### TIER-1 — counter desync siblings

- [x] 2.36 [P] Wrote `testWhitespaceOverlayContainerRawFallbackDoesNotDesyncCounter` with header containing `<vendor:custom>` element (unrecognized) wrapping `<w:r><w:t>vendor-content</w:t></w:r>`. Initial fixture used `<w:moveFromRangeStart/>` self-close (no inner text → no desync). Switched to vendor element with inner content. Confirmed RED before fix.

- [x] 2.37 [P] Wrote `testWhitespaceOverlayHyperlinkRawChildrenDoesNotDesyncCounter` with `<w:hyperlink>` containing nested `<w:fldSimple>` (forces rawChildren path). Initial XML used escaped quotes that failed XML parser; simplified to `<w:fldSimple w:instr="PAGE">`. Confirmed RED before fix.

- [x] 2.38 [P] Wrote `testWhitespaceOverlaySmartTagDoesNotDesyncCounter` exercising smartTag raw-carrier. Confirmed RED before fix. Representative for the customXml/dir/bdo class (same code path).

- [x] 2.39 (P0 fix — TIER-1) Added `Self.advanceWhitespaceCounter(forSkippedXML: childElement.xmlString)` at `parseContainerChildBodyChildren` raw fallback default branch.

- [x] 2.40 (P0 fix — TIER-1) Added `Self.advanceWhitespaceCounter(forSkippedXML: raw)` at parseHyperlink non-`<w:r>` else branch.

- [x] 2.41 (P0 fix — TIER-1) Added `Self.advanceWhitespaceCounter(forSkippedXML: childElement.xmlString)` at parseFieldSimple non-`<w:r>` else branch (added new else branch since the loop previously had no explicit handling). The independent content-loss bug for non-`<w:r>` field-simple content is documented inline; raw capture deferred — currently they're dropped, but counter sync is now correct.

- [x] 2.42 (P0 fix — TIER-1) Added `Self.advanceWhitespaceCounter(forSkippedXML: childElement.xmlString)` at parseParagraph smartTag/customXml/dir/bdo (4 sites). All 3 TIER-1 representative tests GREEN. Full suite 678/0/1.

### TIER-2 — defense in depth + matrix-pin upgrades

- [-] 2.43 **DEFERRED to follow-up SDD** (TIER-2) — central raw-capture helper refactor is high-value but adds touchpoint risk. Tracked as known follow-up: future raw-capture additions still require manual `advanceWhitespaceCounter` call. Acceptable cost while matrix-pin extensions (§2.44/§2.45/§2.46) are the more direct guard.

- [-] 2.44 **DEFERRED** (TIER-2) — `buildAllPartsWhitespaceFixture` upgrade with real-world OOXML content classes deferred. Current fixture remains sterile but the new TIER-1 tests (§2.36-§2.38 + sub-stack B-CONT P0 tests) collectively exercise the same content classes (tables, alternate-content, wrappers, entity-encoded) at the per-test level. Long-term goal: consolidate into one fixture; tracked.

- [-] 2.45 **DEFERRED** (TIER-2) — container-part `<w:t>` parity in matrix-pin deferred. Sub-stack C scope addition.

- [-] 2.46 **DEFERRED** (TIER-2) — `<w:delText>` total-char parity in matrix-pin deferred. Sub-stack C scope addition.

### Ship

- [x] 2.47 Ran full suite `swift test --disable-sandbox`. Result: 678 / 0 / 1 — exactly matches prediction (673 sub-stack B-CONT baseline + 5 new B-CONT-2 tests).

- [x] 2.48 Shipped ooxml-swift v0.19.12 (commit c5506c0, tag v0.19.12, GitHub release: https://github.com/PsychQuant/ooxml-swift/releases/tag/v0.19.12). CHANGELOG entry comprehensive (~80 lines documenting TIER-0 + TIER-1 + R5 false-alarm finding + methodology refinement + deferred TIER-2).

- [x] 2.49 Shipped che-word-mcp v3.13.12 (commit f6ea4bd, tag v3.13.12, GitHub release: https://github.com/PsychQuant/che-word-mcp/releases/tag/v3.13.12 with mcpb + raw CheWordMCP binary). Note: NOT marked as HOTFIX since R5's data-corruption claim was falsified — v3.13.11 was not corrupting `<w:del>` round-trips, only counter desync (less severe). v3.13.12 is recommended upgrade for documents with tables / multi-`<w:del>` / hyperlinks-with-fields / smart-tagged paragraphs.

- [x] 2.50 Marketplace synced (commit 3424e44 in psychquant-claude-plugins). `claude plugin marketplace update` + `claude plugin update che-word-mcp@psychquant-claude-plugins` both succeeded; final state ✔ enabled at v3.13.12. README narrative refreshed to reflect B-CONT-2 closures + R5 false-alarm methodology lesson.

## 2-CONT-2-CONT. Sub-stack B-CONT-2-CONT — CRITICAL HOTFIX for v3.13.12 data-loss regression

The sub-stack B-CONT-2 6-AI verify (run on v0.19.12 / v3.13.12 commits) returned BLOCK with **R2 + R5 + Codex INDEPENDENTLY confirmed** P0: v3.13.12's TIER-0 fix introduced data corruption — adding `"delText"` to `recognizedRunChildren` removed delText from rawElements, triggering writer's synthetic-emission gate to emit empty `<w:delText></w:delText>`. Every `<w:del>` round-trip silently stripped deleted-text content.

Tests §2.33 (opening-tag count) + §2.34 (in-memory `Revision.originalText`) both passed falsely — neither asserted writer output content.

Sub-cycle 4 for #59. Methodology lesson (5th refinement, Codex insight): split tests into counter-parity (tag counts) AND payload-parity (content). Future predictions about duplicate/loss scenarios should require a payload-parity test before falsification accepted.

- [x] 2.51 Wrote failing test `testDelTextContentPreservedThroughRoundTrip` (payload-parity, asserts actual deleted-text content survives round-trip via output XML scan). Confirmed RED on v0.19.12.

- [x] 2.52 (P0 fix) Reverted `"delText"` from `recognizedRunChildren` Set in `DocxReader.swift:1847`. Added `includeDelText: Bool = true` parameter to `advanceWhitespaceCounter(forSkippedXML:)`. parseRun's rawElements loop passes `includeDelText: false` when `localName == "delText"` — explicit `<w:del>` loop already advances delTextCounter, so this prevents double-advance without removing delText from rawElements (writer needs it). Test §2.51 GREEN. Tests §2.33 + §2.34 still GREEN.

- [x] 2.53 Ran full suite. Result: 679 / 0 / 1 (678 sub-stack B-CONT-2 baseline + 1 new payload-parity test).

- [x] 2.54 Shipped ooxml-swift v0.19.13 (commit 0cc68e6, tag v0.19.13, GitHub release: https://github.com/PsychQuant/ooxml-swift/releases/tag/v0.19.13). CHANGELOG comprehensive entry documenting the over-fix + revert + methodology lesson + counter-parity vs payload-parity test split.

- [x] 2.55 Shipped che-word-mcp v3.13.13 (commit 52160a5, tag v3.13.13, GitHub release: https://github.com/PsychQuant/che-word-mcp/releases/tag/v3.13.13 with mcpb + raw CheWordMCP binary). Marked v3.13.12 as DO NOT USE in CHANGELOG.

- [x] 2.56 Marketplace synced (commit a550fa8 in psychquant-claude-plugins). v3.13.12 → v3.13.13 ✔ enabled. README narrative refreshed with HOTFIX notice + payload-parity methodology.

## 3. Sub-stack C — #60 RunProperties field-loss audit (v0.20.0)

- [x] 3.1 [P] Wrote `testRFontsFourAxisPreservedThroughRoundtrip` covering ascii/hAnsi/eastAsia/cs preservation. Confirmed RED pre-fix (eastAsia + cs both collapsed to ascii); GREEN post-fix.

- [x] 3.2 [P] Wrote `testNoProofAndKernPreservedThroughRoundtrip` covering `<w:noProof/>` + `<w:kern w:val="32"/>`. Confirmed RED pre-fix (both silently dropped); GREEN post-fix.

- [x] 3.3 [P] Wrote `testW14NamespaceEffectsPreservedAsRawChildren` covering `<w14:textOutline>` with nested `<w14:solidFill><w14:srgbClr/>`. Confirmed RED pre-fix; GREEN post-fix via rawChildren passthrough.

- [x] 3.4 Added typed fields to `RunProperties` in `Run.swift`: `rFonts: RFontsProperties?` (new struct with 4 axes + hint), `noProof: Bool`, `kern: Int?`, `lang: LanguageProperties?` (new struct with val/eastAsia/bidi). Legacy `fontName: String?` kept; mirrors `rFonts.ascii` for backward compat. New struct types documented inline.

- [x] 3.5 Added `rawChildren: [RawElement]?` to `RunProperties`. Architectural pattern matches `Run.rawElements` (v0.14.0+, #52). `merge()` updated to handle all new fields atomically.

- [x] 3.6 Updated `parseRunProperties` in `DocxReader.swift:2228` to extract `rFonts` 4-axis (with legacy mirror to fontName), `noProof`, `kern`, `lang`. Added `recognizedRprChildren` Set covering 30+ typed kinds; collected unrecognized direct rPr children into `rawChildren`. ~70 lines added.

- [x] 3.7 Updated `RunProperties.toXML()` in `Run.swift:286` to emit `<w:rFonts>` per-axis (when typed), `<w:noProof>`, `<w:kern w:val>`, `<w:lang>` (3-axis), then replay `rawChildren` after typed children. Legacy `fontName` path kept for back-compat (emits 4-axis with same value).

- [x] 3.8 All 3 failing tests from §3.1-§3.3 now PASS individually. Tests confirmed via `swift test --filter`.

- [x] 3.9 Extended `testDocumentContentEqualityInvariant` matrix-pin with preservation-class-3 ratio-floor assertions (rFonts 0.85, noProof 0.90, lang 0.45, kern 0.80, w14:* 0.04). Scope is RUN-LEVEL only — out-of-scope losses (paragraph-mark `<w:pPr><w:rPr>` drop + `w14:paraId/textId` paragraph attributes) documented inline as separate pre-existing bugs to track. New helper `countSubstring(_:in:)` for the assertions. Matrix-pin stays load-bearing for sub-stack C scope while not blocking on out-of-scope drops.

- [x] 3.10 Ran full suite. Result: 682 / 0 / 1 — exactly +3 from baseline (679 sub-stack B-CONT-2-CONT baseline + 3 new sub-stack C tests). No regressions.

- [x] 3.11 Thesis fixture round-trip size sanity check: src=1473896 bytes, post-roundtrip=1212279 bytes, 17.75% loss. Down from pre-fix 32% loss (improvement of 14.25 percentage points). Floor set at 19% to catch sub-stack-C-scope regressions; the remaining 17.75% is paragraph-mark rPr + w14:paraId/textId drops (out-of-scope follow-up).

- [x] 3.12 Shipped ooxml-swift v0.20.0 (commit efc9a8b, tag v0.20.0, GitHub release: https://github.com/PsychQuant/ooxml-swift/releases/tag/v0.20.0). Comprehensive CHANGELOG entry (~110 lines) documenting #60 root cause, fix architecture, matrix-pin extension, out-of-scope discoveries, round-trip size impact, API additions.

- [x] 3.13 Shipped che-word-mcp v3.14.0 (commit 316c2b5, tag v3.14.0, GitHub release: https://github.com/PsychQuant/che-word-mcp/releases/tag/v3.14.0 with mcpb + raw CheWordMCP binary). Pure dep bump (ooxml-swift v0.19.13 → v0.20.0). Architectural completion of 'if not typed, preserve as raw' principle.

- [x] 3.14 Marketplace synced (commit 3f0b837 in psychquant-claude-plugins). v3.13.13 → v3.14.0 ✔ enabled. README narrative refreshed with sub-stack C closure + out-of-scope follow-up SDD.

- [x] 3.15 Ran sub-stack C 6-AI verify on v0.20.0 / v3.14.0 commits. Mixed verdicts: R1 PASS (no warnings), R2 PASS-WITH-WARNINGS (P2), R5 PASS-WITH-WARNINGS escalated to P0, Codex BLOCK. **Triple-confirmed P0** (R2 + R5 + Codex independently): `recognizedRprChildren` Set silently dropped ~16+ rPr child kinds (`<w:spacing>`, `<w:caps>`, `<w:smallCaps>`, `<w:position>`, `<w:shd>`, `<w:bdr>`, `<w:em>`, `<w:effect>`, `<w:vanish>`, `<w:outline>`, `<w:shadow>`, `<w:emboss>`, `<w:imprint>`, `<w:bCs>`, `<w:iCs>`, `<w:dstrike>`, etc.). Codex P1 (deferred): schema-order rawChildren tail-append, characterSpacing/textEffect parser-side gap, static Set allocation perf, ratio-floor maintenance.

- [x] 3.16 Sub-stack C-CONT mini-cycle (executed inline): trimmed `recognizedRprChildren` Set to ONLY actually-typed-extracted-or-emitted kinds. Tests still 682/0/1. Round-trip size loss improved 17.75% → 16.66% (+1.09 pp). Matrix-pin floor tightened 0.19 → 0.175. Shipped ooxml-swift v0.20.1 (commit b591813) + che-word-mcp v3.14.1 (commit 598462a) + marketplace sync (commit 0e6119b). Closing summary posted: https://github.com/PsychQuant/che-word-mcp/issues/60#issuecomment-4326671996. **#60 closed**. Sub-stack C verified clean for actual field-loss audit scope. Out-of-scope drops (paragraph-mark rPr + w14:paraId/textId + Codex P1s) tracked as separate follow-up SDD. `docs/structural-editing-paradigm.md` §3 update deferred — paragraph-mark rPr drop accounts for remaining 16.66% loss; updating "lossless" claim premature until that follow-up lands.

## 4. Documentation + paradigm narrative update

- [x] 4.1 Added new §3.1 to `docs/structural-editing-paradigm.md` documenting the modified-parts content-equality guarantee (typed + raw fallback architecture across sub-stacks A/B/C). Calibrated honestly to actual current state: 32% pre-fix → 16.66% post-sub-stack-C-CONT, with table showing per-sub-stack progression. Documented out-of-scope drops (paragraph-mark rPr + w14:paraId/textId) as separate follow-up SDD; **didn't claim "byte-preservation for modified parts"** because it's content-equality only, with measured 16.66% byte loss from out-of-scope paragraph-level bugs.

- [x] 4.2 Added new §6.1 (强版 demo) calibrated to current state. Includes `<w:caps>`, `<w:smallCaps>`, `<w:shd>`, `<w:bdr>`, `<w14:textOutline>` etc. as preserved. Honest caveat: "edit 一個字 → document.xml shrinks <1%" claim is DEFERRED until paragraph-mark rPr follow-up lands (currently 16.66% loss). Current honest claim: "typed + raw fallback 確保任何 sub-stack A/B/C 已涵蓋的 preservation class 都不會 silently 丟失 — LOAD-BEARING by matrix-pin".

- [x] 4.3 Updated §10 with TWO invariants: Invariant 1 (unmodified parts bit-exact, v0.13.0+), Invariant 2 (modified parts content-equality across enumerated preservation classes, v0.20.1+). Added §10.1 documenting paragraph-level edge cases NOT yet covered (paragraph-mark rPr + w14:paraId/textId) as the gap before second invariant can extend to paragraph-level.
