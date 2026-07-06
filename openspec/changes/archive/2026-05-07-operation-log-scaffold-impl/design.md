## Context

`word-aligned-state-sync` Phase 1 (tasks 2.1-2.6) shipped tree-backed typed views (`Paragraph(xmlNode:)`, etc.) and Reader-side xmlTree population (v0.31.0/0.31.1/0.31.2). The Phase 2 plan in that change's `tasks.md` (3.1-3.17) builds the operation log on top: each typed-view setter eventually emits an `Operation` with an `ElementID` payload, append-only persisted to a JSONL log. Phase 2 tasks 3.1-3.8 are pure data-structure work — they define the Operation taxonomy, ElementID type, OperationLog collection, and JSONL on-disk format without touching any consumer or replay path. This change implements those 8 tasks as Phase 2a.

Prior art consulted:
- `openspec/changes/word-aligned-state-sync/proposal.md` and `design.md` — define the Phase 2 contract this change implements
- `openspec/changes/word-aligned-state-sync/tasks.md` lines 37-44 — the eight task descriptions for 3.1-3.8
- `packages/ooxml-swift/Sources/OOXMLSwift/Tree/XmlNode.swift` — `XmlNode.stableID` (already returns priority-chain-derived String like `"w14:paraId=0ABC1234"`) and `libraryUUID` (UUID v4 fallback). The new `ElementID` derivation MUST stay byte-aligned with this existing string format so a Phase 2b reducer can match by ID across both surfaces.
- `openspec/specs/ooxml-paragraph-tree-projection/spec.md` and `openspec/specs/ooxml-typed-views-tree-projection/spec.md` — define `paragraph.id`, `run.id`, `table.id`, etc. as `String?` accessors that return the same priority-chain-derived format. ElementID interop with these accessors is a soft requirement (the reducer in Phase 2b will need to round-trip strings between OpLog and typed view).
- `Foundation.JSONEncoder` / `JSONDecoder` — used for JSONL encoding. Swift `Codable` covers everything except free-form payload (handled via a custom `JSONValue` enum below).

## Goals

1. Define the full Phase 2 mutation surface as a typed Swift `Operation` enum (16 element-level + 4 tree-node-level + 1 unknown fallback = 21 cases)
2. Define `ElementID` byte-aligned with `XmlNode.stableID`'s string format
3. Define `OperationLog` as an append-only collection with batch markers, source attribution (`.swift` / `.word`), and per-op UUIDs
4. Define JSONL on-disk format that round-trips known ops byte-equal AND preserves unknown `op_type` values byte-equal
5. Ship as ooxml-swift v0.31.3 (additive minor patch — no v0.32.0 commit until Phase 2 GA)
6. Maintain che-word-mcp regression gate at 0 failures (zero risk because no existing code is modified)
7. Provide unit-test coverage exercising every case + every JSONL round-trip path

## Non-Goals

- OperationReducer / replay / time-travel / undo-redo (Phase 2b — `operation-reducer-impl`)
- Typed-view setter wiring (Phase 2c — `operation-log-setter-wiring-impl`)
- Sidecar file management (Phase 2c)
- WordDocument integration (no `operationLog` field on Document in this change)
- v0.32.0 GA tag (waits for Phase 2 bundle)
- Mutation API beyond `append` / `batch` (no remove, no replace)
- Snapshot caching (Phase 2b)
- `Operation` ↔ XmlNode tree synthesis from ops (Phase 2b reducer concern)

## Decisions

### Decision 1: `Operation` is a Swift enum with associated-value cases for typed ops + an `unknown` fallback for forward-compat

