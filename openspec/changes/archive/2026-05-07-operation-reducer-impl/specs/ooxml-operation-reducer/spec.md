## ADDED Requirements

### Requirement: Pure replay of operation log to tree

`OperationReducer.materialize(log: OperationLog, base: XmlTree) throws -> XmlTree` SHALL be a pure function: same `(log, base)` input always produces the same output `XmlTree`. The reducer SHALL NOT mutate the caller's `base` argument; the returned tree is a deep copy with all log ops applied.

The reducer SHALL apply `log.entries` in source-array order. For each entry, the reducer SHALL translate the `Operation` case into the appropriate `XmlNode` / `XmlTree` mutation primitive call (e.g., `setText` op replaces the target node's `<w:t>` children with the new text; `updateAttribute` op calls `node.setAttribute`).

The reducer SHALL throw a typed `ReducerError` when an op cannot be applied. The `base` deep copy is discarded on throw — partial trees do not leak to the caller.

#### Scenario: same input produces same output

- **GIVEN** an `OperationLog` `log` with two `setText` entries and a synthesized `XmlTree` `base`
- **WHEN** `OperationReducer.materialize(log: log, base: base)` is called twice with the same arguments
- **THEN** both returned trees SHALL fingerprint-equal via `XmlNode.normalizedFingerprint()`

#### Scenario: caller's base tree is not mutated

- **GIVEN** a synthesized `XmlTree` `base` with a `<w:p>` root
- **WHEN** the reducer is called with a log containing a `setText` op targeting the root
- **THEN** the returned tree SHALL contain the new text
- **AND** the original `base` tree SHALL be unchanged (root's children identical to pre-call state)

### Requirement: Time-travel state snapshots

`OperationReducer.state(log: OperationLog, base: XmlTree, at point: ReplayPoint) throws -> XmlTree` SHALL materialize the tree state at a specific replay point. `ReplayPoint` SHALL be an `Equatable, Sendable` enum with these cases:

- `.latest` — equivalent to `materialize(log:base:)` (replay all entries)
- `.index(Int)` — replay `log.entries[0..<N]` (first N entries)
- `.timestamp(Date)` — replay every entry whose `LogEntry.timestamp <= cutoff`, in source-array order

`.index(0)` SHALL return a deep copy of `base` unchanged. `.index(log.entries.count)` SHALL be equivalent to `.latest`. Out-of-range index (`< 0` or `> log.entries.count`) SHALL throw `ReducerError.malformedOp(opID: <some opID>, reason: "index out of range")`.

`.timestamp` SHALL preserve source-array order; timestamps in the log are not guaranteed monotonically increasing because batch transactions may share a timestamp.

#### Scenario: index 0 returns base unchanged

- **GIVEN** a log with 3 entries and a base tree
- **WHEN** `state(log:base: at: .index(0))` is called
- **THEN** the returned tree SHALL fingerprint-equal `base`

#### Scenario: index equal to entries.count is identical to latest

- **GIVEN** a log with 3 entries and a base tree
- **WHEN** both `state(log:base: at: .index(3))` and `state(log:base: at: .latest)` are called
- **THEN** the two returned trees SHALL fingerprint-equal each other

#### Scenario: timestamp filters entries by cutoff

- **GIVEN** a log with 3 entries at timestamps `[t0, t1, t2]` (t0 < t1 < t2) and a base tree
- **WHEN** `state(log:base: at: .timestamp(t1))` is called
- **THEN** the returned tree SHALL be the result of replaying entries[0] and entries[1] only (entry[2] excluded because its timestamp > cutoff)

### Requirement: Undo operation reverses its target

`OperationReducer.undo(_ targetOpID: UUID, log: OperationLog, base: XmlTree) throws -> XmlTree` SHALL materialize the tree as if the entry with `opID == targetOpID` had never been applied. The intervening entries (those after the target in `log.entries`) SHALL see the world without the target's effect, NOT see the target's effect followed by an inversion.

In Phase 2b, undo SHALL be supported for these op cases:
- `setText` (inverse: replace text with the value of the most recent prior `setText` entry for the same ElementID; if none, replace with empty string)
- `setParagraphStyle` (inverse: same logic on `styleId`)

For all other op cases, including `.unknown`, undo SHALL throw `ReducerError.cannotUndo(targetOpID:)`.

If no entry matches `targetOpID`, undo SHALL throw `ReducerError.cannotUndo(targetOpID:)` with that same opID.

#### Scenario: undo of setText reverts text

- **GIVEN** a log with two entries: opA `setText(target=X, text="Old")` and opB `setText(target=X, text="New")`
- **WHEN** `OperationReducer.undo(targetOpID: opB.opID, log: log, base: base)` is called
- **THEN** the returned tree SHALL contain the text `"Old"` at element X (the value before opB)

#### Scenario: undo of unsupported op throws

- **GIVEN** a log entry with op `.insertTable(at: ..., table: ...)`
- **WHEN** `undo` is called targeting that entry's opID
- **THEN** the call SHALL throw `ReducerError.cannotUndo(targetOpID:)`

#### Scenario: undo of nonexistent opID throws

- **GIVEN** an `OperationLog` and a UUID that matches no entry
- **WHEN** `undo` is called with that UUID
- **THEN** the call SHALL throw `ReducerError.cannotUndo(targetOpID:)`

### Requirement: Redo reapplies an undone operation

`OperationReducer.redo(_ targetOpID: UUID, log: OperationLog, base: XmlTree) throws -> XmlTree` SHALL undo a prior `Operation.undo(targetOpID:)` log entry. The reducer walks the log; finds the `.undo` entry whose `targetOpID` matches the argument; on materialize, SKIPS that `.undo` entry so the original op stays in effect.

If no `.undo` entry references `targetOpID`, redo SHALL throw `ReducerError.cannotRedo(targetOpID:)`.

#### Scenario: redo restores the original op's effect

- **GIVEN** a log with three entries: opA `setText(target=X, text="Original")`, opB `undo(targetOpID: opA.opID)`, opC `setText(target=Y, text="Other")`
- **WHEN** `OperationReducer.redo(targetOpID: opA.opID, log: log, base: base)` is called
- **THEN** the returned tree SHALL contain the text `"Original"` at element X (opB skipped)
- **AND** the returned tree SHALL contain the text `"Other"` at element Y (opC applied normally)

#### Scenario: redo without matching undo throws

- **GIVEN** an `OperationLog` with no `.undo` entries
- **WHEN** `redo` is called with any UUID
- **THEN** the call SHALL throw `ReducerError.cannotRedo(targetOpID:)`

### Requirement: Blame returns the operation that last touched an element

`OperationReducer.blame(elementID: ElementID, log: OperationLog) -> LogEntry?` SHALL return the most recent `LogEntry` in `log.entries` whose op references the given `ElementID`. The reducer SHALL walk `log.entries` in REVERSE order and return on first match.

If no entry's op touches the given ElementID, blame SHALL return `nil`.

`.unknown` ops SHALL never count as touching any ElementID (opaque payload).

#### Scenario: blame returns the most recent touching op

- **GIVEN** a log with three entries: opA `setText(target=X, text="A")`, opB `setText(target=Y, text="B")`, opC `setText(target=X, text="C")`
- **WHEN** `OperationReducer.blame(elementID: X, log: log)` is called
- **THEN** the returned `LogEntry` SHALL be opC (most recent op touching X)

#### Scenario: blame returns nil for untouched element

- **GIVEN** a log whose entries' ops never reference ElementID Z
- **WHEN** `OperationReducer.blame(elementID: Z, log: log)` is called
- **THEN** the returned value SHALL be `nil`

### Requirement: Snapshot caching avoids full replay on every read

`OperationReducerCache` SHALL be an `actor` exposing `materialize(log: OperationLog, base: XmlTree) async throws -> XmlTree`. The cache SHALL store the last `(logLength, materializedTree)` pair keyed by `ObjectIdentifier(base.root)`. On a cache hit where `cached.logLength <= log.entries.count`, the cache SHALL replay only the tail (`log.entries[cached.logLength..<log.entries.count]`) starting from the cached materialized tree (deep-copied) instead of replaying from `base` from scratch.

The cache SHALL invalidate implicitly when:
- A different `base.root` ObjectIdentifier is encountered (different cache key)
- `cached.logLength > log.entries.count` (defensively — append-only API prevents this, but JSONL re-load could trigger it)

There SHALL NOT be a public `invalidate()` API — the cache is implicit and self-managing.

The cache SHALL NOT persist across process restarts. Disk-backed caching is a separate Phase 2c concern (sidecar `<docx>.snapshot.json` files).

#### Scenario: tail-replay on cache hit

- **GIVEN** an empty `OperationReducerCache`, a log with 5 entries, and a base tree
- **WHEN** `cache.materialize(log: log, base: base)` is called
- **AND** then `log.append(...)` is called to add 2 more entries
- **AND** then `cache.materialize(log: log, base: base)` is called again
- **THEN** the second call SHALL return the same fingerprint as a fresh `OperationReducer.materialize(log: log, base: base)` would
- **AND** the second call SHALL be tail-replay (only the new 2 entries replayed) — verifiable by injecting a counter into a test op

#### Scenario: cache miss on different base identity

- **GIVEN** a populated cache for `baseA`
- **WHEN** `cache.materialize(log: log, base: baseB)` is called with a different base whose root is a distinct `ObjectIdentifier`
- **THEN** the cache SHALL fall back to full materialize and return the correct result

### Requirement: Apply errors are reported, not swallowed

`OperationReducer` SHALL surface a typed `ReducerError` for any op application failure. The error type SHALL have at least these cases:

- `elementNotFound(opID: UUID, elementID: ElementID)` — the op references an ElementID not present in the tree at replay time
- `malformedOp(opID: UUID, reason: String)` — the op's payload is structurally invalid (e.g., negative row index, out-of-range `.index` ReplayPoint)
- `cannotRedo(targetOpID: UUID)` — `redo` invoked but no matching `.undo` entry exists
- `cannotUndo(targetOpID: UUID)` — `undo` invoked but the target op cannot be inverted (unsupported op kind, opaque `.unknown`, or no matching entry)

The reducer SHALL NOT swallow errors silently. The reducer SHALL NOT log to stderr in lieu of throwing — every failure surfaces to the caller.

#### Scenario: elementNotFound throws when target ID is missing

- **GIVEN** a log entry `setText(target: nonexistentID, text: "x")` and a base tree that contains no node with `nonexistentID`
- **WHEN** `OperationReducer.materialize(log: log, base: base)` is called
- **THEN** the call SHALL throw `ReducerError.elementNotFound(opID: <that entry's opID>, elementID: nonexistentID)`

#### Scenario: malformedOp throws for out-of-range index

- **GIVEN** a log with 3 entries
- **WHEN** `OperationReducer.state(log: log, base: base, at: .index(5))` is called
- **THEN** the call SHALL throw `ReducerError.malformedOp(opID: ..., reason: "index out of range")`

### Requirement: OperationReducerTests pinned coverage

A new test file `Tests/OOXMLSwiftTests/OperationReducerTests.swift` SHALL be added with at least 12 XCTestCase methods pinning the requirements above:

1. `testMaterialize_pureFunction` — same input twice produces same output
2. `testMaterialize_doesNotMutateBase` — caller's base tree unchanged
3. `testMaterialize_appliesSetText` — setText op produces expected text
4. `testState_indexZeroReturnsBaseUnchanged`
5. `testState_indexEqualToCountIsLatest`
6. `testState_timestampFilters`
7. `testState_outOfRangeIndexThrows`
8. `testUndo_setTextReverts`
9. `testUndo_unsupportedOpThrows`
10. `testRedo_restoresOriginalOpEffect`
11. `testBlame_returnsMostRecentTouchingOp`
12. `testCache_tailReplayOnHit`
13. `testReducerError_elementNotFoundOnMissingTarget`

The tests SHALL pass GREEN against the implementation in the same release (no `#if false` gate phase).

#### Scenario: OperationReducerTests passes GREEN

- **WHEN** `swift test --filter OperationReducerTests` runs against this change
- **THEN** every test method SHALL pass
- **AND** the test runner SHALL report at least 12 passing tests with 0 failures
