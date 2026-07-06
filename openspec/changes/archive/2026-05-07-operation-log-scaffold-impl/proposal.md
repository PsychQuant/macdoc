## Why

Phase 2 of `word-aligned-state-sync` (Operation log persistence, target ooxml-swift v0.32.0 GA) is the next major piece on the road to the docx → mdocx → docx round-trip the user wants. Phase 2 has 17 tasks (3.1-3.17 in `word-aligned-state-sync/tasks.md`) and naturally splits into three sub-phases:

- **Phase 2a — data structures** (this change): the `Operation` enum, `ElementID`, `OperationLog` collection, and JSONL on-disk format. Purely additive types — no behavior change to existing Reader/Writer/typed model. (8 tasks: 3.1-3.8)
- **Phase 2b — reducer + replay** (separate change `operation-reducer-impl`): `OperationReducer.materialize`, time-travel `state(at:)`, undo/redo, blame, snapshot caching, error reporting. (6 tasks: 3.9-3.14)
- **Phase 2c — typed-view wiring + sidecar persistence** (separate change `operation-log-setter-wiring-impl`): wire setters from Phase 1 typed views (`Paragraph.text =`, etc.) to emit ops via the log; sidecar file management (`<docx>.oplog.jsonl` + `<docx>.snapshot.json`). (2 tasks: 3.15-3.16) Plus `v0.32.0 GA release` (1 task: 3.17).

Splitting Phase 2 into three chunks keeps each change inside the 15-task ceiling and matches the cadence the user asked for ("under 1.5-3 hr per change, no multi-day grinds"). Phase 2b/2c are blocked on Phase 2a — the reducer needs `Operation` and `OperationLog` to exist; the setter wiring needs the reducer.

This change ships the data-structure foundation: types that downstream Phase 2b/2c will consume. Because everything added is **NEW types in a new directory** (`Sources/OOXMLSwift/OpLog/`), there is zero behavioral risk on the existing Reader/Writer/typed-model surface — che-word-mcp's 297 tests cannot regress against this change.

## What Changes

- **NEW**: `Operation` enum (`OpLog/Operation.swift`) covering the full OOXML mutation surface required by `word-aligned-state-sync` Phase 2:
  - **Element-level cases** (16): `insertParagraphAfter`, `insertParagraphBefore`, `removeParagraph`, `setText`, `setParagraphStyle`, `insertTable`, `removeTable`, `setCellText`, `insertRun`, `setRunFormat`, `insertBookmark`, `insertComment`, `undo`, `redo`, `batchBegin`, `batchEnd`
  - **Tree-node-level fallback cases** (4): `insertNode`, `removeNode`, `updateAttribute`, `moveNode`
  - **Forward-compat fallback** (1): `unknown(opType: String, payload: JSONValue)` — preserves any op_type the local code does not recognize so the JSONL log round-trips byte-equal across version skews
- **NEW**: `ElementID` value type (`OpLog/ElementID.swift`) with priority-chain derivation matching `XmlNode.stableID` format. Order: `w14:paraId` → `w:bookmarkId` / `w:id` → `r:id` → `w14:textId` → library `UUID` v4 fallback. Provides `ElementID(node:)` initializer that derives the ID from an `XmlNode`, and an `ElementID(libraryUUID:)` initializer for synthesized cases.
- **NEW**: `OperationLog` value type (`OpLog/OperationLog.swift`):
  - `append-only entries: [LogEntry]` array (mutating `append` only; no remove/replace API in this scaffold)
  - Each `LogEntry` carries `opID: UUID` (v4, generated at append time), `op: Operation`, `source: OpSource` (`.swift` or `.word`), `timestamp: Date`
  - `batch(_ source: OpSource, _ body: (inout OperationLog) throws -> Void) rethrows` — atomic transaction marker via `batchBegin` / `batchEnd` ops surrounding `body`'s appends
- **NEW**: JSONL serialization (`OpLog/OperationLog+JSONL.swift`):
  - `OperationLog.encodeJSONL() -> Data` — one JSON object per line, newline-delimited
  - `OperationLog.decodeJSONL(_ data: Data) throws -> OperationLog` — round-trip-equal for known ops; unknown `op_type` decodes as `.unknown(opType:payload:)` and re-encodes byte-identically
