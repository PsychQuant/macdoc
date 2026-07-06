## Why

Phase 2b of `word-aligned-state-sync` (target ooxml-swift v0.31.4). Phase 2a shipped the data structures in v0.31.3 (`Operation`, `ElementID`, `OperationLog`, JSONL serialization). Now the reducer makes those data structures useful: given a `base: XmlTree` and an `OperationLog`, the reducer materializes the result tree by replaying ops in order. Once the reducer exists, Phase 2c (`operation-log-setter-wiring-impl`) wires typed-view setters to emit ops via the log, and the v0.32.0 GA tag becomes possible.

The reducer is also the foundation for downstream capabilities the user wants:
- **Round-trip closure** (Phase 4 `script-transcoder-impl`, target v0.34.0): reading log → emitting `.mdocx.swift` → re-executing → emitting log requires the reducer to verify the reverse direction is lossless (replay log A on base; replay log B on same base; assert the two materialized trees fingerprint-equal).
- **Word-import diff** (Phase 3 `sync-orchestrator-impl`, target v0.33.0): SyncOrchestrator computes the diff between a Reader-loaded snapshot and a fresh Reader load by replaying both through the reducer and comparing.
- **Undo/redo UI** (downstream consumers like che-word-mcp `undo` MCP tool): need `state(log:base:at: .index(N))` to time-travel to before-and-after states.

This change ships the **pure-replay reducer** (`materialize`, `state(at:)`, `undo`, `redo`, `blame`, snapshot caching, typed errors) without wiring it into `WordDocument` or the typed-view setters. Wiring is Phase 2c. Pure-replay means: same `(log, base)` input always produces the same output tree — no I/O, no global state, no time-of-day dependence. This makes the reducer trivially testable and trivially cacheable.

## What Changes

- **NEW**: `OperationReducer` enum-namespace (`OpLog/OperationReducer.swift`) with the following entry points:
  - `static func materialize(log: OperationLog, base: XmlTree) throws -> XmlTree` — pure replay of every entry in `log.entries`, applying each op's tree mutation to `base`. Returns the resulting tree. Errors throw `ReducerError`.
  - `static func state(log: OperationLog, base: XmlTree, at point: ReplayPoint) throws -> XmlTree` — time-travel materialization. `ReplayPoint` is an enum with `.index(Int)` (replay first N entries) and `.timestamp(Date)` (replay all entries with `timestamp <= cutoff`).
  - `static func undo(_ targetOpID: UUID, log: OperationLog, base: XmlTree) throws -> XmlTree` — materialize the log, then apply the inverse of the targeted op. Equivalent to materializing a log where the targeted op's `Operation` value has been replaced with the inverse of itself.
  - `static func redo(_ targetOpID: UUID, log: OperationLog, base: XmlTree) throws -> XmlTree` — undoes a prior `Operation.undo(targetOpID:)` entry. If no `.undo` entry references the target, throws `ReducerError.cannotRedo(targetOpID:)`.
  - `static func blame(elementID: ElementID, log: OperationLog) -> LogEntry?` — walks `log.entries` backwards, returning the most recent entry whose op touches the given ElementID. Returns `nil` if no entry touches it.
- **NEW**: `ReplayPoint` enum (`OpLog/OperationReducer.swift`) with cases `.latest`, `.index(Int)`, `.timestamp(Date)`.
- **NEW**: `ReducerError` typed error enum:
  - `.elementNotFound(opID: UUID, elementID: ElementID)` — an op references an ElementID not present in the tree at replay time
  - `.malformedOp(opID: UUID, reason: String)` — an op's payload is structurally invalid (e.g., negative row index)
  - `.cannotRedo(targetOpID: UUID)` — `.redo` invoked but no `.undo` entry references the target
  - `.cannotUndo(targetOpID: UUID)` — `.undo` invoked but the target op cannot be inverted (e.g., `.unknown` opaque op)
- **NEW**: `OperationReducerCache` actor (`OpLog/OperationReducerCache.swift`) — stores the last `(log_length, materialized_tree, base_fingerprint)` triple keyed by base-tree identity. On `materialize(log:base:)` calls, if the cached entry exists for `base` and the log has only grown (cached `log_length <= log.entries.count`), the reducer replays only the tail from the cached tree instead of from scratch.
  - The cache is an `actor` for Swift concurrency safety — multiple consumers can read concurrently; mutations serialize.
  - Cache invalidates when `base` changes identity OR when log shrinks (which never happens via append-only API but could happen via JSONL re-load from disk).
