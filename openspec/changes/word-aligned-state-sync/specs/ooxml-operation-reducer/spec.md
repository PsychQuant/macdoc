## ADDED Requirements

### Requirement: Pure replay of operation log to tree

The library SHALL provide `OperationReducer.materialize(log:base:)` that takes an `OperationLog` and a base `XmlNode` tree and returns the resulting tree after applying every operation in log order. The function SHALL be pure (no I/O, no global state) and deterministic (identical inputs produce identical outputs across processes).

#### Scenario: Empty log returns base tree unchanged

- **WHEN** `materialize(log: [], base: tree)` runs
- **THEN** the returned tree is structurally equal to `tree` (same `XmlNode` graph)

#### Scenario: Replay is deterministic across processes

- **WHEN** the same log and base tree are materialized in two separate processes on the same machine and OS
- **THEN** the resulting trees are structurally equal and serialize to byte-equal bytes via `XmlTreeWriter`

### Requirement: Time-travel state snapshots

The library SHALL provide `OperationReducer.state(log:base:at:)` returning the tree state at any point in the operation history, addressed by either operation index or timestamp.

#### Scenario: state(at: index) returns intermediate snapshot

- **GIVEN** a log of `[op0, op1, op2, op3]` and base tree `T0`
- **WHEN** `state(log: log, base: T0, at: .index(2))` runs
- **THEN** the returned tree equals the result of replaying `[op0, op1]` on `T0` (operations strictly before index 2)

#### Scenario: state(at: timestamp) returns the snapshot at-or-before timestamp

- **WHEN** the caller requests `state(log: log, base: T0, at: .timestamp(t))`
- **THEN** the reducer applies every operation whose `timestamp <= t` and returns the resulting tree

### Requirement: Undo operation reverses its target

When the reducer applies an `Undo(targetID:)` operation, it SHALL apply the inverse of the targeted operation. Inverse semantics: `InsertParagraphAfter` ↔ `RemoveParagraph` referencing the inserted ID; `SetText(id, new)` ↔ `SetText(id, prior)` (prior value reconstructed by replaying the log up to but not including the targeted op).

#### Scenario: Undo of InsertParagraph removes that paragraph

- **GIVEN** a log `[InsertParagraphAfter(after: a, id: b, text: "x"), Undo(targetID: <previous op_id>)]`
- **WHEN** the log is materialized
- **THEN** the resulting tree contains paragraph `a` but not paragraph `b`

#### Scenario: Undo of SetText restores prior text

- **GIVEN** a tree where paragraph `p` has text `"original"`, and a log `[SetText(p, "modified"), Undo(targetID: <SetText op_id>)]`
- **WHEN** the log is materialized
- **THEN** paragraph `p`'s text is `"original"`

### Requirement: Redo reapplies an undone operation

When the reducer applies a `Redo(targetUndoID:)` operation, it SHALL re-apply the operation that was undone by the targeted `Undo`.

#### Scenario: Redo restores undone insert

- **GIVEN** a log `[InsertParagraphAfter(...), Undo(target: <Insert op_id>), Redo(target: <Undo op_id>)]`
- **WHEN** the log is materialized
- **THEN** the inserted paragraph is present in the resulting tree

### Requirement: Blame returns the operation that last touched an element

The library SHALL provide `OperationReducer.blame(log:elementID:)` returning the operation that most recently mutated the specified element, or `nil` if the element was never mutated by the log (i.e., it exists only in the base tree).

#### Scenario: Blame finds last mutation

- **GIVEN** a log `[SetText(p, "a"), SetText(p, "b"), SetText(q, "x")]`
- **WHEN** `blame(log, elementID: p)` runs
- **THEN** the returned operation is `SetText(p, "b")` (the last op touching `p`)

#### Scenario: Blame returns nil for untouched element

- **GIVEN** a log that never touches element `r` (which exists in the base tree)
- **WHEN** `blame(log, elementID: r)` runs
- **THEN** the returned value is `nil`

### Requirement: Snapshot caching avoids full replay on every read

The reducer SHALL support caching the most recent materialized tree alongside its corresponding log length. When `state(at: .latest)` is called, the reducer SHALL replay only the operations appended after the cached snapshot, not the entire log.

#### Scenario: Cache hit reduces work

- **GIVEN** a cached snapshot at log length 1000 and the log has grown to length 1010
- **WHEN** `state(at: .latest)` runs
- **THEN** only operations 1000..1010 are replayed against the cached snapshot

### Requirement: Apply errors are reported, not swallowed

When the reducer encounters an operation that cannot apply (e.g., `SetText(elementID: x)` where `x` does not exist in the current tree), it SHALL throw a structured `ReducerError.elementNotFound(opID:elementID:)` containing the offending op_id and element_id. It SHALL NOT silently skip the operation.

#### Scenario: Missing element raises error

- **GIVEN** a log containing `SetText(elementID: nonexistent_id, ...)`
- **WHEN** the log is materialized
- **THEN** the reducer throws `ReducerError.elementNotFound(opID:elementID:)` referencing the offending op

### Requirement: Reducer is pure relative to its inputs

The reducer SHALL NOT touch the file system, network, environment, or wall-clock time during replay. Operation timestamps embedded in the log are data, not side-effect sources.

#### Scenario: No I/O during replay

- **WHEN** `materialize(log:base:)` runs in a sandbox that traps file and network calls
- **THEN** no traps fire; replay completes purely in memory