```swift
public enum Operation: Equatable, Sendable {
    case insertParagraphAfter(after: ElementID, paragraph: ParagraphPayload)
    case insertParagraphBefore(before: ElementID, paragraph: ParagraphPayload)
    case removeParagraph(id: ElementID)
    case setText(target: ElementID, text: String)
    case setParagraphStyle(target: ElementID, styleId: String?)
    case insertTable(at: ElementID, table: TablePayload)
    case removeTable(id: ElementID)
    case setCellText(table: ElementID, row: Int, column: Int, text: String)
    case insertRun(in: ElementID, position: Int, run: RunPayload)
    case setRunFormat(target: ElementID, format: RunFormatPayload)
    case insertBookmark(at: ElementID, bookmarkId: Int, name: String)
    case insertComment(anchor: ElementID, commentId: Int, text: String, author: String)
    case undo(targetOpID: UUID)
    case redo(targetOpID: UUID)
    case batchBegin(label: String?)
    case batchEnd
    case insertNode(parent: ElementID, position: Int, nodeXML: String)
    case removeNode(target: ElementID)
    case updateAttribute(target: ElementID, prefix: String?, localName: String, value: String?)
    case moveNode(source: ElementID, destinationParent: ElementID, destinationIndex: Int)
    case unknown(opType: String, payload: JSONValue)
}
```

**Why associated-value cases**: Swift's compile-time exhaustive switch on the enum is the type-system contract that says "Phase 2b reducer MUST handle every case". An untyped `payload: [String: Any]` would lose this guarantee and force runtime type checks throughout the reducer. Typed cases also let the JSONL encoder dispatch on case rather than parse `op_type` strings.

**Why `unknown(opType:payload:)` instead of throwing on unrecognized ops**: tasks 3.7's "forward-compatible log format" requires that "unknown op_type round-trips byte-equal; replay treats unknown ops as opaque". A future ooxml-swift version may emit ops the current version does not understand. Decoding to `.unknown` lets the local code carry them through (preserve, re-emit, but not interpret) without losing data. The reducer (Phase 2b) decides what to do with `.unknown` (likely: log a warning and pass through to the next op).

**Why payload structs (`ParagraphPayload`, `TablePayload`, etc.) and not raw `Paragraph` / `Table`**: the typed view types are tree-backed (carry an `XmlNode?`), but the JSONL log must be self-contained — a JSON line cannot reference a class instance. Payload structs are pure value types that serialize-deserialize cleanly. Phase 2b reducer materializes payloads back into typed views by constructing tree nodes.

### Decision 2: `ElementID` is a value type wrapping a `String` derivation

```swift
public struct ElementID: Equatable, Hashable, Sendable, Codable {
    public let raw: String   // e.g., "w14:paraId=0ABC1234" or "lib:550E8400-..."
    public init?(node: XmlNode) {
        if let stable = node.stableID { self.raw = stable; return }
        if let uuid = node.libraryUUID { self.raw = "lib:\(uuid.uuidString)"; return }
        return nil
    }
    public init(libraryUUID: UUID) { self.raw = "lib:\(libraryUUID.uuidString)" }
    public init(rawString: String) { self.raw = rawString }   // for JSONL decoding
}
```

**Why a value type, not a String alias**: type safety. A function taking `ElementID` cannot accidentally receive an arbitrary `String` like a part path or a paraId-without-prefix. The wrapper makes the contract explicit at compile time.

**Why `raw: String` and not a structured `(scheme: String, value: String)` pair**: byte-alignment with `XmlNode.stableID`. The reducer in Phase 2b needs to compare ElementID values across the OpLog and the XmlTree — keeping both sides as strings of the same format avoids serialization mismatches. The `raw` representation is parseable when needed (split on `=`).

**Why optional `init?(node:)`**: a node with no stable-ID attributes AND no `libraryUUID` legitimately has no ElementID. The optional initializer surfaces this at the call site rather than silently producing a useless ID.

### Decision 3: `OperationLog` is a value type (struct) with append-only mutating API

