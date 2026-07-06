## Context

`operation-log-scaffold-impl` (archived 2026-05-07, ooxml-swift v0.31.3) shipped the `Operation` enum, `ElementID`, `OperationLog`, and JSONL serialization. The reducer is the next layer up: it interprets log entries against a base tree to materialize state. Phase 2c (typed-view setter wiring) consumes both the log AND the reducer.

Prior art consulted:
- `openspec/specs/ooxml-operation-log/spec.md` (just shipped) — the data structures this change consumes
- `openspec/changes/word-aligned-state-sync/tasks.md` lines 45-50 — task descriptions for 3.9-3.14
- `openspec/changes/word-aligned-state-sync/design.md` — Decision 3 "ID-based operations, never positional indices" + Decision 4 "Typed APIs as views, not as the model" inform reducer behavior
- `packages/ooxml-swift/Sources/OOXMLSwift/Tree/XmlNode.swift` — XmlTree mutation primitives the reducer uses (`node.children = ...`, `setAttribute(...)`, `markDirty()`)
- `packages/ooxml-swift/Sources/OOXMLSwift/Tree/XmlTree.swift` — XmlTree value type the reducer takes as input/output

## Goals

1. Implement `OperationReducer.materialize(log:base:)` as a pure function — same input always produces same output
2. Implement time-travel via `state(log:base:at:)` with `ReplayPoint` enum cases `.latest`, `.index(N)`, `.timestamp(cutoff)`
3. Implement `undo(targetOpID:)` and `redo(targetOpID:)` interpretations
4. Implement `blame(elementID:log:)` walking entries backwards to find last-touching op
5. Implement actor-based snapshot caching with log-tail-replay optimization
6. Implement typed `ReducerError` cases with `opID` + context for diagnostics
7. Ship as ooxml-swift v0.31.4 (additive minor patch)
8. Maintain che-word-mcp regression gate at 0 failures

## Non-Goals

- Typed-view setter wiring (Phase 2c — `operation-log-setter-wiring-impl`)
- Sidecar file management (Phase 2c)
- v0.32.0 GA tag (waits for Phase 2c)
- WordDocument integration (no `Document.replay()`, no `Document.operationLog`)
- Persistent disk-backed cache (in-memory only; sidecar files are Phase 2c)
- Rollback on mid-replay error (throws and lets caller decide)
- Reverse application of `.unknown` ops (treated as opaque no-ops)

## Decisions

### Decision 1: Reducer is an enum-namespace with static functions, not a struct/class

```swift
public enum OperationReducer {
    public static func materialize(log: OperationLog, base: XmlTree) throws -> XmlTree { ... }
    public static func state(log: OperationLog, base: XmlTree, at point: ReplayPoint) throws -> XmlTree { ... }
    public static func undo(_ targetOpID: UUID, log: OperationLog, base: XmlTree) throws -> XmlTree { ... }
    public static func redo(_ targetOpID: UUID, log: OperationLog, base: XmlTree) throws -> XmlTree { ... }
    public static func blame(elementID: ElementID, log: OperationLog) -> LogEntry? { ... }
}
```

**Why enum-namespace**: the reducer holds NO state. Every entry point is a pure function of its arguments. An enum with no cases prevents accidental instantiation while grouping the related functions. Mirrors `JSONLLineCoder` from v0.31.3 (same pattern).

**Why static functions instead of free functions**: discoverability via `OperationReducer.<tab>` autocomplete. Also lets future Phase 2c add `OperationReducer.apply(op:to:)` as a single-op variant without polluting the global namespace.

### Decision 2: `XmlTree` mutation happens on a deep copy of `base`

Materialize takes `base: XmlTree`, makes a deep copy, then applies ops in order. The original `base` is untouched. This is critical for pure-function semantics — caller's tree is not mutated as a side effect.

```swift
public static func materialize(log: OperationLog, base: XmlTree) throws -> XmlTree {
    var working = base.deepCopy()  // NEW method; XmlTree currently has no deepCopy
    for entry in log.entries {
        try apply(entry, to: &working)
    }
    return working
}
```

