## 1. Phase 0 — XmlNode tree foundation (target v0.30.0)

Implements **Decision 1: Generic XmlNode tree as the single internal representation** and the `ooxml-tree-io` capability. Decisions 6 (identity matching) and 8 (staged migration) inform the staging.

- [x] 1.1 Define the `XmlNode` data type covering the **lossless XmlNode tree representation** requirement: element name, namespace URI, ordered attributes (preserving namespace prefix decisions), ordered children (mixed text + element + comment + processing instruction), and source-XML offset for unchanged-sub-tree fast path
- [x] 1.2 [P] Implement `XmlTreeReader.read(part:)` that satisfies the **lossless XmlNode tree representation** requirement on every part class observed in fixtures (settings.xml, document.xml, header*.xml, footer*.xml, customXml/*.xml)
- [x] 1.3 [P] Implement `XmlTreeWriter.write(_:to:)` that satisfies the **identity round-trip on untouched sub-trees** requirement, reusing source-XML offsets for sub-trees marked clean
- [x] 1.4 [P] Implement `XmlNode.normalizedFingerprint()` covering the **identity-noise normalization for diff comparison** requirement (rsids, default attributes, namespace-prefix variants, unordered-attribute permutations)
- [x] 1.5 [P] Implement the **stable sub-tree references across reads** requirement: derive an `ElementID` from `w14:paraId` / `w:id` / `r:id` and surface via `XmlNode.id`
- [x] 1.6 [P] Cover the **generic-text and mixed-content support** requirement: introduce `XmlNode.text(String)` case and verify ordered-children preservation against a mixed-content fixture
- [x] 1.7 Verify the **pure-Swift implementation** requirement by running `swift package show-dependencies` pre/post and confirming no new external entries; lock the module to first-party Swift code only
- [x] 1.8 Commit the **round-trip golden corpus** fixtures (`multi-section-thesis.docx`, `vml-rich.docx`, `cjk-settings.docx`, `comment-anchored.docx`) and the byte-equal goldens that prove the round-trip contract on each
- [x] 1.9 [P] Write `TreeRoundTripGoldenTests` exercising **Decision 1: Generic XmlNode tree as the single internal representation** against all four fixtures with byte-equal assertion
- [x] 1.10 Tag and release `ooxml-swift v0.30.0` per **Decision 8: Migration is staged across `0.x → 1.0`**, preserving the existing typed model unchanged

## 2. Phase 1 — Typed views become tree projections (target v0.31.0)

Implements **Decision 4: Typed APIs as views, not as the model** and the modified `docx-container-parsing` and `docx-revision-parsing` requirements.

- [x] 2.1 Refactor `Paragraph` to satisfy **Decision 4: Typed APIs as views, not as the model**: getters read through the underlying `XmlNode`, setters route mutations to the (still-internal) op log
- [x] 2.2 [P] Refactor `Run` to be a tree-backed view (same shape as 2.1)
- [x] 2.3 [P] Refactor `Table`, `TableRow`, `TableCell` to be tree-backed views
- [x] 2.4 [P] Refactor `SectionProperties` to be a tree-backed view; verify the **multi-section sectPr preservation** requirement against `multi-section-thesis.docx`
- [x] 2.5 [P] Refactor `Settings` to be a tree-backed view; remove the `rawChildren: [String]` deprecation candidate; verify against `cjk-settings.docx`
- [x] 2.6 Update `DocxReader` to satisfy the **all parts preserved via XmlNode tree alongside typed views** requirement: load every part listed in `[Content_Types].xml` into the tree
- [x] 2.7 Update `DocxReader.parseBody` / `parseSettings` / `parseStyles` / `parseHeaders` / `parseFooters` / `parseFootnotes` / `parseEndnotes` / `parseComments` to satisfy the **reader does not silently drop element classes** requirement and the **container parts preserve unknown children identically to body** requirement
- [x] 2.8 Update `DocxReader.parseParagraph` to satisfy the **revision elements preserved via tree on round-trip** requirement and the **unknown revision children are preserved verbatim** requirement
- [x] 2.9 [P] Verify the **nested property-change revisions round-trip via tree** requirement against a fixture containing `<w:rPrChange>` and `<w:pPrChange>`
- [x] 2.10 Verify the **revision-source typed view backed by tree** requirement: `getRevisionsFull()` observable behavior remains identical
- [x] 2.11 Run the full che-word-mcp test suite (271 tests) against the new ooxml-swift; investigate every failure; expect zero observable behavior change in MCP tool output
- [x] 2.12 Tag and release `ooxml-swift v0.31.0`

## 3. Phase 2 — Operation log persistence (target v0.32.0)

Implements **Decision 2: Append-only operation log, persisted as JSONL sidecar**, **Decision 3: ID-based operations, never positional indices**, **Decision 5: Sidecar persistence, not in-document metadata**, and the `ooxml-operation-log` and `ooxml-operation-reducer` capabilities.

- [x] 3.1 Define the `Operation` enum covering the **operation taxonomy covers full OOXML mutation surface** requirement: element-level (`InsertParagraphAfter`, `InsertParagraphBefore`, `RemoveParagraph`, `SetText`, `SetParagraphStyle`, `InsertTable`, `RemoveTable`, `SetCellText`, `InsertRun`, `SetRunFormat`, `InsertBookmark`, `InsertComment`, `Undo`, `Redo`, `BatchBegin`, `BatchEnd`) and tree-node-level fallback (`InsertNode`, `RemoveNode`, `UpdateAttribute`, `MoveNode`)
- [x] 3.2 [P] Implement `ElementID` per the **ElementID derivation rules** requirement: priority chain `w14:paraId` → `w:id` → `r:id` → `w14:textId` → library UUID v4
- [x] 3.3 [P] Implement `OperationLog` covering the **append-only operation log** requirement: `append`, `entries`, immutability of appended ops; demonstrate **Decision 3: ID-based operations, never positional indices** by showing that two independent inserts commute
- [x] 3.4 [P] Cover the **operation IDs are unique and stable** requirement: every op gets a UUID v4; replaying the same log twice produces matching `op_id` per position
- [x] 3.5 [P] Cover the **source attribution for every operation** requirement: every appended op carries `source: "swift" | "word"`
- [x] 3.6 Implement JSONL serialization satisfying the **JSONL on-disk format** requirement: one self-contained JSON object per line with required fields
- [x] 3.7 [P] Cover the **forward-compatible log format** requirement: unknown `op_type` round-trips byte-equal; replay treats unknown ops as opaque
- [x] 3.8 Implement `OperationLog.batch(_:)` covering the **batch transactions for grouped mutations** requirement with atomic `BatchBegin` / `BatchEnd` markers
- [x] 3.9 Implement `OperationReducer.materialize(log:base:)` covering the **pure replay of operation log to tree** requirement and the **reducer is pure relative to its inputs** requirement (sandbox test traps any I/O)
- [x] 3.10 [P] Implement `OperationReducer.state(log:base:at:)` covering the **time-travel state snapshots** requirement (index and timestamp variants)
- [x] 3.11 [P] Implement the **undo operation reverses its target** requirement and the **redo reapplies an undone operation** requirement
- [x] 3.12 [P] Implement `OperationReducer.blame(log:elementID:)` covering the **blame returns the operation that last touched an element** requirement
- [x] 3.13 [P] Implement the **snapshot caching avoids full replay on every read** requirement: cache last-materialized tree + log length, replay tail on `state(at: .latest)`
- [x] 3.14 [P] Cover the **apply errors are reported, not swallowed** requirement: throw `ReducerError.elementNotFound(opID:elementID:)`
- [x] 3.15 Wire typed-view setters from Phase 1 to emit ops via the log instead of direct tree mutation; verify **Decision 4: Typed APIs as views, not as the model** end-to-end
- [x] 3.16 Implement sidecar file management satisfying **Decision 5: Sidecar persistence, not in-document metadata**: `<docx>.oplog.jsonl` + `<docx>.snapshot.json` written alongside the docx; nothing written into the docx
- [x] 3.17 Tag and release `ooxml-swift v0.32.0`

## 4. Phase 3 — Word-import diff and sync orchestration (target v0.33.0)

Implements **Decision 6: Word-import diff via structural element-identity matching** and **Decision 7: Conflict policy is opt-in and explicit**, and the `ooxml-word-sync` capability.

- [x] 4.1 Implement `SyncOrchestrator` covering the **SyncOrchestrator coordinates Word and Swift writers** requirement
- [x] 4.2 Implement `WordImport.diff(snapshot:current:)` covering the **Word-import diff via element identity matching** requirement; satisfies **Decision 6: Word-import diff via structural element-identity matching** end-to-end
- [x] 4.3 [P] Implement the **conflict detection on overlapping mutations** requirement: compute `ConflictReport` listing each conflicting `ElementID`
- [x] 4.4 Define `SyncPolicy` enum covering the **typed conflict policy** requirement (`.abortOnConflict`, `.swiftWins`, `.wordWins`, `.askUser(handler:)`); satisfies **Decision 7: Conflict policy is opt-in and explicit** end-to-end
- [x] 4.5 [P] Implement the **file watcher contract** requirement: mtime + SHA-256 polling at configurable interval (default 1s)
- [x] 4.6 [P] Implement the **Word file-lock interaction** requirement: detect `~$<filename>.docx` lock-file lifecycle; refuse Swift writes while lock present; trigger final import on lock removal
- [x] 4.7 Implement the **sidecar persistence of snapshot and log** requirement and the **bootstrap from existing docx** requirement (`SyncOrchestrator.bootstrapFromDocx(url:)` handles fresh / existing / stale-snapshot cases)
- [x] 4.8 Add Word-roundtrip integration test: open a fixture in Word (manual or scripted via AppleScript / `osascript`), edit one paragraph, save; assert the orchestrator captures the edit as a non-empty op set with `source: "word"`
- [x] 4.9 Run the rsid-only-no-edit fixture pair: the import diff must produce an empty op set (regression-pin **identity-noise normalization for diff comparison**)
- [x] 4.10 Tag and release `ooxml-swift v0.33.0`

## 4b. Phase 3.5 — Operation taxonomy alignment (#128, gates Phase 4)

Spec-side consolidation shipped by the #128 PR (op-log delta + transcode scenario rewrite + mdocx-grammar MODIFIED delta). The tasks below are the ooxml-swift implementation side — additive only, per the "Authoring operations extend the taxonomy additively with OOXML-mirror naming" requirement.

- [x] 4b.1 Extend `Operation` enum with the authoring cases per the updated `ooxml-operation-log` delta: `appendParagraph(in:)`, `setRuns`, `defineStyle`, `beginComponent`/`endComponent`, `insertTab`/`insertBreak`/`insertNoBreakHyphen` (TDD; names + payload fields OOXML-mirror audited). **Verify**: enum cases compile; each constructs and pattern-matches.

- [x] 4b.2 [P] JSONL codec cases for the new ops + forward-compat round-trip tests (unknown-op preservation unchanged). **Verify**: encode/decode round-trip per op; existing JSONL tests untouched and green.

- [x] 4b.3 [P] Reducer cases: `beginComponent`/`endComponent` as no-op markers (batch-marker pattern); `appendParagraph`/`setRuns`/`defineStyle`/inline atoms materialize per their spec scenarios incl. defineStyle idempotency. **Verify**: `swift test --filter OperationReducer` green with new cases.

- [x] 4b.4 Tag and release `ooxml-swift v0.33.1` (additive; sidecar wire format backward-compatible). **Verify**: tag pushed; che-word-mcp suite green against it.

## 5. Phase 4 — Script transcoder (target v0.34.0)

Implements the `ooxml-script-transcode` capability per Decision 9: Phase 4 script transcoder targets the `mdocx-grammar` contract. Output of `ScriptExporter` MUST conform to `openspec/specs/mdocx-grammar/spec.md`; input of `ScriptImporter` MUST accept exactly that surface. The 14 empty Swift files at `packages/ooxml-swift/Sources/WordDSLSwift/` (placeholders landed by `mdocx-syntax`) are the implementation targets.

- [x] 5.1 Implement `ScriptExporter.exportSwift(log:)` covering the **operation log to Swift script export** requirement; emitted Swift source MUST conform to `mdocx-grammar` Requirements "File extension and dual-extension pattern", "Flat Run with implicit String literal inline grammar", and "OOXML-mirror element naming"
- [x] 5.2 [P] Implement `ScriptImporter.parse(source:)` covering the **Swift script to operation log import** requirement, including structured error reporting (`TranscodeError.unsupportedSyntax`); accepted source MUST cover `mdocx-grammar` Requirements "Mandatory explicit identifiers on structural elements", "No semantic shortcuts for OOXML-style attributes", and "Special-character inline atoms as standalone children"
- [x] 5.3 [P] Cover the **build a docx end-to-end from a Swift script** requirement: `Document.create()` produces a valid empty docx; round-trip through Word save preserves structural equivalence; covers `mdocx-grammar` Requirements "save(to:) atomic three-file write" (docx + oplog.jsonl + snapshot.json) and "Section as DSL container with compile-time marker inversion"
- [x] 5.4 [P] Implement the **stable script formatting for diff readability** requirement: deterministic indent, predictable line ordering, deterministic comment placement; verify "add one operation → one git-diff hunk" property
- [x] 5.5 [P] Cover the **script export covers all operation types in the log** requirement, including the unknown-op_type forward-compat case; structural element types covered MUST include `mdocx-grammar` Requirements "Table grammar mirrors OOXML three-layer structure", "Lists use Paragraph with numPr reference, not nested containers", "Hyperlinks are containers with target enum", "Bookmarks default to container with paired-marker escape hatch", "Style references via typed enum with define-on-first-use", and "Component-aware op log via BeginComponent and EndComponent"
- [x] 5.6 Round-trip integration test: log → script → log produces equivalent operations (same `op_type` and `payload` per position; `op_id` and `timestamp` may regenerate); script → log → script idempotency holds for the canonical form (per `mdocx-grammar` Requirement "Reverse CLI shape — macdoc word reverse" once that CLI surface lands)
- [x] 5.7 Implement the `macdoc word reverse <docx> --to-mdocx <out> [--from-oplog] [--force]` CLI surface required by `mdocx-grammar` Requirement "Reverse CLI shape — macdoc word reverse"
- [x] 5.8 Tag and release `ooxml-swift v0.34.0`

## 6. Phase 5 — Migration cleanup (target v1.0.0)

Implements the final stage of **Decision 8: Migration is staged across `0.x → 1.0`**.

- [x] 6.1 Remove the typed-only legacy `DocxReader` paths superseded by tree IO; the tree path becomes the only read path
- [x] 6.2 [P] Remove the typed-only legacy `DocxWriter` paths; the tree path becomes the only write path
- [ ] 6.3 [P] Remove the `rawChildren: [String]` ad-hoc fields from `Run`, `Paragraph`, `SectionProperties`, `Settings`; tree coverage subsumes them
  > **2026-07-06 scoping note**: only `RunProperties.rawChildren` and `Hyperlink.rawChildren` exist in code (Paragraph/SectionProperties/Settings never grew the field). Removal experiment surfaced the real dependency: 16 direct-typed-mutation round-trip tests (Issue56R3Stack `*_RoundtripVariant`: acceptRevision / rejectRevision / insertComment / replaceText / bookmark-id calibration …) rely on the typed writer re-emitting dirty parts, and rawChildren is what keeps unknown `<w:rPr>` children alive on that path. Tree-first dirty writes (serialize the live tree) fix unknown-preservation for op-log mutations but silently drop direct typed mutations — the tree only stays fresh through the reducer. **6.3 therefore requires migrating that direct-mutation API surface to op-based implementations first** (per-API op mapping or part-level typed→tree materialization at mutation time). Sequenced as the first block of the remaining v1.0 surgery.
- [ ] 6.4 Update CHANGELOG with the v0.30 → v1.0 migration narrative; document the `Document.body.children = [...]` direct-assignment removal as a migration note
- [ ] 6.5 Run the full ooxml-swift + che-word-mcp + macdoc CLI test matrix against v1.0; confirm zero regressions
- [x] 6.6 Address the **risks / trade-offs** section's "tree memory cost on large docs" risk: benchmark NTPU thesis fixture; report memory under 50 MB or document mitigation
- [x] 6.7 [P] Address the typed-view performance regression risk: benchmark che-word-mcp `get_paragraphs` on 200-paragraph fixture pre/post; document numbers
- [x] 6.8 Address the **migration plan** rollback documentation: each release tag is independently downgradable; document downgrade matrix
- [x] 6.9 Resolve **open questions** (sidecar opt-in default, op log granularity for fine mutations, mixed-content representation, file-watcher boundary heuristic, single-writer assumption, ad-hoc rawChildren bridge code) — convert each from "working answer" to spec-frozen decision in the corresponding capability spec
- [ ] 6.10 Tag and release `ooxml-swift v1.0.0`

## 7. Cross-cutting verification

- [ ] 7.1 Independent 6-AI verify (5 Claude reviewers + Codex gpt-5.5 xhigh) on the v0.30.0 release per the project's verify-gate protocol
- [ ] 7.2 [P] Independent 6-AI verify on v0.31.0
- [ ] 7.3 [P] Independent 6-AI verify on v0.32.0
- [ ] 7.4 [P] Independent 6-AI verify on v0.33.0
- [ ] 7.5 [P] Independent 6-AI verify on v0.34.0
- [ ] 7.6 Independent 6-AI verify on v1.0.0 (final architectural sign-off)