```swift
public struct OperationLog: Equatable, Sendable {
    public private(set) var entries: [LogEntry] = []
    public init() {}
    public mutating func append(_ op: Operation, source: OpSource, opID: UUID = UUID(), at timestamp: Date = Date()) {
        entries.append(LogEntry(opID: opID, op: op, source: source, timestamp: timestamp))
    }
    public mutating func batch(_ source: OpSource, label: String? = nil, _ body: (inout OperationLog) throws -> Void) rethrows {
        append(.batchBegin(label: label), source: source)
        try body(&self)
        append(.batchEnd, source: source)
    }
}

public struct LogEntry: Equatable, Sendable, Codable {
    public let opID: UUID
    public let op: Operation
    public let source: OpSource
    public let timestamp: Date
}

public enum OpSource: String, Equatable, Sendable, Codable {
    case swift
    case word
}
```

**Why a value type and not a class**: matches the rest of the typed model (Document is a struct). Append-only invariant is enforced by `private(set) var entries`. Two independent value-copies of an `OperationLog` evolve independently — desirable for unit testing without setup teardown.

**Why `OpSource` is an enum, not a String**: typed cases prevent typos and let the compiler check exhaustive handling. The enum has `Codable` conformance to serialize as `"swift"` / `"word"` per the task description.

**Why per-op UUID v4**: task 3.4 requires "every op gets a UUID v4". The `append(_:source:opID:at:)` exposes the `opID` parameter (defaulted to `UUID()`) so test code can supply deterministic IDs while production calls auto-generate.

**Why `batch(_:label:_:)` is a method rather than free-standing markers**: makes it impossible to forget `batchEnd` — Swift's `defer`-equivalent block scope guarantees the end marker fires even on throw. The closure-based API is also more discoverable than manual `append(.batchBegin); ...; append(.batchEnd)` patterns.

### Decision 4: JSONL format is one JSON object per line, lossy fields excluded, unknown ops carry their full payload

JSONL line format (each line is a complete JSON object encoding a `LogEntry`):

```json
{"op_id":"550E8400-E29B-41D4-A716-446655440000","ts":"2026-05-07T01:30:00Z","source":"swift","op_type":"setText","target":"w14:paraId=0ABC1234","text":"Hello"}
```

Encoding rules:
- One `LogEntry` per line; lines separated by `\n` (Unix LF, not CRLF)
- Field order: `op_id`, `ts`, `source`, `op_type`, then op-specific fields in the order their case associated values declare
- ISO-8601 UTC for timestamps (`Date` → `"2026-05-07T01:30:00Z"`)
- UUIDs as uppercase hex with dashes (`UUID.uuidString` default)
- ElementID raw string is used directly (e.g., `"w14:paraId=..."`)
- For `.unknown(opType:payload:)`, the entry SHALL emit `op_type` = the carried opType and merge the JSONValue payload as additional fields verbatim

Decoding rules:
- Each line is parsed as a JSON object
- Required fields: `op_id`, `ts`, `source`, `op_type`
- Dispatch on `op_type`: known cases decode their associated values; unknown decodes to `.unknown(opType:, payload: ...)` with the entire JSON object minus the four required fields stored as the JSONValue payload
- A `.unknown` LogEntry re-encodes byte-identically because the original payload JSONValue is preserved verbatim and the four required fields are deterministic

**Why custom JSONL format and not, say, NDJSON-with-concatenated-JSONEncoder**: forward-compat (handling unknown `op_type`) requires custom encoding logic anyway. Doing JSONL by hand on top of `JSONSerialization` is straightforward and gives the byte-exact control the spec scenario demands.

**Why `op_type` as a discriminator field**: standard tagged-union JSON pattern. Maps cleanly onto Swift `Codable`'s manual `init(from:)` / `encode(to:)` dispatch.

**Why no `trace` / `parent_op_id` / etc. metadata fields in this scaffold**: out of scope. Phase 2b reducer may need them for undo/redo; if so, this change's JSONL format will need extension. The spec's "forward-compatible" guarantee covers this — extension fields show up as `.unknown`-equivalent extra payload that the decoder ignores but the encoder carries through.