- **NEW**: Tests (`Tests/OOXMLSwiftTests/OperationReducerTests.swift`) — at least 12 tests covering the 6 reducer requirements + the cache contract.
- **NON-BREAKING**: No modification to `Operation`, `ElementID`, `OperationLog`, JSONL, or `WordDocument`. The reducer is a NEW consumer of v0.31.3 OpLog types. Phase 1 typed views (Paragraph/Run/Table/etc.) untouched. che-word-mcp 297 tests must remain GREEN (regression gate via Package.resolved bump after release).

## Non-Goals

- **Typed-view setter wiring to op log** (`word-aligned-state-sync` task 3.15) — out of scope. Separate change `operation-log-setter-wiring-impl`. This change provides the reducer; the next change wires `Paragraph.text =` etc. to emit ops via the log AND uses this reducer to materialize them.
- **Sidecar file management** (`<docx>.oplog.jsonl` + `<docx>.snapshot.json`, task 3.16) — out of scope. Same follow-up.
- **v0.32.0 GA release** (task 3.17) — waits for Phase 2c. This change ships as v0.31.4 (additive minor patch).
- **WordDocument integration** — no `WordDocument.replay()` method, no `WordDocument.operationLog` field. Reducer is fully self-contained; Phase 2c decides whether the log lives on Document or on a sibling SyncOrchestrator.
- **Tree mutation primitives** — the reducer translates each `Operation` case into XmlTree mutations using existing primitives (`XmlNode.children = ...`, `XmlNode.setAttribute(...)`, etc. from v0.30.0). No new low-level primitives are added.
- **Rollback on error mid-replay** — if the reducer throws while applying op N of M, the partially-mutated tree is NOT rolled back. The throw surfaces to the caller; the caller decides whether to retry, log, or abort. (Pure-function semantics: the input `base` is unchanged because the reducer mutates a copy. But the returned partial tree is not returned at all on throw — only the error.)
- **Persistent caching across process restarts** — the cache is in-memory only; restart loses it. Disk-backed snapshot caching is `<docx>.snapshot.json` (Phase 2c sidecar territory, not this change).
- **Reverse application of `.unknown` ops** — `.unknown(opType:payload:)` ops are opaque to the reducer. They are NOT applied to the tree (no behavior change), they ARE included in `state` snapshots (the snapshot's log slice contains them), and `undo(targetOpID:)` on an `.unknown` op throws `.cannotUndo`.

## Capabilities

### New Capabilities

- `ooxml-operation-reducer`: Defines the pure-replay reducer that consumes the operation-log data structures landed in v0.31.3. Specifies the `materialize(log:base:)` entry point, time-travel via `state(log:base:at:)` with `.index` / `.timestamp` variants, `undo`/`redo` semantics, `blame(elementID:log:)` for last-touching op lookup, snapshot caching contract (in-memory actor-based, log-tail-replay optimization), and typed error reporting via `ReducerError`. Sibling to the operation-log capability (consumed) and to the v0.30.0 lossless tree IO capability (XmlTree mutation primitives consumed).

### Modified Capabilities

(none — this change is purely additive; it introduces a new sibling capability that consumes the v0.31.3 operation-log without modifying it.)

## Impact

- Affected specs:
  - New: `openspec/specs/ooxml-operation-reducer/spec.md`
- Affected code:
  - New: `packages/ooxml-swift/Sources/OOXMLSwift/OpLog/OperationReducer.swift` (OperationReducer enum-namespace + ReplayPoint + ReducerError)
  - New: `packages/ooxml-swift/Sources/OOXMLSwift/OpLog/OperationReducerCache.swift` (actor-based snapshot cache)
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/OperationReducerTests.swift` (12+ tests)
- Affected dependencies:
  - che-word-mcp (downstream lib consumer): no source change required; its 297 production tests are the regression gate. They MUST stay GREEN through this change after Package.resolved bump to v0.31.4 (regression risk is essentially zero since this change adds new types only).
  - macdoc CLI: no source change required.
- Affected releases:
  - ooxml-swift v0.31.4 (additive minor patch — keeps v0.32.0 reserved for the Phase 2 GA bundle that ships once Phase 2c also lands).
- Affected sibling Spectra changes:
  - `word-aligned-state-sync` Phase 2 tasks 3.9, 3.10, 3.11, 3.12, 3.13, 3.14 marked done after this change archives. Tasks 3.15-3.17 remain pending; recorded as follow-ups `operation-log-setter-wiring-impl` (3.15-3.16) and the v0.32.0 GA tag (3.17).