- **NEW**: Tests (`Tests/OOXMLSwiftTests/OperationLogTests.swift`):
  - `Operation` enum coverage: each case constructs and pattern-matches correctly
  - `ElementID` derivation: priority-chain unit tests covering each tier (paraId, bookmarkId, w:id, r:id, textId, libraryUUID, none → nil)
  - `OperationLog.append`: appends increase entry count; opIDs are unique across appends; source attribution preserved
  - `OperationLog.batch`: atomic markers wrap body ops in entries
  - JSONL round-trip: encode → decode → encode produces byte-identical bytes for typed ops
  - JSONL forward-compat: synthesized JSONL with unknown `op_type` decodes to `.unknown` and re-encodes byte-identically
- **NON-BREAKING**: Reader, Writer, typed model untouched. Public Document/Paragraph/Run/Table API surface unchanged. che-word-mcp 297 tests must remain GREEN (regression gate via Package.resolved bump after release).

## Non-Goals

- **OperationReducer / replay logic** (`word-aligned-state-sync` tasks 3.9-3.14) — out of scope. Separate change `operation-reducer-impl`. This change ships the data structures; the next change consumes them.
- **Typed-view setter wiring to op log** (task 3.15) — out of scope. Separate change `operation-log-setter-wiring-impl`. Phase 1 stub setters (e.g., `Paragraph.text =` mutating the tree directly) remain untouched.
- **Sidecar file management** (task 3.16) — out of scope. Same follow-up.
- **v0.32.0 GA release** (task 3.17) — defers until all Phase 2 sub-phases land. This change ships as v0.31.3 (additive minor patch).
- **Mutation API on `OperationLog` beyond `append` and `batch`** — no removal, replacement, in-place edit. The append-only invariant is the data-structure contract; tooling like undo is a reducer-side concern (Phase 2b).
- **Wire `OpLog/` types into `WordDocument`** — out of scope. WordDocument does NOT gain an `operationLog` field in this change. Phase 2b decides whether the log lives on Document or on a sibling SyncOrchestrator (per Phase 3 design).
- **Snapshot caching / time-travel** — Phase 2b.

## Capabilities

### New Capabilities

- `ooxml-operation-log`: Defines the Operation taxonomy (element-level + tree-node-level + forward-compat unknown), ElementID derivation rules, OperationLog append-only contract with batch transactions and source attribution, and JSONL on-disk format. Sibling to the v0.30.0 lossless tree IO capability and to the typed-view tree-projection capabilities (which it consumes via `XmlNode` for `ElementID(node:)` derivation). Phase 2b and 2c will extend this capability with Reducer requirements and setter-wiring requirements respectively.

### Modified Capabilities

(none — this change is purely additive; it introduces a new top-level OpLog module with no modification to any existing capability surface.)

## Impact

- Affected specs:
  - New: `openspec/specs/ooxml-operation-log/spec.md`
- Affected code:
  - New: `packages/ooxml-swift/Sources/OOXMLSwift/OpLog/Operation.swift` (Operation enum + JSONValue helper)
  - New: `packages/ooxml-swift/Sources/OOXMLSwift/OpLog/ElementID.swift` (ElementID value type + derivation)
  - New: `packages/ooxml-swift/Sources/OOXMLSwift/OpLog/OperationLog.swift` (OperationLog + LogEntry + OpSource + batch helper)
  - New: `packages/ooxml-swift/Sources/OOXMLSwift/OpLog/OperationLog+JSONL.swift` (JSONL encode/decode)
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/OperationLogTests.swift` (unit tests)
- Affected dependencies:
  - che-word-mcp (downstream lib consumer): no source change required; its 297 production tests are the regression gate. They MUST stay GREEN through this change after Package.resolved bump to v0.31.3 (regression risk is essentially zero since this change adds new types only).
  - macdoc CLI: no source change required.
- Affected releases:
  - ooxml-swift v0.31.3 (additive minor patch — keeps v0.32.0 reserved for the Phase 2 GA bundle that ships once Phase 2b + 2c also land).
- Affected sibling Spectra changes:
  - `word-aligned-state-sync` Phase 2 tasks 3.1-3.8 marked done after this change archives. Tasks 3.9-3.17 remain pending; recorded as follow-ups `operation-reducer-impl` (3.9-3.14) and `operation-log-setter-wiring-impl` (3.15-3.16); v0.32.0 GA tag (3.17) lands when 2c archives.
