# ooxml-operation-log Specification

> **Related**: this capability is Phase 2a of `word-aligned-state-sync` — it provides the data structures the rest of Phase 2 builds on. The reducer / replay / time-travel / undo-redo logic (`word-aligned-state-sync` tasks 3.9-3.14) lives in follow-up `operation-reducer-impl`. Typed-view setter wiring + sidecar persistence (tasks 3.15-3.16) live in follow-up `operation-log-setter-wiring-impl`. The v0.32.0 GA tag (task 3.17) waits for the full Phase 2 bundle (2a + 2b + 2c) to ship together.

## Purpose

Defines the data-structure contract for the operation log that makes `word-aligned-state-sync` Phase 2 possible. Every mutation in a tree-backed `WordDocument` is expressible as an `Operation` value; the typed `OperationLog` is the append-only collection that records those mutations with `ElementID` payloads, source attribution (`.swift` / `.word`), per-op UUIDs, and JSONL persistence. The Phase 2b `OperationReducer` (separate change) consumes this log to materialize trees / time-travel / undo-redo; Phase 2c wires the typed-view setters from v0.31.0 / v0.31.1 (`Paragraph.text =`, `Run.text =`, etc.) to emit ops via this log instead of mutating trees directly.

This capability covers, in this order of dependency:

1. **Operation taxonomy** — 21 enum cases enumerated to cover the full Phase 2 mutation surface: 16 element-level (`insertParagraphAfter`, `insertParagraphBefore`, `removeParagraph`, `setText`, `setParagraphStyle`, `insertTable`, `removeTable`, `setCellText`, `insertRun`, `setRunFormat`, `insertBookmark`, `insertComment`, `undo`, `redo`, `batchBegin`, `batchEnd`) + 4 tree-node-level fallback (`insertNode`, `removeNode`, `updateAttribute`, `moveNode`) + 1 forward-compat fallback (`unknown(opType:payload:)` carries any unrecognized op_type byte-equal across version skews)
2. **ElementID derivation** — `ElementID(node:)` walks the priority chain `w14:paraId` → `w:bookmarkId` → `w:id` → `r:id` → `w14:textId` → `libraryUUID` → returns `nil`. Format byte-aligns with `XmlNode.stableID` so the reducer can match by string equality across OpLog and XmlTree
3. **Append-only log contract** — `OperationLog` value type with `private(set) var entries`, `append(_:source:opID:at:)`, and `batch(_:label:_:)` mutating methods. No public remove/replace/reorder API — append-only is the data-structure invariant
4. **Operation IDs are unique and stable** — every `LogEntry` carries a UUID v4 in `opID`; the value persists through serialization/deserialization unchanged
5. **Source attribution** — every `LogEntry` carries `source: OpSource` whose value is `.swift` (Swift code emitted the op) or `.word` (Phase 3 SyncOrchestrator import path reconstructed the op from a Word-app edit)
6. **JSONL on-disk format** — one self-contained JSON object per line, separated by Unix LF. Required discriminator fields (`op_id`, `ts`, `source`, `op_type`) in fixed order, op-specific fields next in case-declaration order. Round-trip byte-equal for known ops
7. **Forward-compatible log format** — unknown `op_type` values decode to `.unknown(opType:payload:)` carrying the entire JSON object minus the four required fields as a `JSONValue.object`. Re-encoding sorts payload keys lexicographically for byte-equal round-trip when input was sorted. Cross-version log files (e.g., v0.31.4 emits an op v0.31.3 doesn't recognize) round-trip without data loss
8. **Batch transactions** — `OperationLog.batch(_:label:_:)` emits `batchBegin(label:)` before the closure body and `batchEnd` after. Phase 2b reducer uses these markers to group related ops for undo/redo. Best-effort: `batchEnd` is NOT emitted if the closure body throws (rollback is a reducer concern, not a data-structure concern)
9. **Test coverage pinned** — 8 spec scenarios + 1 bonus malformed-line test, all GREEN-from-the-start (no `#if false` gate)

The capability does not own the reducer (`operation-reducer-impl`), the typed-view setter wiring (`operation-log-setter-wiring-impl`), the sidecar files, the SyncOrchestrator (Phase 3), the typed views (`ooxml-paragraph-tree-projection` / `ooxml-typed-views-tree-projection`), or the lossless tree IO (v0.30.0). It is the narrow contract for "what an Operation is, what an OperationLog is, and how they serialize to JSONL."

## Requirements

### Requirement: Operation taxonomy covers full OOXML mutation surface

The `Operation` enum SHALL expose every mutation kind the Phase 2 op log persists. The taxonomy splits into three groups:

**Element-level operations** (typed cases addressing OOXML elements by `ElementID`):
- `insertParagraphAfter(after: ElementID, paragraph: ParagraphPayload)`
- `insertParagraphBefore(before: ElementID, paragraph: ParagraphPayload)`
- `removeParagraph(id: ElementID)`
- `setText(target: ElementID, text: String)`
- `setParagraphStyle(target: ElementID, styleId: String?)`
- `insertTable(at: ElementID, table: TablePayload)`
- `removeTable(id: ElementID)`
- `setCellText(table: ElementID, row: Int, column: Int, text: String)`
- `insertRun(in: ElementID, position: Int, run: RunPayload)`
- `setRunFormat(target: ElementID, format: RunFormatPayload)`
- `insertBookmark(at: ElementID, bookmarkId: Int, name: String)`
- `insertComment(anchor: ElementID, commentId: Int, text: String, author: String)`
- `undo(targetOpID: UUID)`
- `redo(targetOpID: UUID)`
- `batchBegin(label: String?)`
- `batchEnd`

**Tree-node-level fallback operations** (typed cases addressing nodes by `ElementID` for cases the element-level set does not cover):
- `insertNode(parent: ElementID, position: Int, nodeXML: String)`
- `removeNode(target: ElementID)`
- `updateAttribute(target: ElementID, prefix: String?, localName: String, value: String?)`
- `moveNode(source: ElementID, destinationParent: ElementID, destinationIndex: Int)`

**Forward-compat fallback** (carries any unrecognized op_type byte-equal):
- `unknown(opType: String, payload: JSONValue)`

The enum SHALL conform to `Equatable`, `Sendable`, and `Codable`. Adding new cases in future ooxml-swift versions SHALL be additive — existing consumers compile unchanged.

#### Scenario: every documented case constructs and pattern-matches

- **WHEN** a test constructs each of the 21 cases listed above with reasonable values
- **THEN** the construction SHALL succeed and a `switch` over the value SHALL match exactly one case
- **AND** the matched case's associated values SHALL equal the input values


<!-- @trace
source: operation-log-scaffold-impl
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-143628.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-050704.log
-->


<!-- @trace
source: word-aligned-state-sync
updated: 2026-07-06
code:
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-144618.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/AnchorResolver.swift
  - .remember/logs/autonomous/save-095118.log
  - plugins/macdoc/hooks/hooks.json
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-143020.log
  - Sources/MacDocCLI/MacDoc+Word.swift
  - .remember/logs/autonomous/save-133659.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093340.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-095142.log
  - plugins/che-pdf-mcp/bin/che-pdf-mcp-wrapper.sh
  - reference/README.md
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-144433.log
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - .remember/logs/autonomous/save-090944.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ExecutorTests.swift
  - .remember/logs/autonomous/save-092853.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGeneratorTests.swift
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - plugins/che-pptx-mcp/bin/che-pptx-mcp-wrapper.sh
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-125453.log
  - mcp/che-pdf-mcp
  - .remember/logs/autonomous/save-070717.log
  - plugins/che-pptx-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-094627.log
  - .claude-plugin/marketplace.json
  - Package.swift
  - .remember/logs/autonomous/save-053409.log
  - plugins/che-pptx-mcp/README.md
  - plugins/macdoc/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-095621.log
  - README.md
  - .remember/logs/autonomous/save-093255.log
  - docs/lossless-conversion.md
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorDecodingTests.swift
  - Package.resolved
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-130300.log
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - mcp/che-pptx-mcp
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093039.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/DocxWorkflowLib.swift
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/VerifyAssertions.swift
  - packages/docx-workflow-swift/Package.swift
  - .github/PULL_REQUEST_TEMPLATE.md
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-093030.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Manifest.swift
  - .remember/logs/autonomous/save-093138.log
  - cli/FastOCR
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-095539.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Anchor.swift
  - plugins/che-word-mcp/CLAUDE.md
  - plugins/macdoc/skills/macdoc/SKILL.md
  - .remember/logs/autonomous/save-095047.log
  - plugins/che-word-mcp/README.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Tests/MacDocCLITests/NoteHTMLConvertTests.swift
  - plugins/che-pdf-mcp/skills/che-pdf-mcp/SKILL.md
  - plugins/che-word-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-125949.log
  - plugins/che-word-mcp/.mcp.json
  - .github/skills/spectra-drift/SKILL.md
  - plugins/che-pdf-mcp/README.md
  - docs/stale-triage-chain-2026-05-25.md
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-132950.log
  - plugins/che-pdf-mcp/CHANGELOG.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/EditPlanner.swift
  - plugins/che-word-mcp/bin/che-word-mcp-wrapper.sh
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093013.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ManifestDecodingTests.swift
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-132859.log
  - plugins/che-word-mcp/CHANGELOG.md
  - Sources/MacDocCLI/MacDoc.swift
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143733.log
  - plugins/macdoc/hooks/session-start.sh
  - packages/docx-workflow-swift/CHANGELOG.md
  - .remember/logs/autonomous/save-144132.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifierTests.swift
  - plugins/che-pdf-mcp/.claude-plugin/plugin.json
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-144003.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Executor.swift
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093149.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Verifier.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifyAssertionsDecodingTests.swift
  - plugins/che-pptx-mcp/.mcp.json
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - scripts/release-cli.sh
  - .remember/logs/autonomous/save-143856.log
  - CLAUDE.md
  - .remember/logs/autonomous/save-144708.log
  - Tests/MacDocCLITests/Fixtures/README.md
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095546.log
  - .gitmodules
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-090656.log
  - packages/docx-workflow-swift/README.md
  - plugins/che-pptx-mcp/CHANGELOG.md
  - .remember/logs/autonomous/save-051714.log
  - plugins/che-pdf-mcp/.mcp.json
  - .remember/logs/autonomous/save-093825.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGenerator.swift
  - plugins/macdoc/CHANGELOG.md
  - plugins/che-word-mcp/skills/che-word-mcp/SKILL.md
  - .remember/logs/autonomous/save-091107.log
  - docs/edit-algebra-cd-discipline.md
  - docs/structural-editing-paradigm.md
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-131902.log
  - .github/prompts/spectra-drift.prompt.md
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-050705.log
  - docs/docx-libraries-comparison.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/ParagraphSnapshot.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorResolverTests.swift
  - docs/stale-triage-chain-batch2-2026-05-25.md
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-143700.log
-->

---
### Requirement: ElementID derivation rules

`ElementID` SHALL be a value type wrapping a `String` that aligns byte-for-byte with `XmlNode.stableID`'s format. The initializer `ElementID(node: XmlNode)` SHALL derive the ID using this priority chain (first match wins):

1. `w14:paraId` attribute → `"w14:paraId=\(value)"`
2. `w:bookmarkId` attribute → `"w:bookmarkId=\(value)"`
3. `w:id` attribute → `"w:id=\(value)"`
4. `r:id` attribute → `"r:id=\(value)"`
5. `w14:textId` attribute → `"w14:textId=\(value)"`
6. `XmlNode.libraryUUID` (if assigned) → `"lib:\(uuid.uuidString)"`
7. None of the above → returns `nil`

A separate initializer `ElementID(libraryUUID: UUID)` SHALL produce `"lib:\(uuid.uuidString)"` directly without consulting an `XmlNode`.

A separate initializer `ElementID(rawString: String)` SHALL accept any String verbatim — used by JSONL decoding to reconstruct ElementID values from on-disk bytes.

`ElementID` SHALL conform to `Equatable`, `Hashable`, `Sendable`, and `Codable`.

#### Scenario: ElementID derives from w14:paraId

- **GIVEN** an `XmlNode` with attribute `w14:paraId="0ABC1234"`
- **WHEN** `ElementID(node: thatNode)` is called
- **THEN** the returned `ElementID?` SHALL be non-nil
- **AND** its `raw` property SHALL equal `"w14:paraId=0ABC1234"`

#### Scenario: ElementID falls back to libraryUUID when no native stable ID

- **GIVEN** an `XmlNode` with no stable-ID attributes but `libraryUUID = UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")`
- **WHEN** `ElementID(node: thatNode)` is called
- **THEN** the returned `ElementID?` SHALL be non-nil
- **AND** its `raw` property SHALL equal `"lib:550E8400-E29B-41D4-A716-446655440000"`

#### Scenario: ElementID returns nil when no stable identity exists

- **GIVEN** an `XmlNode` with no stable-ID attributes and `libraryUUID == nil`
- **WHEN** `ElementID(node: thatNode)` is called
- **THEN** the returned `ElementID?` SHALL be `nil`


<!-- @trace
source: operation-log-scaffold-impl
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-143628.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-050704.log
-->


<!-- @trace
source: word-aligned-state-sync
updated: 2026-07-06
code:
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-144618.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/AnchorResolver.swift
  - .remember/logs/autonomous/save-095118.log
  - plugins/macdoc/hooks/hooks.json
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-143020.log
  - Sources/MacDocCLI/MacDoc+Word.swift
  - .remember/logs/autonomous/save-133659.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093340.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-095142.log
  - plugins/che-pdf-mcp/bin/che-pdf-mcp-wrapper.sh
  - reference/README.md
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-144433.log
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - .remember/logs/autonomous/save-090944.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ExecutorTests.swift
  - .remember/logs/autonomous/save-092853.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGeneratorTests.swift
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - plugins/che-pptx-mcp/bin/che-pptx-mcp-wrapper.sh
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-125453.log
  - mcp/che-pdf-mcp
  - .remember/logs/autonomous/save-070717.log
  - plugins/che-pptx-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-094627.log
  - .claude-plugin/marketplace.json
  - Package.swift
  - .remember/logs/autonomous/save-053409.log
  - plugins/che-pptx-mcp/README.md
  - plugins/macdoc/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-095621.log
  - README.md
  - .remember/logs/autonomous/save-093255.log
  - docs/lossless-conversion.md
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorDecodingTests.swift
  - Package.resolved
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-130300.log
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - mcp/che-pptx-mcp
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093039.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/DocxWorkflowLib.swift
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/VerifyAssertions.swift
  - packages/docx-workflow-swift/Package.swift
  - .github/PULL_REQUEST_TEMPLATE.md
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-093030.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Manifest.swift
  - .remember/logs/autonomous/save-093138.log
  - cli/FastOCR
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-095539.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Anchor.swift
  - plugins/che-word-mcp/CLAUDE.md
  - plugins/macdoc/skills/macdoc/SKILL.md
  - .remember/logs/autonomous/save-095047.log
  - plugins/che-word-mcp/README.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Tests/MacDocCLITests/NoteHTMLConvertTests.swift
  - plugins/che-pdf-mcp/skills/che-pdf-mcp/SKILL.md
  - plugins/che-word-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-125949.log
  - plugins/che-word-mcp/.mcp.json
  - .github/skills/spectra-drift/SKILL.md
  - plugins/che-pdf-mcp/README.md
  - docs/stale-triage-chain-2026-05-25.md
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-132950.log
  - plugins/che-pdf-mcp/CHANGELOG.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/EditPlanner.swift
  - plugins/che-word-mcp/bin/che-word-mcp-wrapper.sh
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093013.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ManifestDecodingTests.swift
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-132859.log
  - plugins/che-word-mcp/CHANGELOG.md
  - Sources/MacDocCLI/MacDoc.swift
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143733.log
  - plugins/macdoc/hooks/session-start.sh
  - packages/docx-workflow-swift/CHANGELOG.md
  - .remember/logs/autonomous/save-144132.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifierTests.swift
  - plugins/che-pdf-mcp/.claude-plugin/plugin.json
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-144003.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Executor.swift
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093149.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Verifier.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifyAssertionsDecodingTests.swift
  - plugins/che-pptx-mcp/.mcp.json
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - scripts/release-cli.sh
  - .remember/logs/autonomous/save-143856.log
  - CLAUDE.md
  - .remember/logs/autonomous/save-144708.log
  - Tests/MacDocCLITests/Fixtures/README.md
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095546.log
  - .gitmodules
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-090656.log
  - packages/docx-workflow-swift/README.md
  - plugins/che-pptx-mcp/CHANGELOG.md
  - .remember/logs/autonomous/save-051714.log
  - plugins/che-pdf-mcp/.mcp.json
  - .remember/logs/autonomous/save-093825.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGenerator.swift
  - plugins/macdoc/CHANGELOG.md
  - plugins/che-word-mcp/skills/che-word-mcp/SKILL.md
  - .remember/logs/autonomous/save-091107.log
  - docs/edit-algebra-cd-discipline.md
  - docs/structural-editing-paradigm.md
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-131902.log
  - .github/prompts/spectra-drift.prompt.md
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-050705.log
  - docs/docx-libraries-comparison.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/ParagraphSnapshot.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorResolverTests.swift
  - docs/stale-triage-chain-batch2-2026-05-25.md
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-143700.log
-->

---
### Requirement: Append-only operation log

`OperationLog` SHALL be a value type with an `entries: [LogEntry]` array exposed read-only externally (`public private(set)`). The type SHALL provide:

- `append(_ op: Operation, source: OpSource, opID: UUID = UUID(), at timestamp: Date = Date())` — mutating method that appends a new `LogEntry` to `entries`
- `batch(_ source: OpSource, label: String? = nil, _ body: (inout OperationLog) throws -> Void) rethrows` — atomic transaction helper that wraps the closure body in `batchBegin` / `batchEnd` op markers

There SHALL be NO public method to remove entries, replace entries in-place, or mutate `entries` directly. The append-only invariant is part of the contract.

`LogEntry` SHALL be a value type carrying `opID: UUID`, `op: Operation`, `source: OpSource`, `timestamp: Date`, conforming to `Equatable`, `Sendable`, `Codable`.

`OpSource` SHALL be an enum with cases `.swift` and `.word`, conforming to `Equatable`, `Sendable`, `Codable` (encoded as JSON strings `"swift"` / `"word"`).

#### Scenario: append increases entries count and preserves source

- **GIVEN** an empty `OperationLog`
- **WHEN** `log.append(.setText(target: id, text: "X"), source: .swift)` is called
- **THEN** `log.entries.count` SHALL equal `1`
- **AND** `log.entries[0].op` SHALL equal `.setText(target: id, text: "X")`
- **AND** `log.entries[0].source` SHALL equal `.swift`

#### Scenario: opIDs are unique across appends

- **WHEN** two consecutive default-opID appends happen on the same log
- **THEN** the two `LogEntry.opID` values SHALL differ (UUID v4 collision probability is negligible)

#### Scenario: batch wraps body ops with begin/end markers

- **GIVEN** an empty `OperationLog`
- **WHEN** `log.batch(.swift, label: "rename") { lb in lb.append(.setText(target: id, text: "X"), source: .swift) }` is called
- **THEN** `log.entries.count` SHALL equal `3`
- **AND** `log.entries[0].op` SHALL equal `.batchBegin(label: "rename")`
- **AND** `log.entries[1].op` SHALL equal `.setText(target: id, text: "X")`
- **AND** `log.entries[2].op` SHALL equal `.batchEnd`

#### Scenario: batch closes its end marker on throw

- **GIVEN** an empty `OperationLog`
- **WHEN** `log.batch(.swift) { _ in throw SomeError() }` is called and rethrows
- **THEN** the rethrow SHALL surface to the caller
- **AND** `log.entries.count` SHALL equal `1` (the `batchBegin` was appended; the body threw before any further appends; the implementation MAY rethrow before appending `batchEnd`)

(This scenario pins the contract that batch is a best-effort transaction marker, NOT a rollback mechanism. Rollback is a Phase 2b reducer concern.)


<!-- @trace
source: operation-log-scaffold-impl
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-143628.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-050704.log
-->


<!-- @trace
source: word-aligned-state-sync
updated: 2026-07-06
code:
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-144618.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/AnchorResolver.swift
  - .remember/logs/autonomous/save-095118.log
  - plugins/macdoc/hooks/hooks.json
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-143020.log
  - Sources/MacDocCLI/MacDoc+Word.swift
  - .remember/logs/autonomous/save-133659.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093340.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-095142.log
  - plugins/che-pdf-mcp/bin/che-pdf-mcp-wrapper.sh
  - reference/README.md
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-144433.log
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - .remember/logs/autonomous/save-090944.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ExecutorTests.swift
  - .remember/logs/autonomous/save-092853.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGeneratorTests.swift
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - plugins/che-pptx-mcp/bin/che-pptx-mcp-wrapper.sh
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-125453.log
  - mcp/che-pdf-mcp
  - .remember/logs/autonomous/save-070717.log
  - plugins/che-pptx-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-094627.log
  - .claude-plugin/marketplace.json
  - Package.swift
  - .remember/logs/autonomous/save-053409.log
  - plugins/che-pptx-mcp/README.md
  - plugins/macdoc/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-095621.log
  - README.md
  - .remember/logs/autonomous/save-093255.log
  - docs/lossless-conversion.md
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorDecodingTests.swift
  - Package.resolved
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-130300.log
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - mcp/che-pptx-mcp
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093039.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/DocxWorkflowLib.swift
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/VerifyAssertions.swift
  - packages/docx-workflow-swift/Package.swift
  - .github/PULL_REQUEST_TEMPLATE.md
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-093030.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Manifest.swift
  - .remember/logs/autonomous/save-093138.log
  - cli/FastOCR
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-095539.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Anchor.swift
  - plugins/che-word-mcp/CLAUDE.md
  - plugins/macdoc/skills/macdoc/SKILL.md
  - .remember/logs/autonomous/save-095047.log
  - plugins/che-word-mcp/README.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Tests/MacDocCLITests/NoteHTMLConvertTests.swift
  - plugins/che-pdf-mcp/skills/che-pdf-mcp/SKILL.md
  - plugins/che-word-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-125949.log
  - plugins/che-word-mcp/.mcp.json
  - .github/skills/spectra-drift/SKILL.md
  - plugins/che-pdf-mcp/README.md
  - docs/stale-triage-chain-2026-05-25.md
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-132950.log
  - plugins/che-pdf-mcp/CHANGELOG.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/EditPlanner.swift
  - plugins/che-word-mcp/bin/che-word-mcp-wrapper.sh
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093013.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ManifestDecodingTests.swift
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-132859.log
  - plugins/che-word-mcp/CHANGELOG.md
  - Sources/MacDocCLI/MacDoc.swift
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143733.log
  - plugins/macdoc/hooks/session-start.sh
  - packages/docx-workflow-swift/CHANGELOG.md
  - .remember/logs/autonomous/save-144132.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifierTests.swift
  - plugins/che-pdf-mcp/.claude-plugin/plugin.json
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-144003.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Executor.swift
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093149.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Verifier.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifyAssertionsDecodingTests.swift
  - plugins/che-pptx-mcp/.mcp.json
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - scripts/release-cli.sh
  - .remember/logs/autonomous/save-143856.log
  - CLAUDE.md
  - .remember/logs/autonomous/save-144708.log
  - Tests/MacDocCLITests/Fixtures/README.md
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095546.log
  - .gitmodules
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-090656.log
  - packages/docx-workflow-swift/README.md
  - plugins/che-pptx-mcp/CHANGELOG.md
  - .remember/logs/autonomous/save-051714.log
  - plugins/che-pdf-mcp/.mcp.json
  - .remember/logs/autonomous/save-093825.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGenerator.swift
  - plugins/macdoc/CHANGELOG.md
  - plugins/che-word-mcp/skills/che-word-mcp/SKILL.md
  - .remember/logs/autonomous/save-091107.log
  - docs/edit-algebra-cd-discipline.md
  - docs/structural-editing-paradigm.md
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-131902.log
  - .github/prompts/spectra-drift.prompt.md
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-050705.log
  - docs/docx-libraries-comparison.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/ParagraphSnapshot.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorResolverTests.swift
  - docs/stale-triage-chain-batch2-2026-05-25.md
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-143700.log
-->

---
### Requirement: JSONL on-disk format

`OperationLog.encodeJSONL() -> Data` SHALL serialize the log to UTF-8 bytes containing one JSON object per `LogEntry`, separated by Unix line-feed characters (`0x0A`). Each line SHALL be a complete JSON object containing at minimum the four required fields:

- `"op_id"`: `LogEntry.opID.uuidString` (uppercase hex with dashes)
- `"ts"`: `LogEntry.timestamp` formatted as ISO-8601 UTC (e.g., `"2026-05-07T01:30:00Z"`)
- `"source"`: `"swift"` or `"word"`
- `"op_type"`: a string discriminator naming the `Operation` case (e.g., `"setText"`, `"insertParagraphAfter"`, `"unknown"`)

After the four required fields, op-specific fields SHALL be emitted in the order their associated values declare. For typed cases this gives a deterministic field order. For the `.unknown(opType:payload:)` case, the carried `JSONValue` payload SHALL be merged into the line verbatim, with payload object keys sorted lexicographically to maintain byte-equal round-trip.

`OperationLog.decodeJSONL(_ data: Data) throws -> OperationLog` SHALL parse newline-delimited JSON objects back into a log. Each line SHALL be required to have the four discriminator fields; otherwise decode SHALL throw a typed `OperationLogJSONLError.malformedLine(lineIndex:)` error.

Encoding is the inverse of decoding for typed cases: `decode(encode(log)) == log` for any `OperationLog` containing only typed cases.

For unknown ops: encoding an `OperationLog` containing a `.unknown(opType:, payload:)` SHALL produce the same JSON bytes that the original lossless line had (assuming the `.unknown` was constructed from JSONL decode of those bytes). This is the forward-compat round-trip guarantee.

#### Scenario: known-ops JSONL round-trip is byte-equal

- **GIVEN** an `OperationLog` constructed in code with one entry: `(opID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!, op: .setText(target: ElementID(rawString: "w14:paraId=0ABC1234"), text: "Hello"), source: .swift, timestamp: Date(timeIntervalSince1970: 1747500000))`
- **WHEN** `let bytes = log.encodeJSONL()` then `let decoded = OperationLog.decodeJSONL(bytes)` then `let bytes2 = decoded.encodeJSONL()`
- **THEN** `bytes` SHALL equal `bytes2` (byte-equal)
- **AND** `decoded` SHALL equal `log` (`Equatable` round-trip)

#### Scenario: unknown op_type round-trips byte-equal via the .unknown fallback

- **GIVEN** a JSONL line containing an op_type `setRunStrikethrough` that this version of `Operation` does not declare: `{"op_id":"22222222-2222-4222-8222-222222222222","ts":"2026-05-07T02:00:00Z","source":"swift","op_type":"setRunStrikethrough","target":"w14:paraId=Z","strike":true}`
- **WHEN** `OperationLog.decodeJSONL` is called on a Data wrapping that line
- **THEN** the decoded log SHALL contain one entry whose `op` matches `.unknown(opType: "setRunStrikethrough", payload: <JSONValue containing target + strike>)`
- **AND** when `encodeJSONL` is called on the decoded log
- **THEN** the resulting bytes SHALL be byte-equal to the input line bytes (with payload object keys sorted lexicographically — `strike` before `target` per ASCII order)

#### Scenario: malformed line throws

- **GIVEN** input bytes containing a line that is valid JSON but missing one of the four required fields (e.g., missing `op_type`)
- **WHEN** `OperationLog.decodeJSONL` is called
- **THEN** the call SHALL throw `OperationLogJSONLError.malformedLine(lineIndex:)` with the index of the offending line


<!-- @trace
source: operation-log-scaffold-impl
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-143628.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-050704.log
-->


<!-- @trace
source: word-aligned-state-sync
updated: 2026-07-06
code:
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-144618.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/AnchorResolver.swift
  - .remember/logs/autonomous/save-095118.log
  - plugins/macdoc/hooks/hooks.json
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-143020.log
  - Sources/MacDocCLI/MacDoc+Word.swift
  - .remember/logs/autonomous/save-133659.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093340.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-095142.log
  - plugins/che-pdf-mcp/bin/che-pdf-mcp-wrapper.sh
  - reference/README.md
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-144433.log
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - .remember/logs/autonomous/save-090944.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ExecutorTests.swift
  - .remember/logs/autonomous/save-092853.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGeneratorTests.swift
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - plugins/che-pptx-mcp/bin/che-pptx-mcp-wrapper.sh
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-125453.log
  - mcp/che-pdf-mcp
  - .remember/logs/autonomous/save-070717.log
  - plugins/che-pptx-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-094627.log
  - .claude-plugin/marketplace.json
  - Package.swift
  - .remember/logs/autonomous/save-053409.log
  - plugins/che-pptx-mcp/README.md
  - plugins/macdoc/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-095621.log
  - README.md
  - .remember/logs/autonomous/save-093255.log
  - docs/lossless-conversion.md
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorDecodingTests.swift
  - Package.resolved
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-130300.log
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - mcp/che-pptx-mcp
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093039.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/DocxWorkflowLib.swift
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/VerifyAssertions.swift
  - packages/docx-workflow-swift/Package.swift
  - .github/PULL_REQUEST_TEMPLATE.md
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-093030.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Manifest.swift
  - .remember/logs/autonomous/save-093138.log
  - cli/FastOCR
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-095539.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Anchor.swift
  - plugins/che-word-mcp/CLAUDE.md
  - plugins/macdoc/skills/macdoc/SKILL.md
  - .remember/logs/autonomous/save-095047.log
  - plugins/che-word-mcp/README.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Tests/MacDocCLITests/NoteHTMLConvertTests.swift
  - plugins/che-pdf-mcp/skills/che-pdf-mcp/SKILL.md
  - plugins/che-word-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-125949.log
  - plugins/che-word-mcp/.mcp.json
  - .github/skills/spectra-drift/SKILL.md
  - plugins/che-pdf-mcp/README.md
  - docs/stale-triage-chain-2026-05-25.md
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-132950.log
  - plugins/che-pdf-mcp/CHANGELOG.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/EditPlanner.swift
  - plugins/che-word-mcp/bin/che-word-mcp-wrapper.sh
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093013.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ManifestDecodingTests.swift
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-132859.log
  - plugins/che-word-mcp/CHANGELOG.md
  - Sources/MacDocCLI/MacDoc.swift
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143733.log
  - plugins/macdoc/hooks/session-start.sh
  - packages/docx-workflow-swift/CHANGELOG.md
  - .remember/logs/autonomous/save-144132.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifierTests.swift
  - plugins/che-pdf-mcp/.claude-plugin/plugin.json
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-144003.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Executor.swift
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093149.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Verifier.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifyAssertionsDecodingTests.swift
  - plugins/che-pptx-mcp/.mcp.json
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - scripts/release-cli.sh
  - .remember/logs/autonomous/save-143856.log
  - CLAUDE.md
  - .remember/logs/autonomous/save-144708.log
  - Tests/MacDocCLITests/Fixtures/README.md
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095546.log
  - .gitmodules
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-090656.log
  - packages/docx-workflow-swift/README.md
  - plugins/che-pptx-mcp/CHANGELOG.md
  - .remember/logs/autonomous/save-051714.log
  - plugins/che-pdf-mcp/.mcp.json
  - .remember/logs/autonomous/save-093825.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGenerator.swift
  - plugins/macdoc/CHANGELOG.md
  - plugins/che-word-mcp/skills/che-word-mcp/SKILL.md
  - .remember/logs/autonomous/save-091107.log
  - docs/edit-algebra-cd-discipline.md
  - docs/structural-editing-paradigm.md
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-131902.log
  - .github/prompts/spectra-drift.prompt.md
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-050705.log
  - docs/docx-libraries-comparison.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/ParagraphSnapshot.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorResolverTests.swift
  - docs/stale-triage-chain-batch2-2026-05-25.md
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-143700.log
-->

---
### Requirement: Operation IDs are unique and stable

Every `LogEntry` SHALL carry a `UUID` v4 in its `opID` field. UUIDs SHALL be unique across all entries in any single log (UUID v4 collision probability is treated as zero per the cryptographic standard). UUIDs SHALL be stable: the value assigned at `append` time persists through serialization and deserialization unchanged.

#### Scenario: opID round-trips through JSONL byte-equal

- **GIVEN** a log entry with `opID == UUID(uuidString: "AABBCCDD-1234-4567-8999-EEFF00112233")!`
- **WHEN** the log is encoded to JSONL and decoded back
- **THEN** the decoded entry's `opID` SHALL equal `UUID(uuidString: "AABBCCDD-1234-4567-8999-EEFF00112233")!`


<!-- @trace
source: operation-log-scaffold-impl
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-143628.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-050704.log
-->


<!-- @trace
source: word-aligned-state-sync
updated: 2026-07-06
code:
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-144618.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/AnchorResolver.swift
  - .remember/logs/autonomous/save-095118.log
  - plugins/macdoc/hooks/hooks.json
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-143020.log
  - Sources/MacDocCLI/MacDoc+Word.swift
  - .remember/logs/autonomous/save-133659.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093340.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-095142.log
  - plugins/che-pdf-mcp/bin/che-pdf-mcp-wrapper.sh
  - reference/README.md
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-144433.log
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - .remember/logs/autonomous/save-090944.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ExecutorTests.swift
  - .remember/logs/autonomous/save-092853.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGeneratorTests.swift
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - plugins/che-pptx-mcp/bin/che-pptx-mcp-wrapper.sh
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-125453.log
  - mcp/che-pdf-mcp
  - .remember/logs/autonomous/save-070717.log
  - plugins/che-pptx-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-094627.log
  - .claude-plugin/marketplace.json
  - Package.swift
  - .remember/logs/autonomous/save-053409.log
  - plugins/che-pptx-mcp/README.md
  - plugins/macdoc/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-095621.log
  - README.md
  - .remember/logs/autonomous/save-093255.log
  - docs/lossless-conversion.md
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorDecodingTests.swift
  - Package.resolved
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-130300.log
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - mcp/che-pptx-mcp
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093039.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/DocxWorkflowLib.swift
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/VerifyAssertions.swift
  - packages/docx-workflow-swift/Package.swift
  - .github/PULL_REQUEST_TEMPLATE.md
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-093030.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Manifest.swift
  - .remember/logs/autonomous/save-093138.log
  - cli/FastOCR
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-095539.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Anchor.swift
  - plugins/che-word-mcp/CLAUDE.md
  - plugins/macdoc/skills/macdoc/SKILL.md
  - .remember/logs/autonomous/save-095047.log
  - plugins/che-word-mcp/README.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Tests/MacDocCLITests/NoteHTMLConvertTests.swift
  - plugins/che-pdf-mcp/skills/che-pdf-mcp/SKILL.md
  - plugins/che-word-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-125949.log
  - plugins/che-word-mcp/.mcp.json
  - .github/skills/spectra-drift/SKILL.md
  - plugins/che-pdf-mcp/README.md
  - docs/stale-triage-chain-2026-05-25.md
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-132950.log
  - plugins/che-pdf-mcp/CHANGELOG.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/EditPlanner.swift
  - plugins/che-word-mcp/bin/che-word-mcp-wrapper.sh
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093013.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ManifestDecodingTests.swift
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-132859.log
  - plugins/che-word-mcp/CHANGELOG.md
  - Sources/MacDocCLI/MacDoc.swift
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143733.log
  - plugins/macdoc/hooks/session-start.sh
  - packages/docx-workflow-swift/CHANGELOG.md
  - .remember/logs/autonomous/save-144132.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifierTests.swift
  - plugins/che-pdf-mcp/.claude-plugin/plugin.json
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-144003.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Executor.swift
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093149.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Verifier.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifyAssertionsDecodingTests.swift
  - plugins/che-pptx-mcp/.mcp.json
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - scripts/release-cli.sh
  - .remember/logs/autonomous/save-143856.log
  - CLAUDE.md
  - .remember/logs/autonomous/save-144708.log
  - Tests/MacDocCLITests/Fixtures/README.md
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095546.log
  - .gitmodules
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-090656.log
  - packages/docx-workflow-swift/README.md
  - plugins/che-pptx-mcp/CHANGELOG.md
  - .remember/logs/autonomous/save-051714.log
  - plugins/che-pdf-mcp/.mcp.json
  - .remember/logs/autonomous/save-093825.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGenerator.swift
  - plugins/macdoc/CHANGELOG.md
  - plugins/che-word-mcp/skills/che-word-mcp/SKILL.md
  - .remember/logs/autonomous/save-091107.log
  - docs/edit-algebra-cd-discipline.md
  - docs/structural-editing-paradigm.md
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-131902.log
  - .github/prompts/spectra-drift.prompt.md
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-050705.log
  - docs/docx-libraries-comparison.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/ParagraphSnapshot.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorResolverTests.swift
  - docs/stale-triage-chain-batch2-2026-05-25.md
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-143700.log
-->

---
### Requirement: Source attribution for every operation

Every `LogEntry` SHALL carry a `source: OpSource` field whose value is `.swift` (Swift code emitted the op) or `.word` (Word app's edit was the source — used by Phase 3 SyncOrchestrator import).

#### Scenario: source round-trips through JSONL

- **GIVEN** a log with one entry of source `.word`
- **WHEN** the log is encoded to JSONL and decoded back
- **THEN** the decoded entry's `source` SHALL equal `.word`


<!-- @trace
source: operation-log-scaffold-impl
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-143628.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-050704.log
-->


<!-- @trace
source: word-aligned-state-sync
updated: 2026-07-06
code:
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-144618.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/AnchorResolver.swift
  - .remember/logs/autonomous/save-095118.log
  - plugins/macdoc/hooks/hooks.json
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-143020.log
  - Sources/MacDocCLI/MacDoc+Word.swift
  - .remember/logs/autonomous/save-133659.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093340.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-095142.log
  - plugins/che-pdf-mcp/bin/che-pdf-mcp-wrapper.sh
  - reference/README.md
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-144433.log
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - .remember/logs/autonomous/save-090944.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ExecutorTests.swift
  - .remember/logs/autonomous/save-092853.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGeneratorTests.swift
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - plugins/che-pptx-mcp/bin/che-pptx-mcp-wrapper.sh
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-125453.log
  - mcp/che-pdf-mcp
  - .remember/logs/autonomous/save-070717.log
  - plugins/che-pptx-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-094627.log
  - .claude-plugin/marketplace.json
  - Package.swift
  - .remember/logs/autonomous/save-053409.log
  - plugins/che-pptx-mcp/README.md
  - plugins/macdoc/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-095621.log
  - README.md
  - .remember/logs/autonomous/save-093255.log
  - docs/lossless-conversion.md
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorDecodingTests.swift
  - Package.resolved
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-130300.log
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - mcp/che-pptx-mcp
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093039.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/DocxWorkflowLib.swift
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/VerifyAssertions.swift
  - packages/docx-workflow-swift/Package.swift
  - .github/PULL_REQUEST_TEMPLATE.md
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-093030.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Manifest.swift
  - .remember/logs/autonomous/save-093138.log
  - cli/FastOCR
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-095539.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Anchor.swift
  - plugins/che-word-mcp/CLAUDE.md
  - plugins/macdoc/skills/macdoc/SKILL.md
  - .remember/logs/autonomous/save-095047.log
  - plugins/che-word-mcp/README.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Tests/MacDocCLITests/NoteHTMLConvertTests.swift
  - plugins/che-pdf-mcp/skills/che-pdf-mcp/SKILL.md
  - plugins/che-word-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-125949.log
  - plugins/che-word-mcp/.mcp.json
  - .github/skills/spectra-drift/SKILL.md
  - plugins/che-pdf-mcp/README.md
  - docs/stale-triage-chain-2026-05-25.md
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-132950.log
  - plugins/che-pdf-mcp/CHANGELOG.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/EditPlanner.swift
  - plugins/che-word-mcp/bin/che-word-mcp-wrapper.sh
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093013.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ManifestDecodingTests.swift
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-132859.log
  - plugins/che-word-mcp/CHANGELOG.md
  - Sources/MacDocCLI/MacDoc.swift
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143733.log
  - plugins/macdoc/hooks/session-start.sh
  - packages/docx-workflow-swift/CHANGELOG.md
  - .remember/logs/autonomous/save-144132.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifierTests.swift
  - plugins/che-pdf-mcp/.claude-plugin/plugin.json
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-144003.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Executor.swift
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093149.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Verifier.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifyAssertionsDecodingTests.swift
  - plugins/che-pptx-mcp/.mcp.json
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - scripts/release-cli.sh
  - .remember/logs/autonomous/save-143856.log
  - CLAUDE.md
  - .remember/logs/autonomous/save-144708.log
  - Tests/MacDocCLITests/Fixtures/README.md
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095546.log
  - .gitmodules
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-090656.log
  - packages/docx-workflow-swift/README.md
  - plugins/che-pptx-mcp/CHANGELOG.md
  - .remember/logs/autonomous/save-051714.log
  - plugins/che-pdf-mcp/.mcp.json
  - .remember/logs/autonomous/save-093825.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGenerator.swift
  - plugins/macdoc/CHANGELOG.md
  - plugins/che-word-mcp/skills/che-word-mcp/SKILL.md
  - .remember/logs/autonomous/save-091107.log
  - docs/edit-algebra-cd-discipline.md
  - docs/structural-editing-paradigm.md
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-131902.log
  - .github/prompts/spectra-drift.prompt.md
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-050705.log
  - docs/docx-libraries-comparison.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/ParagraphSnapshot.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorResolverTests.swift
  - docs/stale-triage-chain-batch2-2026-05-25.md
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-143700.log
-->

---
### Requirement: Forward-compatible log format

The `OperationLog` JSONL on-disk format SHALL preserve unknown `op_type` values byte-equal across encode → decode → encode cycles. This forward-compat guarantee enables version-skewed log files: a log emitted by ooxml-swift v0.31.4 SHALL be decode-able by an older v0.31.3 reader, with v0.31.3 carrying any newer ops as `.unknown` and re-emitting them byte-identically.

#### Scenario: ooxml-swift v0.31.4 emits an op v0.31.3 doesn't recognize

- **GIVEN** a JSONL log containing an op_type that the local code's `Operation` enum does not declare
- **WHEN** the local code reads the log via `decodeJSONL`, appends one local typed op, and re-emits the log via `encodeJSONL`
- **THEN** the re-emitted bytes SHALL contain the original unknown line byte-equal to its input form
- **AND** the new typed op line SHALL appear after it in the expected JSONL format


<!-- @trace
source: operation-log-scaffold-impl
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-143628.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-050704.log
-->


<!-- @trace
source: word-aligned-state-sync
updated: 2026-07-06
code:
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-144618.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/AnchorResolver.swift
  - .remember/logs/autonomous/save-095118.log
  - plugins/macdoc/hooks/hooks.json
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-143020.log
  - Sources/MacDocCLI/MacDoc+Word.swift
  - .remember/logs/autonomous/save-133659.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093340.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-095142.log
  - plugins/che-pdf-mcp/bin/che-pdf-mcp-wrapper.sh
  - reference/README.md
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-144433.log
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - .remember/logs/autonomous/save-090944.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ExecutorTests.swift
  - .remember/logs/autonomous/save-092853.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGeneratorTests.swift
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - plugins/che-pptx-mcp/bin/che-pptx-mcp-wrapper.sh
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-125453.log
  - mcp/che-pdf-mcp
  - .remember/logs/autonomous/save-070717.log
  - plugins/che-pptx-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-094627.log
  - .claude-plugin/marketplace.json
  - Package.swift
  - .remember/logs/autonomous/save-053409.log
  - plugins/che-pptx-mcp/README.md
  - plugins/macdoc/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-095621.log
  - README.md
  - .remember/logs/autonomous/save-093255.log
  - docs/lossless-conversion.md
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorDecodingTests.swift
  - Package.resolved
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-130300.log
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - mcp/che-pptx-mcp
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093039.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/DocxWorkflowLib.swift
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/VerifyAssertions.swift
  - packages/docx-workflow-swift/Package.swift
  - .github/PULL_REQUEST_TEMPLATE.md
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-093030.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Manifest.swift
  - .remember/logs/autonomous/save-093138.log
  - cli/FastOCR
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-095539.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Anchor.swift
  - plugins/che-word-mcp/CLAUDE.md
  - plugins/macdoc/skills/macdoc/SKILL.md
  - .remember/logs/autonomous/save-095047.log
  - plugins/che-word-mcp/README.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Tests/MacDocCLITests/NoteHTMLConvertTests.swift
  - plugins/che-pdf-mcp/skills/che-pdf-mcp/SKILL.md
  - plugins/che-word-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-125949.log
  - plugins/che-word-mcp/.mcp.json
  - .github/skills/spectra-drift/SKILL.md
  - plugins/che-pdf-mcp/README.md
  - docs/stale-triage-chain-2026-05-25.md
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-132950.log
  - plugins/che-pdf-mcp/CHANGELOG.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/EditPlanner.swift
  - plugins/che-word-mcp/bin/che-word-mcp-wrapper.sh
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093013.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ManifestDecodingTests.swift
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-132859.log
  - plugins/che-word-mcp/CHANGELOG.md
  - Sources/MacDocCLI/MacDoc.swift
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143733.log
  - plugins/macdoc/hooks/session-start.sh
  - packages/docx-workflow-swift/CHANGELOG.md
  - .remember/logs/autonomous/save-144132.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifierTests.swift
  - plugins/che-pdf-mcp/.claude-plugin/plugin.json
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-144003.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Executor.swift
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093149.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Verifier.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifyAssertionsDecodingTests.swift
  - plugins/che-pptx-mcp/.mcp.json
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - scripts/release-cli.sh
  - .remember/logs/autonomous/save-143856.log
  - CLAUDE.md
  - .remember/logs/autonomous/save-144708.log
  - Tests/MacDocCLITests/Fixtures/README.md
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095546.log
  - .gitmodules
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-090656.log
  - packages/docx-workflow-swift/README.md
  - plugins/che-pptx-mcp/CHANGELOG.md
  - .remember/logs/autonomous/save-051714.log
  - plugins/che-pdf-mcp/.mcp.json
  - .remember/logs/autonomous/save-093825.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGenerator.swift
  - plugins/macdoc/CHANGELOG.md
  - plugins/che-word-mcp/skills/che-word-mcp/SKILL.md
  - .remember/logs/autonomous/save-091107.log
  - docs/edit-algebra-cd-discipline.md
  - docs/structural-editing-paradigm.md
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-131902.log
  - .github/prompts/spectra-drift.prompt.md
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-050705.log
  - docs/docx-libraries-comparison.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/ParagraphSnapshot.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorResolverTests.swift
  - docs/stale-triage-chain-batch2-2026-05-25.md
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-143700.log
-->

---
### Requirement: Batch transactions for grouped mutations

`OperationLog.batch(_:label:_:)` SHALL emit a `batchBegin(label:)` op before the closure body executes and a `batchEnd` op after the closure body returns normally. The label SHALL be carried in the `batchBegin` op's associated value for human-readable correlation in log diffs and audits.

#### Scenario: batch emits begin/end markers around body ops

- **WHEN** `log.batch(.swift, label: "rename") { lb in lb.append(.setText(...), source: .swift); lb.append(.setParagraphStyle(...), source: .swift) }` is called
- **THEN** `log.entries.count` SHALL equal `4`
- **AND** the entries SHALL be `[batchBegin(label: "rename"), setText(...), setParagraphStyle(...), batchEnd]` in that order


<!-- @trace
source: operation-log-scaffold-impl
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-143628.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-050704.log
-->


<!-- @trace
source: word-aligned-state-sync
updated: 2026-07-06
code:
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-144618.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/AnchorResolver.swift
  - .remember/logs/autonomous/save-095118.log
  - plugins/macdoc/hooks/hooks.json
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-143020.log
  - Sources/MacDocCLI/MacDoc+Word.swift
  - .remember/logs/autonomous/save-133659.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093340.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-095142.log
  - plugins/che-pdf-mcp/bin/che-pdf-mcp-wrapper.sh
  - reference/README.md
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-144433.log
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - .remember/logs/autonomous/save-090944.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ExecutorTests.swift
  - .remember/logs/autonomous/save-092853.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGeneratorTests.swift
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - plugins/che-pptx-mcp/bin/che-pptx-mcp-wrapper.sh
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-125453.log
  - mcp/che-pdf-mcp
  - .remember/logs/autonomous/save-070717.log
  - plugins/che-pptx-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-094627.log
  - .claude-plugin/marketplace.json
  - Package.swift
  - .remember/logs/autonomous/save-053409.log
  - plugins/che-pptx-mcp/README.md
  - plugins/macdoc/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-095621.log
  - README.md
  - .remember/logs/autonomous/save-093255.log
  - docs/lossless-conversion.md
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorDecodingTests.swift
  - Package.resolved
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-130300.log
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - mcp/che-pptx-mcp
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093039.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/DocxWorkflowLib.swift
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/VerifyAssertions.swift
  - packages/docx-workflow-swift/Package.swift
  - .github/PULL_REQUEST_TEMPLATE.md
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-093030.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Manifest.swift
  - .remember/logs/autonomous/save-093138.log
  - cli/FastOCR
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-095539.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Anchor.swift
  - plugins/che-word-mcp/CLAUDE.md
  - plugins/macdoc/skills/macdoc/SKILL.md
  - .remember/logs/autonomous/save-095047.log
  - plugins/che-word-mcp/README.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Tests/MacDocCLITests/NoteHTMLConvertTests.swift
  - plugins/che-pdf-mcp/skills/che-pdf-mcp/SKILL.md
  - plugins/che-word-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-125949.log
  - plugins/che-word-mcp/.mcp.json
  - .github/skills/spectra-drift/SKILL.md
  - plugins/che-pdf-mcp/README.md
  - docs/stale-triage-chain-2026-05-25.md
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-132950.log
  - plugins/che-pdf-mcp/CHANGELOG.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/EditPlanner.swift
  - plugins/che-word-mcp/bin/che-word-mcp-wrapper.sh
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093013.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ManifestDecodingTests.swift
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-132859.log
  - plugins/che-word-mcp/CHANGELOG.md
  - Sources/MacDocCLI/MacDoc.swift
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143733.log
  - plugins/macdoc/hooks/session-start.sh
  - packages/docx-workflow-swift/CHANGELOG.md
  - .remember/logs/autonomous/save-144132.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifierTests.swift
  - plugins/che-pdf-mcp/.claude-plugin/plugin.json
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-144003.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Executor.swift
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093149.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Verifier.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifyAssertionsDecodingTests.swift
  - plugins/che-pptx-mcp/.mcp.json
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - scripts/release-cli.sh
  - .remember/logs/autonomous/save-143856.log
  - CLAUDE.md
  - .remember/logs/autonomous/save-144708.log
  - Tests/MacDocCLITests/Fixtures/README.md
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095546.log
  - .gitmodules
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-090656.log
  - packages/docx-workflow-swift/README.md
  - plugins/che-pptx-mcp/CHANGELOG.md
  - .remember/logs/autonomous/save-051714.log
  - plugins/che-pdf-mcp/.mcp.json
  - .remember/logs/autonomous/save-093825.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGenerator.swift
  - plugins/macdoc/CHANGELOG.md
  - plugins/che-word-mcp/skills/che-word-mcp/SKILL.md
  - .remember/logs/autonomous/save-091107.log
  - docs/edit-algebra-cd-discipline.md
  - docs/structural-editing-paradigm.md
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-131902.log
  - .github/prompts/spectra-drift.prompt.md
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-050705.log
  - docs/docx-libraries-comparison.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/ParagraphSnapshot.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorResolverTests.swift
  - docs/stale-triage-chain-batch2-2026-05-25.md
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-143700.log
-->

---
### Requirement: OpLog tests pinned coverage

A new test file `Tests/OOXMLSwiftTests/OperationLogTests.swift` SHALL be added with at least 8 XCTestCase methods pinning the requirements above:

1. `testOperationEnumEachCaseConstructsAndMatches` — exhaustive case construction + pattern match
2. `testElementIDDerivesFromW14ParaId`
3. `testElementIDFallsBackToLibraryUUID`
4. `testElementIDReturnsNilForBareElement`
5. `testOperationLogAppendIncreasesCount`
6. `testOperationLogBatchWrapsBodyOps`
7. `testJSONLKnownOpsRoundTripByteEqual`
8. `testJSONLForwardCompatRoundTripByteEqual`

The tests SHALL pass GREEN against the implementation in the same release (no `#if false` gate phase).

#### Scenario: OperationLogTests passes GREEN

- **WHEN** `swift test --filter OperationLogTests` runs against this change
- **THEN** every test method SHALL pass
- **AND** the test runner SHALL report at least 8 passing tests with 0 failures

<!-- @trace
source: operation-log-scaffold-impl
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-143628.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-050704.log
-->

---
### Requirement: ID-based operations, never positional indices

Every `Operation` referencing a structural element SHALL identify the element by stable ID (`ElementID`), never by positional index. ID derivation order: existing OOXML stable IDs (`w14:paraId`, `w:bookmarkId`, `w:id` on comments, `r:id` on relationships) → library-generated UUID stored on the in-memory `XmlNode` when no OOXML ID exists.

#### Scenario: Operation references paragraph by ID

- **WHEN** the caller emits `InsertParagraphAfter(id:)` to insert a new paragraph after an existing paragraph
- **THEN** the operation carries the existing paragraph's `ElementID` (a `w14:paraId` GUID or library UUID), not its position

#### Scenario: Independent inserts commute

- **GIVEN** the log is empty and a base tree has paragraphs `p1`, `p2`, `p3`
- **WHEN** `op_a = InsertParagraphAfter(id: p1.id, ...)` and `op_b = InsertParagraphAfter(id: p3.id, ...)` are appended in either order, and the log is replayed
- **THEN** the resulting state is identical regardless of append order: a tree with the new paragraphs in their correct positions relative to `p1` and `p3`


<!-- @trace
source: word-aligned-state-sync
updated: 2026-07-06
code:
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-144618.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/AnchorResolver.swift
  - .remember/logs/autonomous/save-095118.log
  - plugins/macdoc/hooks/hooks.json
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-143020.log
  - Sources/MacDocCLI/MacDoc+Word.swift
  - .remember/logs/autonomous/save-133659.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093340.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-095142.log
  - plugins/che-pdf-mcp/bin/che-pdf-mcp-wrapper.sh
  - reference/README.md
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-144433.log
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - .remember/logs/autonomous/save-090944.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ExecutorTests.swift
  - .remember/logs/autonomous/save-092853.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGeneratorTests.swift
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - plugins/che-pptx-mcp/bin/che-pptx-mcp-wrapper.sh
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-125453.log
  - mcp/che-pdf-mcp
  - .remember/logs/autonomous/save-070717.log
  - plugins/che-pptx-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-094627.log
  - .claude-plugin/marketplace.json
  - Package.swift
  - .remember/logs/autonomous/save-053409.log
  - plugins/che-pptx-mcp/README.md
  - plugins/macdoc/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-095621.log
  - README.md
  - .remember/logs/autonomous/save-093255.log
  - docs/lossless-conversion.md
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorDecodingTests.swift
  - Package.resolved
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-130300.log
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - mcp/che-pptx-mcp
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093039.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/DocxWorkflowLib.swift
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/VerifyAssertions.swift
  - packages/docx-workflow-swift/Package.swift
  - .github/PULL_REQUEST_TEMPLATE.md
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-093030.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Manifest.swift
  - .remember/logs/autonomous/save-093138.log
  - cli/FastOCR
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-095539.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Anchor.swift
  - plugins/che-word-mcp/CLAUDE.md
  - plugins/macdoc/skills/macdoc/SKILL.md
  - .remember/logs/autonomous/save-095047.log
  - plugins/che-word-mcp/README.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Tests/MacDocCLITests/NoteHTMLConvertTests.swift
  - plugins/che-pdf-mcp/skills/che-pdf-mcp/SKILL.md
  - plugins/che-word-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-125949.log
  - plugins/che-word-mcp/.mcp.json
  - .github/skills/spectra-drift/SKILL.md
  - plugins/che-pdf-mcp/README.md
  - docs/stale-triage-chain-2026-05-25.md
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-132950.log
  - plugins/che-pdf-mcp/CHANGELOG.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/EditPlanner.swift
  - plugins/che-word-mcp/bin/che-word-mcp-wrapper.sh
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093013.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ManifestDecodingTests.swift
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-132859.log
  - plugins/che-word-mcp/CHANGELOG.md
  - Sources/MacDocCLI/MacDoc.swift
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143733.log
  - plugins/macdoc/hooks/session-start.sh
  - packages/docx-workflow-swift/CHANGELOG.md
  - .remember/logs/autonomous/save-144132.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifierTests.swift
  - plugins/che-pdf-mcp/.claude-plugin/plugin.json
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-144003.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Executor.swift
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093149.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Verifier.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifyAssertionsDecodingTests.swift
  - plugins/che-pptx-mcp/.mcp.json
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - scripts/release-cli.sh
  - .remember/logs/autonomous/save-143856.log
  - CLAUDE.md
  - .remember/logs/autonomous/save-144708.log
  - Tests/MacDocCLITests/Fixtures/README.md
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095546.log
  - .gitmodules
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-090656.log
  - packages/docx-workflow-swift/README.md
  - plugins/che-pptx-mcp/CHANGELOG.md
  - .remember/logs/autonomous/save-051714.log
  - plugins/che-pdf-mcp/.mcp.json
  - .remember/logs/autonomous/save-093825.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGenerator.swift
  - plugins/macdoc/CHANGELOG.md
  - plugins/che-word-mcp/skills/che-word-mcp/SKILL.md
  - .remember/logs/autonomous/save-091107.log
  - docs/edit-algebra-cd-discipline.md
  - docs/structural-editing-paradigm.md
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-131902.log
  - .github/prompts/spectra-drift.prompt.md
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-050705.log
  - docs/docx-libraries-comparison.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/ParagraphSnapshot.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorResolverTests.swift
  - docs/stale-triage-chain-batch2-2026-05-25.md
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-143700.log
-->

---
### Requirement: Authoring operations extend the taxonomy additively with OOXML-mirror naming

Operations required by the `.mdocx` authoring surface (`mdocx-grammar`) SHALL be added to the `Operation` enum additively: existing cases and their JSONL wire shapes SHALL NOT change. New operation names and payload field names SHALL mirror official OOXML (ECMA-376 WordprocessingML) vocabulary where a correspondence exists — the same naming policy `mdocx-grammar` mandates for DSL elements, extended to the op layer (#128). Ops with no OOXML correspondence SHALL be documented as explicit exceptions with justification.

This spec is the single normative home of the operation wire format. Other specs (`mdocx-grammar`, `ooxml-script-transcode`) SHALL reference operations by canonical name and SHALL NOT restate their shapes.

#### Scenario: New op names anchor to ECMA-376 vocabulary

- **WHEN** a new operation targeting run content is added
- **THEN** its name and payload reference the OOXML element vocabulary (`run` ↔ `<w:r>`, `tab` ↔ `<w:tab>`, `styleId` ↔ `<w:pStyle w:val>`), not invented synonyms

##### Example: OOXML-mirror correspondence table

| Op / payload field | OOXML anchor (ECMA-376 WordprocessingML) |
| --- | --- |
| `appendParagraph` / `insertParagraphAfter` target | `<w:p>` as child of `<w:body>` (or container) |
| `paraId` (ParagraphPayload) | `w14:paraId` attribute |
| `setRuns` | `<w:r>` children of `<w:p>` |
| `bold` (RunPayload) | `<w:b>` (§17.3.2.1 "b (Bold)") |
| `italic` (RunPayload) | `<w:i>` (§17.3.2.16, ECMA title "Italics"; field spelled `italic` for cross-payload consistency with the shipped `RunFormatPayload.italic`) |
| `color` (RunPayload) | `<w:color w:val>` |
| `styleId` | `<w:pStyle w:val>` reference / `<w:style w:styleId>` definition |
| `insertTab` | `<w:tab/>` (§17.3.3.24) inside `<w:r>` |
| `insertBreak` | `<w:br/>` (§17.3.3.1) inside `<w:r>` |
| `insertNoBreakHyphen` | `<w:noBreakHyphen/>` (§17.3.3.18) inside `<w:r>` |
| `beginComponent` / `endComponent` | (none — documented exception: op-log metadata) |


<!-- @trace
source: word-aligned-state-sync
updated: 2026-07-06
code:
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-144618.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/AnchorResolver.swift
  - .remember/logs/autonomous/save-095118.log
  - plugins/macdoc/hooks/hooks.json
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-143020.log
  - Sources/MacDocCLI/MacDoc+Word.swift
  - .remember/logs/autonomous/save-133659.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093340.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-095142.log
  - plugins/che-pdf-mcp/bin/che-pdf-mcp-wrapper.sh
  - reference/README.md
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-144433.log
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - .remember/logs/autonomous/save-090944.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ExecutorTests.swift
  - .remember/logs/autonomous/save-092853.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGeneratorTests.swift
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - plugins/che-pptx-mcp/bin/che-pptx-mcp-wrapper.sh
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-125453.log
  - mcp/che-pdf-mcp
  - .remember/logs/autonomous/save-070717.log
  - plugins/che-pptx-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-094627.log
  - .claude-plugin/marketplace.json
  - Package.swift
  - .remember/logs/autonomous/save-053409.log
  - plugins/che-pptx-mcp/README.md
  - plugins/macdoc/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-095621.log
  - README.md
  - .remember/logs/autonomous/save-093255.log
  - docs/lossless-conversion.md
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorDecodingTests.swift
  - Package.resolved
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-130300.log
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - mcp/che-pptx-mcp
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093039.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/DocxWorkflowLib.swift
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/VerifyAssertions.swift
  - packages/docx-workflow-swift/Package.swift
  - .github/PULL_REQUEST_TEMPLATE.md
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-093030.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Manifest.swift
  - .remember/logs/autonomous/save-093138.log
  - cli/FastOCR
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-095539.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Anchor.swift
  - plugins/che-word-mcp/CLAUDE.md
  - plugins/macdoc/skills/macdoc/SKILL.md
  - .remember/logs/autonomous/save-095047.log
  - plugins/che-word-mcp/README.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Tests/MacDocCLITests/NoteHTMLConvertTests.swift
  - plugins/che-pdf-mcp/skills/che-pdf-mcp/SKILL.md
  - plugins/che-word-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-125949.log
  - plugins/che-word-mcp/.mcp.json
  - .github/skills/spectra-drift/SKILL.md
  - plugins/che-pdf-mcp/README.md
  - docs/stale-triage-chain-2026-05-25.md
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-132950.log
  - plugins/che-pdf-mcp/CHANGELOG.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/EditPlanner.swift
  - plugins/che-word-mcp/bin/che-word-mcp-wrapper.sh
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093013.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ManifestDecodingTests.swift
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-132859.log
  - plugins/che-word-mcp/CHANGELOG.md
  - Sources/MacDocCLI/MacDoc.swift
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143733.log
  - plugins/macdoc/hooks/session-start.sh
  - packages/docx-workflow-swift/CHANGELOG.md
  - .remember/logs/autonomous/save-144132.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifierTests.swift
  - plugins/che-pdf-mcp/.claude-plugin/plugin.json
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-144003.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Executor.swift
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093149.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Verifier.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifyAssertionsDecodingTests.swift
  - plugins/che-pptx-mcp/.mcp.json
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - scripts/release-cli.sh
  - .remember/logs/autonomous/save-143856.log
  - CLAUDE.md
  - .remember/logs/autonomous/save-144708.log
  - Tests/MacDocCLITests/Fixtures/README.md
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095546.log
  - .gitmodules
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-090656.log
  - packages/docx-workflow-swift/README.md
  - plugins/che-pptx-mcp/CHANGELOG.md
  - .remember/logs/autonomous/save-051714.log
  - plugins/che-pdf-mcp/.mcp.json
  - .remember/logs/autonomous/save-093825.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGenerator.swift
  - plugins/macdoc/CHANGELOG.md
  - plugins/che-word-mcp/skills/che-word-mcp/SKILL.md
  - .remember/logs/autonomous/save-091107.log
  - docs/edit-algebra-cd-discipline.md
  - docs/structural-editing-paradigm.md
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-131902.log
  - .github/prompts/spectra-drift.prompt.md
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-050705.log
  - docs/docx-libraries-comparison.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/ParagraphSnapshot.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorResolverTests.swift
  - docs/stale-triage-chain-batch2-2026-05-25.md
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-143700.log
-->

---
### Requirement: AppendParagraph anchors construction-order inserts

The taxonomy SHALL include `appendParagraph(in: ElementID?, paragraph: ParagraphPayload)` appending a paragraph as the last block-level child of the container addressed by `in` (`nil` = the document body). This covers the authoring case where no preceding sibling exists yet; subsequent construction-order inserts SHALL use the existing `insertParagraphAfter(after:)` anchored on the previously emitted element. To carry the DSL's mandatory explicit identifiers (`mdocx-grammar` "Mandatory explicit identifiers on structural elements"), `ParagraphPayload` SHALL gain an optional `paraId` field (↔ `w14:paraId`); when present the reducer stamps it on the created `<w:p>`, when absent the existing opID-derived libraryUUID behavior applies unchanged. Addressing stays ID-based — no positional index parameter exists (per the "ID-based operations, never positional indices" requirement; `mdocx-grammar` example indices are derived display metadata, not addressing).

#### Scenario: First paragraph in an empty body

- **GIVEN** an empty document body and an empty log
- **WHEN** the DSL emits its first paragraph
- **THEN** the op is `appendParagraph(in: nil, paragraph: ...)`; the second paragraph emits `insertParagraphAfter(after: <first-id>)`


<!-- @trace
source: word-aligned-state-sync
updated: 2026-07-06
code:
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-144618.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/AnchorResolver.swift
  - .remember/logs/autonomous/save-095118.log
  - plugins/macdoc/hooks/hooks.json
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-143020.log
  - Sources/MacDocCLI/MacDoc+Word.swift
  - .remember/logs/autonomous/save-133659.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093340.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-095142.log
  - plugins/che-pdf-mcp/bin/che-pdf-mcp-wrapper.sh
  - reference/README.md
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-144433.log
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - .remember/logs/autonomous/save-090944.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ExecutorTests.swift
  - .remember/logs/autonomous/save-092853.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGeneratorTests.swift
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - plugins/che-pptx-mcp/bin/che-pptx-mcp-wrapper.sh
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-125453.log
  - mcp/che-pdf-mcp
  - .remember/logs/autonomous/save-070717.log
  - plugins/che-pptx-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-094627.log
  - .claude-plugin/marketplace.json
  - Package.swift
  - .remember/logs/autonomous/save-053409.log
  - plugins/che-pptx-mcp/README.md
  - plugins/macdoc/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-095621.log
  - README.md
  - .remember/logs/autonomous/save-093255.log
  - docs/lossless-conversion.md
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorDecodingTests.swift
  - Package.resolved
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-130300.log
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - mcp/che-pptx-mcp
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093039.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/DocxWorkflowLib.swift
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/VerifyAssertions.swift
  - packages/docx-workflow-swift/Package.swift
  - .github/PULL_REQUEST_TEMPLATE.md
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-093030.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Manifest.swift
  - .remember/logs/autonomous/save-093138.log
  - cli/FastOCR
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-095539.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Anchor.swift
  - plugins/che-word-mcp/CLAUDE.md
  - plugins/macdoc/skills/macdoc/SKILL.md
  - .remember/logs/autonomous/save-095047.log
  - plugins/che-word-mcp/README.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Tests/MacDocCLITests/NoteHTMLConvertTests.swift
  - plugins/che-pdf-mcp/skills/che-pdf-mcp/SKILL.md
  - plugins/che-word-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-125949.log
  - plugins/che-word-mcp/.mcp.json
  - .github/skills/spectra-drift/SKILL.md
  - plugins/che-pdf-mcp/README.md
  - docs/stale-triage-chain-2026-05-25.md
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-132950.log
  - plugins/che-pdf-mcp/CHANGELOG.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/EditPlanner.swift
  - plugins/che-word-mcp/bin/che-word-mcp-wrapper.sh
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093013.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ManifestDecodingTests.swift
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-132859.log
  - plugins/che-word-mcp/CHANGELOG.md
  - Sources/MacDocCLI/MacDoc.swift
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143733.log
  - plugins/macdoc/hooks/session-start.sh
  - packages/docx-workflow-swift/CHANGELOG.md
  - .remember/logs/autonomous/save-144132.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifierTests.swift
  - plugins/che-pdf-mcp/.claude-plugin/plugin.json
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-144003.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Executor.swift
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093149.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Verifier.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifyAssertionsDecodingTests.swift
  - plugins/che-pptx-mcp/.mcp.json
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - scripts/release-cli.sh
  - .remember/logs/autonomous/save-143856.log
  - CLAUDE.md
  - .remember/logs/autonomous/save-144708.log
  - Tests/MacDocCLITests/Fixtures/README.md
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095546.log
  - .gitmodules
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-090656.log
  - packages/docx-workflow-swift/README.md
  - plugins/che-pptx-mcp/CHANGELOG.md
  - .remember/logs/autonomous/save-051714.log
  - plugins/che-pdf-mcp/.mcp.json
  - .remember/logs/autonomous/save-093825.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGenerator.swift
  - plugins/macdoc/CHANGELOG.md
  - plugins/che-word-mcp/skills/che-word-mcp/SKILL.md
  - .remember/logs/autonomous/save-091107.log
  - docs/edit-algebra-cd-discipline.md
  - docs/structural-editing-paradigm.md
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-131902.log
  - .github/prompts/spectra-drift.prompt.md
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-050705.log
  - docs/docx-libraries-comparison.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/ParagraphSnapshot.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorResolverTests.swift
  - docs/stale-triage-chain-batch2-2026-05-25.md
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-143700.log
-->

---
### Requirement: SetRuns replaces inline content with typed run payloads

The taxonomy SHALL include `setRuns(target: ElementID, runs: [RunPayload])` replacing the addressed paragraph's inline content. The formatting fields SHALL be added to the existing `RunPayload` struct (which today carries only `text`) — NOT to the separate `RunFormatPayload` used by `setRunFormat` — as optionals: `bold` ↔ `<w:b>`, `italic` ↔ `<w:i>`, `color` ↔ `<w:color w:val>`. Spelling note: ECMA-376 titles `<w:i>` "Italics", but the field is spelled `italic` for cross-payload consistency with the shipped `RunFormatPayload.italic` (the OOXML anchor is the element `<w:i>` itself, which both spellings mirror).

#### Scenario: Formatted runs round-trip through the log

- **WHEN** `setRuns(target: p, runs: [{text: "本章探討"}, {text: "意識本質", bold: true}])` replays
- **THEN** the paragraph contains two `<w:r>` children in order, the second carrying `<w:rPr><w:b/></w:rPr>`


<!-- @trace
source: word-aligned-state-sync
updated: 2026-07-06
code:
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-144618.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/AnchorResolver.swift
  - .remember/logs/autonomous/save-095118.log
  - plugins/macdoc/hooks/hooks.json
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-143020.log
  - Sources/MacDocCLI/MacDoc+Word.swift
  - .remember/logs/autonomous/save-133659.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093340.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-095142.log
  - plugins/che-pdf-mcp/bin/che-pdf-mcp-wrapper.sh
  - reference/README.md
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-144433.log
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - .remember/logs/autonomous/save-090944.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ExecutorTests.swift
  - .remember/logs/autonomous/save-092853.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGeneratorTests.swift
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - plugins/che-pptx-mcp/bin/che-pptx-mcp-wrapper.sh
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-125453.log
  - mcp/che-pdf-mcp
  - .remember/logs/autonomous/save-070717.log
  - plugins/che-pptx-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-094627.log
  - .claude-plugin/marketplace.json
  - Package.swift
  - .remember/logs/autonomous/save-053409.log
  - plugins/che-pptx-mcp/README.md
  - plugins/macdoc/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-095621.log
  - README.md
  - .remember/logs/autonomous/save-093255.log
  - docs/lossless-conversion.md
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorDecodingTests.swift
  - Package.resolved
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-130300.log
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - mcp/che-pptx-mcp
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093039.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/DocxWorkflowLib.swift
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/VerifyAssertions.swift
  - packages/docx-workflow-swift/Package.swift
  - .github/PULL_REQUEST_TEMPLATE.md
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-093030.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Manifest.swift
  - .remember/logs/autonomous/save-093138.log
  - cli/FastOCR
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-095539.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Anchor.swift
  - plugins/che-word-mcp/CLAUDE.md
  - plugins/macdoc/skills/macdoc/SKILL.md
  - .remember/logs/autonomous/save-095047.log
  - plugins/che-word-mcp/README.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Tests/MacDocCLITests/NoteHTMLConvertTests.swift
  - plugins/che-pdf-mcp/skills/che-pdf-mcp/SKILL.md
  - plugins/che-word-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-125949.log
  - plugins/che-word-mcp/.mcp.json
  - .github/skills/spectra-drift/SKILL.md
  - plugins/che-pdf-mcp/README.md
  - docs/stale-triage-chain-2026-05-25.md
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-132950.log
  - plugins/che-pdf-mcp/CHANGELOG.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/EditPlanner.swift
  - plugins/che-word-mcp/bin/che-word-mcp-wrapper.sh
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093013.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ManifestDecodingTests.swift
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-132859.log
  - plugins/che-word-mcp/CHANGELOG.md
  - Sources/MacDocCLI/MacDoc.swift
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143733.log
  - plugins/macdoc/hooks/session-start.sh
  - packages/docx-workflow-swift/CHANGELOG.md
  - .remember/logs/autonomous/save-144132.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifierTests.swift
  - plugins/che-pdf-mcp/.claude-plugin/plugin.json
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-144003.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Executor.swift
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093149.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Verifier.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifyAssertionsDecodingTests.swift
  - plugins/che-pptx-mcp/.mcp.json
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - scripts/release-cli.sh
  - .remember/logs/autonomous/save-143856.log
  - CLAUDE.md
  - .remember/logs/autonomous/save-144708.log
  - Tests/MacDocCLITests/Fixtures/README.md
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095546.log
  - .gitmodules
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-090656.log
  - packages/docx-workflow-swift/README.md
  - plugins/che-pptx-mcp/CHANGELOG.md
  - .remember/logs/autonomous/save-051714.log
  - plugins/che-pdf-mcp/.mcp.json
  - .remember/logs/autonomous/save-093825.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGenerator.swift
  - plugins/macdoc/CHANGELOG.md
  - plugins/che-word-mcp/skills/che-word-mcp/SKILL.md
  - .remember/logs/autonomous/save-091107.log
  - docs/edit-algebra-cd-discipline.md
  - docs/structural-editing-paradigm.md
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-131902.log
  - .github/prompts/spectra-drift.prompt.md
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-050705.log
  - docs/docx-libraries-comparison.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/ParagraphSnapshot.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorResolverTests.swift
  - docs/stale-triage-chain-batch2-2026-05-25.md
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-143700.log
-->

---
### Requirement: DefineStyle registers style definitions once

The taxonomy SHALL include `defineStyle(payload: StylePayload)` carrying `styleId` (↔ `<w:style w:styleId>`) plus properties. Replaying a `defineStyle` whose `styleId` already exists SHALL be an idempotent no-op (define-on-first-use semantics from `mdocx-grammar` stay replay-safe).

#### Scenario: Duplicate defineStyle is idempotent

- **WHEN** two `defineStyle(styleId: "titleBrown", ...)` ops replay
- **THEN** styles.xml contains exactly one `titleBrown` definition and replay does not throw


<!-- @trace
source: word-aligned-state-sync
updated: 2026-07-06
code:
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-144618.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/AnchorResolver.swift
  - .remember/logs/autonomous/save-095118.log
  - plugins/macdoc/hooks/hooks.json
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-143020.log
  - Sources/MacDocCLI/MacDoc+Word.swift
  - .remember/logs/autonomous/save-133659.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093340.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-095142.log
  - plugins/che-pdf-mcp/bin/che-pdf-mcp-wrapper.sh
  - reference/README.md
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-144433.log
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - .remember/logs/autonomous/save-090944.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ExecutorTests.swift
  - .remember/logs/autonomous/save-092853.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGeneratorTests.swift
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - plugins/che-pptx-mcp/bin/che-pptx-mcp-wrapper.sh
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-125453.log
  - mcp/che-pdf-mcp
  - .remember/logs/autonomous/save-070717.log
  - plugins/che-pptx-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-094627.log
  - .claude-plugin/marketplace.json
  - Package.swift
  - .remember/logs/autonomous/save-053409.log
  - plugins/che-pptx-mcp/README.md
  - plugins/macdoc/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-095621.log
  - README.md
  - .remember/logs/autonomous/save-093255.log
  - docs/lossless-conversion.md
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorDecodingTests.swift
  - Package.resolved
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-130300.log
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - mcp/che-pptx-mcp
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093039.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/DocxWorkflowLib.swift
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/VerifyAssertions.swift
  - packages/docx-workflow-swift/Package.swift
  - .github/PULL_REQUEST_TEMPLATE.md
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-093030.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Manifest.swift
  - .remember/logs/autonomous/save-093138.log
  - cli/FastOCR
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-095539.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Anchor.swift
  - plugins/che-word-mcp/CLAUDE.md
  - plugins/macdoc/skills/macdoc/SKILL.md
  - .remember/logs/autonomous/save-095047.log
  - plugins/che-word-mcp/README.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Tests/MacDocCLITests/NoteHTMLConvertTests.swift
  - plugins/che-pdf-mcp/skills/che-pdf-mcp/SKILL.md
  - plugins/che-word-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-125949.log
  - plugins/che-word-mcp/.mcp.json
  - .github/skills/spectra-drift/SKILL.md
  - plugins/che-pdf-mcp/README.md
  - docs/stale-triage-chain-2026-05-25.md
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-132950.log
  - plugins/che-pdf-mcp/CHANGELOG.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/EditPlanner.swift
  - plugins/che-word-mcp/bin/che-word-mcp-wrapper.sh
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093013.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ManifestDecodingTests.swift
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-132859.log
  - plugins/che-word-mcp/CHANGELOG.md
  - Sources/MacDocCLI/MacDoc.swift
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143733.log
  - plugins/macdoc/hooks/session-start.sh
  - packages/docx-workflow-swift/CHANGELOG.md
  - .remember/logs/autonomous/save-144132.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifierTests.swift
  - plugins/che-pdf-mcp/.claude-plugin/plugin.json
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-144003.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Executor.swift
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093149.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Verifier.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifyAssertionsDecodingTests.swift
  - plugins/che-pptx-mcp/.mcp.json
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - scripts/release-cli.sh
  - .remember/logs/autonomous/save-143856.log
  - CLAUDE.md
  - .remember/logs/autonomous/save-144708.log
  - Tests/MacDocCLITests/Fixtures/README.md
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095546.log
  - .gitmodules
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-090656.log
  - packages/docx-workflow-swift/README.md
  - plugins/che-pptx-mcp/CHANGELOG.md
  - .remember/logs/autonomous/save-051714.log
  - plugins/che-pdf-mcp/.mcp.json
  - .remember/logs/autonomous/save-093825.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGenerator.swift
  - plugins/macdoc/CHANGELOG.md
  - plugins/che-word-mcp/skills/che-word-mcp/SKILL.md
  - .remember/logs/autonomous/save-091107.log
  - docs/edit-algebra-cd-discipline.md
  - docs/structural-editing-paradigm.md
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-131902.log
  - .github/prompts/spectra-drift.prompt.md
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-050705.log
  - docs/docx-libraries-comparison.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/ParagraphSnapshot.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorResolverTests.swift
  - docs/stale-triage-chain-batch2-2026-05-25.md
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-143700.log
-->

---
### Requirement: Component envelope ops are log metadata only

The taxonomy SHALL include `beginComponent(type: String, id: ElementID)` / `endComponent(id: ElementID)` bracketing a `WordComponent` expansion. **Documented exception to OOXML-mirror naming**: these have no OOXML correspondence by design — they are op-log metadata (like the batch markers) and SHALL produce zero elements in serialized OOXML; the reducer treats them as no-ops.

#### Scenario: Envelope produces no OOXML artifact

- **WHEN** a log containing a `beginComponent`/`endComponent` pair replays and the tree serializes
- **THEN** the output contains no element corresponding to either op


<!-- @trace
source: word-aligned-state-sync
updated: 2026-07-06
code:
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-144618.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/AnchorResolver.swift
  - .remember/logs/autonomous/save-095118.log
  - plugins/macdoc/hooks/hooks.json
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-143020.log
  - Sources/MacDocCLI/MacDoc+Word.swift
  - .remember/logs/autonomous/save-133659.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093340.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-095142.log
  - plugins/che-pdf-mcp/bin/che-pdf-mcp-wrapper.sh
  - reference/README.md
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-144433.log
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - .remember/logs/autonomous/save-090944.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ExecutorTests.swift
  - .remember/logs/autonomous/save-092853.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGeneratorTests.swift
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - plugins/che-pptx-mcp/bin/che-pptx-mcp-wrapper.sh
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-125453.log
  - mcp/che-pdf-mcp
  - .remember/logs/autonomous/save-070717.log
  - plugins/che-pptx-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-094627.log
  - .claude-plugin/marketplace.json
  - Package.swift
  - .remember/logs/autonomous/save-053409.log
  - plugins/che-pptx-mcp/README.md
  - plugins/macdoc/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-095621.log
  - README.md
  - .remember/logs/autonomous/save-093255.log
  - docs/lossless-conversion.md
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorDecodingTests.swift
  - Package.resolved
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-130300.log
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - mcp/che-pptx-mcp
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093039.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/DocxWorkflowLib.swift
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/VerifyAssertions.swift
  - packages/docx-workflow-swift/Package.swift
  - .github/PULL_REQUEST_TEMPLATE.md
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-093030.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Manifest.swift
  - .remember/logs/autonomous/save-093138.log
  - cli/FastOCR
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-095539.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Anchor.swift
  - plugins/che-word-mcp/CLAUDE.md
  - plugins/macdoc/skills/macdoc/SKILL.md
  - .remember/logs/autonomous/save-095047.log
  - plugins/che-word-mcp/README.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Tests/MacDocCLITests/NoteHTMLConvertTests.swift
  - plugins/che-pdf-mcp/skills/che-pdf-mcp/SKILL.md
  - plugins/che-word-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-125949.log
  - plugins/che-word-mcp/.mcp.json
  - .github/skills/spectra-drift/SKILL.md
  - plugins/che-pdf-mcp/README.md
  - docs/stale-triage-chain-2026-05-25.md
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-132950.log
  - plugins/che-pdf-mcp/CHANGELOG.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/EditPlanner.swift
  - plugins/che-word-mcp/bin/che-word-mcp-wrapper.sh
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093013.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ManifestDecodingTests.swift
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-132859.log
  - plugins/che-word-mcp/CHANGELOG.md
  - Sources/MacDocCLI/MacDoc.swift
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143733.log
  - plugins/macdoc/hooks/session-start.sh
  - packages/docx-workflow-swift/CHANGELOG.md
  - .remember/logs/autonomous/save-144132.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifierTests.swift
  - plugins/che-pdf-mcp/.claude-plugin/plugin.json
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-144003.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Executor.swift
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093149.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Verifier.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifyAssertionsDecodingTests.swift
  - plugins/che-pptx-mcp/.mcp.json
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - scripts/release-cli.sh
  - .remember/logs/autonomous/save-143856.log
  - CLAUDE.md
  - .remember/logs/autonomous/save-144708.log
  - Tests/MacDocCLITests/Fixtures/README.md
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095546.log
  - .gitmodules
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-090656.log
  - packages/docx-workflow-swift/README.md
  - plugins/che-pptx-mcp/CHANGELOG.md
  - .remember/logs/autonomous/save-051714.log
  - plugins/che-pdf-mcp/.mcp.json
  - .remember/logs/autonomous/save-093825.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGenerator.swift
  - plugins/macdoc/CHANGELOG.md
  - plugins/che-word-mcp/skills/che-word-mcp/SKILL.md
  - .remember/logs/autonomous/save-091107.log
  - docs/edit-algebra-cd-discipline.md
  - docs/structural-editing-paradigm.md
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-131902.log
  - .github/prompts/spectra-drift.prompt.md
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-050705.log
  - docs/docx-libraries-comparison.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/ParagraphSnapshot.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorResolverTests.swift
  - docs/stale-triage-chain-batch2-2026-05-25.md
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-143700.log
-->

---
### Requirement: Inline atom ops mirror OOXML empty elements

The taxonomy SHALL include `insertTab(in: ElementID)`, `insertBreak(in: ElementID)`, and `insertNoBreakHyphen(in: ElementID)` appending the corresponding empty inline element (`<w:tab/>`, `<w:br/>`, `<w:noBreakHyphen/>`) in construction order. `in:` SHALL address a **run** (`<w:r>`) — these atoms are only schema-valid inside `<w:r>`, never as direct children of `<w:p>`. When the DSL emits a standalone atom with no preceding run in the paragraph, the reducer SHALL synthesize an empty wrapping `<w:r>` first. No index parameter (same ID-based rule as AppendParagraph). Scope note: a bare `<w:br/>` is the text-wrapping line break; page/column breaks (`w:type="page|column"`) are out of scope until a future additive `type:` parameter.

#### Scenario: Tab op appends w:tab

- **WHEN** `insertTab(in: <run-id>)` replays
- **THEN** the addressed `<w:r>` gains a trailing `<w:tab/>` child


<!-- @trace
source: word-aligned-state-sync
updated: 2026-07-06
code:
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-144618.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/AnchorResolver.swift
  - .remember/logs/autonomous/save-095118.log
  - plugins/macdoc/hooks/hooks.json
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-143020.log
  - Sources/MacDocCLI/MacDoc+Word.swift
  - .remember/logs/autonomous/save-133659.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093340.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-095142.log
  - plugins/che-pdf-mcp/bin/che-pdf-mcp-wrapper.sh
  - reference/README.md
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-144433.log
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - .remember/logs/autonomous/save-090944.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ExecutorTests.swift
  - .remember/logs/autonomous/save-092853.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGeneratorTests.swift
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - plugins/che-pptx-mcp/bin/che-pptx-mcp-wrapper.sh
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-125453.log
  - mcp/che-pdf-mcp
  - .remember/logs/autonomous/save-070717.log
  - plugins/che-pptx-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-094627.log
  - .claude-plugin/marketplace.json
  - Package.swift
  - .remember/logs/autonomous/save-053409.log
  - plugins/che-pptx-mcp/README.md
  - plugins/macdoc/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-095621.log
  - README.md
  - .remember/logs/autonomous/save-093255.log
  - docs/lossless-conversion.md
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorDecodingTests.swift
  - Package.resolved
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-130300.log
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - mcp/che-pptx-mcp
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093039.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/DocxWorkflowLib.swift
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/VerifyAssertions.swift
  - packages/docx-workflow-swift/Package.swift
  - .github/PULL_REQUEST_TEMPLATE.md
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-093030.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Manifest.swift
  - .remember/logs/autonomous/save-093138.log
  - cli/FastOCR
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-095539.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Anchor.swift
  - plugins/che-word-mcp/CLAUDE.md
  - plugins/macdoc/skills/macdoc/SKILL.md
  - .remember/logs/autonomous/save-095047.log
  - plugins/che-word-mcp/README.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Tests/MacDocCLITests/NoteHTMLConvertTests.swift
  - plugins/che-pdf-mcp/skills/che-pdf-mcp/SKILL.md
  - plugins/che-word-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-125949.log
  - plugins/che-word-mcp/.mcp.json
  - .github/skills/spectra-drift/SKILL.md
  - plugins/che-pdf-mcp/README.md
  - docs/stale-triage-chain-2026-05-25.md
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-132950.log
  - plugins/che-pdf-mcp/CHANGELOG.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/EditPlanner.swift
  - plugins/che-word-mcp/bin/che-word-mcp-wrapper.sh
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093013.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ManifestDecodingTests.swift
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-132859.log
  - plugins/che-word-mcp/CHANGELOG.md
  - Sources/MacDocCLI/MacDoc.swift
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143733.log
  - plugins/macdoc/hooks/session-start.sh
  - packages/docx-workflow-swift/CHANGELOG.md
  - .remember/logs/autonomous/save-144132.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifierTests.swift
  - plugins/che-pdf-mcp/.claude-plugin/plugin.json
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-144003.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Executor.swift
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093149.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Verifier.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifyAssertionsDecodingTests.swift
  - plugins/che-pptx-mcp/.mcp.json
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - scripts/release-cli.sh
  - .remember/logs/autonomous/save-143856.log
  - CLAUDE.md
  - .remember/logs/autonomous/save-144708.log
  - Tests/MacDocCLITests/Fixtures/README.md
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095546.log
  - .gitmodules
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-090656.log
  - packages/docx-workflow-swift/README.md
  - plugins/che-pptx-mcp/CHANGELOG.md
  - .remember/logs/autonomous/save-051714.log
  - plugins/che-pdf-mcp/.mcp.json
  - .remember/logs/autonomous/save-093825.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGenerator.swift
  - plugins/macdoc/CHANGELOG.md
  - plugins/che-word-mcp/skills/che-word-mcp/SKILL.md
  - .remember/logs/autonomous/save-091107.log
  - docs/edit-algebra-cd-discipline.md
  - docs/structural-editing-paradigm.md
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-131902.log
  - .github/prompts/spectra-drift.prompt.md
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-050705.log
  - docs/docx-libraries-comparison.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/ParagraphSnapshot.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorResolverTests.swift
  - docs/stale-triage-chain-batch2-2026-05-25.md
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-143700.log
-->

---
### Requirement: Bulk-mutation granularity uses the batch envelope（spec-frozen from design Q2）

Fine-grained mutations SHALL remain one operation per change（e.g., one `updateAttribute` per attribute）. Bulk operations SHALL be expressed by wrapping the constituent ops in a `batchBegin(label:)` / `batchEnd` envelope — there is NO merged `BatchUpdate` payload op. Consumers（undo, sync, transcoder）treat the envelope as one logical unit while the wire stays uniformly per-op.

#### Scenario: bulk reformat is one logical unit, many wire ops

- **WHEN** a 100-run reformat is applied through a batch
- **THEN** the log contains `batchBegin`, 100 individual ops, `batchEnd` — and undo of the batch reverts all 100 as one step

<!-- @trace
source: word-aligned-state-sync
updated: 2026-07-06
code:
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-144618.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/AnchorResolver.swift
  - .remember/logs/autonomous/save-095118.log
  - plugins/macdoc/hooks/hooks.json
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-143020.log
  - Sources/MacDocCLI/MacDoc+Word.swift
  - .remember/logs/autonomous/save-133659.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093340.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-095142.log
  - plugins/che-pdf-mcp/bin/che-pdf-mcp-wrapper.sh
  - reference/README.md
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-144433.log
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - .remember/logs/autonomous/save-090944.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ExecutorTests.swift
  - .remember/logs/autonomous/save-092853.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGeneratorTests.swift
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - plugins/che-pptx-mcp/bin/che-pptx-mcp-wrapper.sh
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-125453.log
  - mcp/che-pdf-mcp
  - .remember/logs/autonomous/save-070717.log
  - plugins/che-pptx-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-094627.log
  - .claude-plugin/marketplace.json
  - Package.swift
  - .remember/logs/autonomous/save-053409.log
  - plugins/che-pptx-mcp/README.md
  - plugins/macdoc/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-095621.log
  - README.md
  - .remember/logs/autonomous/save-093255.log
  - docs/lossless-conversion.md
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorDecodingTests.swift
  - Package.resolved
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-130300.log
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - mcp/che-pptx-mcp
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093039.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/DocxWorkflowLib.swift
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/VerifyAssertions.swift
  - packages/docx-workflow-swift/Package.swift
  - .github/PULL_REQUEST_TEMPLATE.md
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-093030.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Manifest.swift
  - .remember/logs/autonomous/save-093138.log
  - cli/FastOCR
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-095539.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Anchor.swift
  - plugins/che-word-mcp/CLAUDE.md
  - plugins/macdoc/skills/macdoc/SKILL.md
  - .remember/logs/autonomous/save-095047.log
  - plugins/che-word-mcp/README.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Tests/MacDocCLITests/NoteHTMLConvertTests.swift
  - plugins/che-pdf-mcp/skills/che-pdf-mcp/SKILL.md
  - plugins/che-word-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-125949.log
  - plugins/che-word-mcp/.mcp.json
  - .github/skills/spectra-drift/SKILL.md
  - plugins/che-pdf-mcp/README.md
  - docs/stale-triage-chain-2026-05-25.md
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-132950.log
  - plugins/che-pdf-mcp/CHANGELOG.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/EditPlanner.swift
  - plugins/che-word-mcp/bin/che-word-mcp-wrapper.sh
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093013.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ManifestDecodingTests.swift
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-132859.log
  - plugins/che-word-mcp/CHANGELOG.md
  - Sources/MacDocCLI/MacDoc.swift
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143733.log
  - plugins/macdoc/hooks/session-start.sh
  - packages/docx-workflow-swift/CHANGELOG.md
  - .remember/logs/autonomous/save-144132.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifierTests.swift
  - plugins/che-pdf-mcp/.claude-plugin/plugin.json
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-144003.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Executor.swift
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093149.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Verifier.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifyAssertionsDecodingTests.swift
  - plugins/che-pptx-mcp/.mcp.json
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - scripts/release-cli.sh
  - .remember/logs/autonomous/save-143856.log
  - CLAUDE.md
  - .remember/logs/autonomous/save-144708.log
  - Tests/MacDocCLITests/Fixtures/README.md
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095546.log
  - .gitmodules
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-090656.log
  - packages/docx-workflow-swift/README.md
  - plugins/che-pptx-mcp/CHANGELOG.md
  - .remember/logs/autonomous/save-051714.log
  - plugins/che-pdf-mcp/.mcp.json
  - .remember/logs/autonomous/save-093825.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGenerator.swift
  - plugins/macdoc/CHANGELOG.md
  - plugins/che-word-mcp/skills/che-word-mcp/SKILL.md
  - .remember/logs/autonomous/save-091107.log
  - docs/edit-algebra-cd-discipline.md
  - docs/structural-editing-paradigm.md
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-131902.log
  - .github/prompts/spectra-drift.prompt.md
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-050705.log
  - docs/docx-libraries-comparison.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/ParagraphSnapshot.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorResolverTests.swift
  - docs/stale-triage-chain-batch2-2026-05-25.md
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-143700.log
-->

---
### Requirement: Format-payload additive extensions

Payload types SHALL gain additive optional fields required by five-layer extraction: `RunPayload` gains font (ascii/eastAsia), size, underline, and vertical-alignment fields; `ParagraphPayload` gains spacing, indentation, alignment, and numbering-reference fields; a `SectionPayload` carries page size, margins, orientation, column count, and header/footer references. All extensions follow the additive-only wire discipline (#128): existing JSONL lines decode unchanged, absent fields mean "not specified", and new field names SHALL NOT collide with the envelope keys op_id / ts / source / op_type (v1.0.2 moveNode lesson).

#### Scenario: old sidecar decodes under extended payloads

- **WHEN** a v1.0.x oplog sidecar is decoded by a build carrying the extended payloads
- **THEN** every line decodes with the new fields absent and replay behavior is unchanged

#### Scenario: extended fields round-trip the wire

- **GIVEN** an appendParagraph whose RunPayload carries eastAsia font and size
- **WHEN** the entry is encoded to JSONL and decoded back
- **THEN** the payload round-trips field-for-field with camelCase discriminators per the OOXML-mirror naming table

<!-- @trace
source: format-alignment-engine
updated: 2026-07-08
code:
  - mcp/che-word-mcp
-->

---
### Requirement: Word-form payload additive extensions

Payload types SHALL gain additive optional fields for Word-canonical forms: `ParagraphPayload` and `RunPayload` gain revision-session-id fields (rsid family, opaque strings); `RunPayload` gains a preserve-space flag (↔ `xml:space="preserve"` on `<w:t>`); a new `setDocumentRoot` operation carries the document root's attribute list as an order-significant array of prefix/localName/value triples. All extensions follow the additive-only wire discipline: existing JSONL lines decode unchanged, absent fields mean "not specified", and new field names SHALL NOT collide with the envelope keys op_id / ts / source / op_type.

#### Scenario: old sidecar decodes under Word-form extensions

- **WHEN** a pre-extension oplog sidecar is decoded by a build carrying the Word-form payload fields
- **THEN** every line decodes with the new fields absent and replay behavior is unchanged

#### Scenario: setDocumentRoot round-trips the wire order-preserved

- **GIVEN** a `setDocumentRoot` op carrying five namespace declarations and `mc:Ignorable` in a specific order
- **WHEN** the entry is encoded to JSONL and decoded back
- **THEN** the attribute array round-trips field-for-field in the same order

#### Scenario: rsid fields round-trip field-for-field

- **GIVEN** an appendParagraph whose payload carries rsidR and rsidRDefault values
- **WHEN** the entry is encoded to JSONL and decoded back
- **THEN** the payload round-trips field-for-field


<!-- @trace
source: word-canonical-forms
updated: 2026-07-09
code:
  - mcp/che-word-mcp
-->

---
### Requirement: Document root stamping replaces attributes wholesale

The reducer SHALL apply `setDocumentRoot` by replacing the document root element's attribute list with the op's attributes in array order. When the op is absent the authoring default root (minimal namespace set) SHALL remain unchanged, preserving all existing behavior.

#### Scenario: root attributes stamped in order

- **GIVEN** an empty authoring document and a `setDocumentRoot` op with an ordered attribute list
- **WHEN** the op applies
- **THEN** the root element carries exactly those attributes in that order

#### Scenario: absent op keeps the default root

- **WHEN** a script without `setDocumentRoot` executes
- **THEN** the rebuilt root carries the authoring default namespace set, byte-identical to pre-extension behavior

<!-- @trace
source: word-canonical-forms
updated: 2026-07-09
code:
  - mcp/che-word-mcp
-->