**Wrinkle**: `XmlTree` is a `struct` containing `root: XmlNode` (a `class`). A struct copy shares the class instance — NOT a deep copy. The reducer needs `XmlTree.deepCopy()` that recursively clones the XmlNode tree.

**Decision**: add `internal func deepCopy() -> XmlTree` to `XmlTree`, and `internal func deepClone() -> XmlNode` to `XmlNode`. Internal because external consumers should not need them; Phase 2c wiring will use `materialize(log:base:)` and never see the deep copy directly.

This DOES mean modifying existing v0.30.0 types — slight scope drift from "additive only". Mitigation: the new methods are purely additive on those types (no behavior change to existing public surface; new internal-visibility methods).

### Decision 3: `ReplayPoint` enum unifies time-travel API

```swift
public enum ReplayPoint: Equatable, Sendable {
    case latest
    case index(Int)       // replay log.entries[0..<N]
    case timestamp(Date)  // replay all entries with .timestamp <= cutoff
}
```

**Why one enum vs multiple methods**: a single `state(log:base:at:)` entry point with an enum parameter scales when future variants are added (e.g., `.afterOp(opID: UUID)`). Cleaner than `state_at_index`, `state_at_timestamp`, `state_after_op`, etc.

**Why `.latest`**: convenience that's identical to `materialize(log:base:)`. Lets consumer code parameterize time-travel uniformly: pass `.latest` to mean "current state", or any other case for time-travel. Exists for ergonomics; not a new behavior.

**Index semantics**: `.index(N)` means "replay first N entries". `.index(0)` returns `base` unchanged. `.index(log.entries.count)` is equivalent to `.latest`. Out-of-range index throws `.malformedOp(... reason: "index out of range")`.

**Timestamp semantics**: `.timestamp(cutoff)` replays every entry whose `LogEntry.timestamp <= cutoff`. Order is preserved (entries are replayed in `entries` array order — timestamps in the log are NOT guaranteed to be monotonically increasing because batch transactions may share a timestamp; the array order is canonical).

### Decision 4: `undo(targetOpID:)` materializes with the target op's inverse substituted in

Two sane interpretations of undo:
(a) Materialize `log` then apply the inverse of `targetOp` post-hoc
(b) Materialize a modified log where `targetOp` has been replaced with its inverse

Going with (b) — modify the log copy in place during reducer's internal walk:

```swift
public static func undo(_ targetOpID: UUID, log: OperationLog, base: XmlTree) throws -> XmlTree {
    var working = base.deepCopy()
    for entry in log.entries {
        if entry.opID == targetOpID {
            try applyInverse(entry, to: &working)
        } else {
            try apply(entry, to: &working)
        }
    }
    return working
}
```

**Why (b) over (a)**: ops between `targetOp` and the end of the log may depend on `targetOp`'s effect. If we materialize then reverse, those intervening ops would have already mutated the tree based on the un-undone state — applying the inverse after them produces a different tree than the user expects. Approach (b) replays the whole history with the targeted op replaced; intervening ops then see the world as if `targetOp` never happened, which matches the user's mental model ("undo X means as if X never happened").