### Decision 5: `JSONValue` is a custom enum, not `[String: Any]`

```swift
public indirect enum JSONValue: Equatable, Sendable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}
```

**Why a custom enum**: Swift's `Any` is not `Sendable` and has fragile equality. A typed `JSONValue` enum gives `Equatable + Sendable + Codable` for free. The forward-compat unknown-op payload carries arbitrary JSON, so we need a representation that round-trips through Foundation's JSON without loss.

**Why `indirect enum` and not a class wrapper**: value semantics, plus `Sendable` works without locks. The recursion overhead is negligible for typical op payloads (a few keys and values).

### Decision 6: File organization — new `OpLog/` module under `Sources/OOXMLSwift/`

```
Sources/OOXMLSwift/OpLog/
├── Operation.swift          (Operation enum + payload structs + JSONValue)
├── ElementID.swift          (ElementID value type + derivation)
├── OperationLog.swift       (OperationLog + LogEntry + OpSource + batch helper)
└── OperationLog+JSONL.swift (encodeJSONL / decodeJSONL)

Tests/OOXMLSwiftTests/
└── OperationLogTests.swift  (one test class with sections for each file's contracts)
```

Mirrors the existing `Tree/` module organization (5 files for tree IO landed in v0.30.0). Keeps OpLog code physically separated from the typed model — easier to delete cleanly if Phase 5 ever needs to.

### Decision 7: No `WordDocument.operationLog` field in this change

Phase 2b/2c will decide whether the log lives on `WordDocument` or on a sibling `SyncOrchestrator` (per Phase 3's design — see `word-aligned-state-sync/design.md`). Adding an `operationLog: OperationLog?` to Document now would lock in a decision that's better made when the reducer + setter wiring drive concrete usage patterns.

This change keeps OpLog types fully self-contained — they're constructible / appendable / serializable in isolation, validated by unit tests that don't go through Document. Phase 2b decides integration shape.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| The `Operation` enum's case set drifts from what Phase 2b reducer needs | The 16 element-level + 4 tree-node-level cases are sourced verbatim from `word-aligned-state-sync/tasks.md` task 3.1. Phase 2b may discover missing cases — those are added as additive enum extensions (additive enum extension is non-breaking for downstream consumers per Swift evolution rules). |
| JSONL decoder fails to round-trip an `.unknown` op byte-equal because field ordering varies | Use a deterministic encoder: emit required fields (`op_id`, `ts`, `source`, `op_type`) first in fixed order, then emit unknown payload keys sorted lexicographically. This pins byte-equality across encode/decode/encode cycles. Test `testJSONLForwardCompat` verifies. |
| `ElementID(node:)` returns nil for nodes without any stable identity, breaking ops that reference such a node | Caller responsibility: an op that targets an ElementID-less node is malformed. The reducer (Phase 2b) will assign a `libraryUUID` to such nodes BEFORE constructing ops. This change exposes the optional initializer so the assignment step is explicit. |
| Serializing `Operation` cases with associated structs (e.g., `ParagraphPayload`) couples this change's JSONL format to those struct shapes — future struct field additions would change the JSONL bytes | Payload structs in this change carry the **minimum** fields needed by the typed-view setters they support. Future field additions are expected to be additive and decode-tolerant (missing fields → defaults). The forward-compat scenario covers cross-version add-only changes via the `.unknown` fallback for new op_types and via decode-tolerance on extra fields for existing op_types. |
| che-word-mcp regression risk from the new module | Essentially zero. This change adds NEW files in a NEW directory. No existing source file is modified. Regression risk only via Swift module-graph weirdness (e.g., test target trying to import OpLog/ from somewhere unexpected). The 297-test gate validates. |

## Open Items

- (none — all 7 decisions are explicitly resolved)