**Inverse rules per op type**:
- `setText(target, text)` → inverse is `setText(target, previousText)` — but the reducer doesn't know `previousText`. Solution: walk the log backwards from the target op; find the most recent prior `setText(target, X)` for the same ElementID; that X is the previous text. If no prior, the inverse is "remove all `<w:t>` content" (which corresponds to `setText(target, "")`).
- `insertParagraphAfter(after, paragraph)` → inverse is `removeParagraph(id: insertedParagraphID)`. But we need to know what ID the insertion got. Phase 2c will need to assign IDs at op-emit time (e.g., insertParagraphAfter carries the new paragraph's ElementID in its payload). This change works around it: only `setText` and `setParagraphStyle` ops support undo in Phase 2b; other op types throw `.cannotUndo`.
- `removeParagraph(id)` → inverse is `insertParagraphAfter(after: previousSiblingID, paragraph: ParagraphPayload(...))`. Same problem — we don't have the removed paragraph's content. Throws `.cannotUndo` in Phase 2b.
- `batchBegin` / `batchEnd` → undoing a batch is a separate concern (Phase 2c may add `undoBatch(label:)`). Throws `.cannotUndo` for individual markers.
- `unknown` ops → opaque, can't invert. Throws `.cannotUndo`.

**Phase 2b reducer supports undo for**: `setText`, `setParagraphStyle`. Other op types throw `.cannotUndo(targetOpID:)`. This is a Phase 2b limitation — Phase 2c may extend coverage by carrying inverse-payload data on each op. Decision intentionally deferred.

### Decision 5: `redo(targetOpID:)` re-undoes a prior `Operation.undo` entry

`redo(targetOpID:)` interprets a previously-emitted `Operation.undo(targetOpID:)` entry: walk the log, find the `.undo` entry whose `targetOpID` matches the argument, apply normally up to that entry, then RESTORE the original op (don't apply the inverse) for the rest of the replay.

```swift
public static func redo(_ targetOpID: UUID, log: OperationLog, base: XmlTree) throws -> XmlTree {
    // Find a .undo entry referencing targetOpID.
    let undoEntry = log.entries.first { entry in
        if case .undo(let tgt) = entry.op, tgt == targetOpID { return true }
        return false
    }
    guard undoEntry != nil else {
        throw ReducerError.cannotRedo(targetOpID: targetOpID)
    }
    // Replay normally — the .undo is a regular log entry that the reducer
    // interprets per Decision 4 (skip the targeted op). Redo SKIPS the .undo:
    var working = base.deepCopy()
    for entry in log.entries {
        if entry == undoEntry {
            continue  // skip the .undo entry; original op stays in effect
        }
        try apply(entry, to: &working)
    }
    return working
}
```

**Wrinkle**: redo only works if the original op is still in the log. If the user did `.undo(opID)` and then later removed the op from the log somehow (impossible with append-only API, but could happen via JSONL editing), redo throws.

### Decision 6: `blame(elementID:log:)` walks entries backwards

```swift
public static func blame(elementID: ElementID, log: OperationLog) -> LogEntry? {
    for entry in log.entries.reversed() {
        if entry.op.touchesElement(elementID) {
            return entry
        }
    }
    return nil
}
```

`Operation.touchesElement(_:)` is a private helper that returns true if the op references the given ElementID in any of its associated values. Implemented as a switch over all 21 cases, checking the relevant ElementID field. `.unknown` ops never touch (opaque).

**Why backwards walk**: blame returns the MOST RECENT op that touched the element, not the first. Reverse iteration short-circuits on first match.

### Decision 7: `OperationReducerCache` is an `actor` keyed by base tree identity

```swift
public actor OperationReducerCache {
    private var cached: [ObjectIdentifier: CacheEntry] = [:]

    public init() {}

    public func materialize(log: OperationLog, base: XmlTree) async throws -> XmlTree {
        let key = ObjectIdentifier(base.root)
        if let entry = cached[key], entry.logLength <= log.entries.count {
            // Replay only the tail.
            var working = entry.materializedTree.deepCopy()
            for i in entry.logLength..<log.entries.count {
                try OperationReducer.apply(log.entries[i], to: &working)
            }
            cached[key] = CacheEntry(logLength: log.entries.count, materializedTree: working.deepCopy())
            return working
        }
        // Full materialize.
        let result = try OperationReducer.materialize(log: log, base: base)
        cached[key] = CacheEntry(logLength: log.entries.count, materializedTree: result.deepCopy())
        return result
    }

    private struct CacheEntry {
        let logLength: Int
        let materializedTree: XmlTree
    }
}
```

**Why `actor`**: Swift concurrency safety. Multiple async callers can `await cache.materialize(...)` and the actor serializes the cache mutations.

**Why `ObjectIdentifier(base.root)`**: distinct trees produced by separate Reader runs have distinct root XmlNode class identities. The cache keys on root identity to avoid cross-tree confusion. If a caller passes a deep-copied tree, the cache miss is a no-op penalty (one full materialize) — correct behavior.

**Cache invalidation**: only invalidates implicitly when the cached `logLength > log.entries.count` (impossible via append-only API but defended) OR when the caller passes a different `base.root`. No explicit `invalidate()` API — keeps the actor surface minimal.

### Decision 8: Tree mutations use existing v0.30.0 primitives, not new ones

Each `Operation` case maps to a specific sequence of `XmlNode` / `XmlTree` mutations using existing public/internal primitives:
- `setText(target, text)` → find node by ElementID, replace its `<w:t>` direct children with one new `<w:t>X</w:t>`, call `markDirty()`. (Same as `Paragraph.text` setter from v0.31.0.)
- `insertParagraphAfter(after, paragraph)` → find parent of `after` node, find `after` node's index in parent, insert new `<w:p>` synthesized from ParagraphPayload at `index+1`. The new node gets a fresh `libraryUUID` since it has no native stable ID.
- `setCellText(table, row, col, text)` → find table node, walk to `<w:tr>[row]/<w:tc>[col]`, replace cell's first `<w:p>`'s `<w:r>/<w:t>` content.
- `updateAttribute(target, prefix, localName, value)` → find node, call `node.setAttribute(prefix:, localName:, value:)`. If `value == nil`, remove the attribute (need a new XmlNode helper or use direct attribute-array manipulation).

**The "find node by ElementID" primitive**: this is the workhorse of the reducer. Implemented as a tree walk that compares `XmlNode.stableID` and `libraryUUID`-derived IDs against the target. For Phase 2b, a linear walk suffices; Phase 5+ may add an index for performance.

```swift
private static func findNode(elementID: ElementID, in tree: XmlTree) -> XmlNode? {
    return findNode(elementID: elementID, in: tree.root)
}
private static func findNode(elementID: ElementID, in node: XmlNode) -> XmlNode? {
    if let nodeID = ElementID(node: node), nodeID == elementID {
        return node
    }
    for child in node.children {
        if let found = findNode(elementID: elementID, in: child) { return found }
    }
    return nil
}
```

If `findNode` returns nil for an op's ElementID, the reducer throws `ReducerError.elementNotFound(opID:elementID:)`.

### Decision 9: Pure-replay testing via byte-equal XmlTree fingerprints

Tests verify the reducer is pure by:
1. Materializing the same `(log, base)` twice; assert resulting trees fingerprint-equal via `XmlNode.normalizedFingerprint()` (landed v0.30.0).
2. Verifying that consumer-visible mutations (text content, attribute values) match expected values.
3. Verifying time-travel: `state(at: .index(N))` for various N produces expected partial states.

Tests use a synthesized `XmlTree.synthesized(root: ...)` for the base — no docx fixtures needed for reducer correctness tests. Larger integration tests against real docx (if needed) come in Phase 2c.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| `XmlTree.deepCopy()` is a new internal method on a v0.30.0 type — drift from "additive only" promise | The new method is internal-visibility additive (no public API change). v0.30.0 capability `ooxml-tree-io` is unaffected (its public surface unchanged). Documented clearly in CHANGELOG. |
| Undo coverage in Phase 2b is limited (only `setText`, `setParagraphStyle`) — Phase 2c users may expect more | Throws typed `.cannotUndo(targetOpID:)` so callers know undo isn't supported for that op kind. Phase 2c can extend by carrying inverse-payload data on each emitted op. |
| `ObjectIdentifier`-based cache key is brittle when callers create new XmlTree values from disk | Cache miss on different identity is a one-time penalty (full materialize), correct behavior. No incorrect results. Phase 2c may add fingerprint-based caching if profiling shows the miss rate is too high. |
| Reducer throws partway through a long log → caller has no rollback | Documented in Non-Goals. Pure-function semantics: input `base` is unchanged; only the throw escapes. Partial trees never leak out. |
| Tree mutation by ElementID requires linear walk → O(N²) for N-op replay | Acceptable for Phase 2b: typical logs are <100 ops on documents with <1000 elements (100k node-comparisons, milliseconds). Phase 5 adds an ID index if profiling demands it. |

## Open Items

- (none — Decisions 1-9 cover all the contracts; Phase 2c follow-up is registered)
