## ADDED Requirements

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

### Requirement: Operation IDs are unique and stable

Every `LogEntry` SHALL carry a `UUID` v4 in its `opID` field. UUIDs SHALL be unique across all entries in any single log (UUID v4 collision probability is treated as zero per the cryptographic standard). UUIDs SHALL be stable: the value assigned at `append` time persists through serialization and deserialization unchanged.

#### Scenario: opID round-trips through JSONL byte-equal

- **GIVEN** a log entry with `opID == UUID(uuidString: "AABBCCDD-1234-4567-8999-EEFF00112233")!`
- **WHEN** the log is encoded to JSONL and decoded back
- **THEN** the decoded entry's `opID` SHALL equal `UUID(uuidString: "AABBCCDD-1234-4567-8999-EEFF00112233")!`

### Requirement: Source attribution for every operation

Every `LogEntry` SHALL carry a `source: OpSource` field whose value is `.swift` (Swift code emitted the op) or `.word` (Word app's edit was the source — used by Phase 3 SyncOrchestrator import).

#### Scenario: source round-trips through JSONL

- **GIVEN** a log with one entry of source `.word`
- **WHEN** the log is encoded to JSONL and decoded back
- **THEN** the decoded entry's `source` SHALL equal `.word`

### Requirement: Forward-compatible log format

The `OperationLog` JSONL on-disk format SHALL preserve unknown `op_type` values byte-equal across encode → decode → encode cycles. This forward-compat guarantee enables version-skewed log files: a log emitted by ooxml-swift v0.31.4 SHALL be decode-able by an older v0.31.3 reader, with v0.31.3 carrying any newer ops as `.unknown` and re-emitting them byte-identically.

#### Scenario: ooxml-swift v0.31.4 emits an op v0.31.3 doesn't recognize

- **GIVEN** a JSONL log containing an op_type that the local code's `Operation` enum does not declare
- **WHEN** the local code reads the log via `decodeJSONL`, appends one local typed op, and re-emits the log via `encodeJSONL`
- **THEN** the re-emitted bytes SHALL contain the original unknown line byte-equal to its input form
- **AND** the new typed op line SHALL appear after it in the expected JSONL format

### Requirement: Batch transactions for grouped mutations

`OperationLog.batch(_:label:_:)` SHALL emit a `batchBegin(label:)` op before the closure body executes and a `batchEnd` op after the closure body returns normally. The label SHALL be carried in the `batchBegin` op's associated value for human-readable correlation in log diffs and audits.

#### Scenario: batch emits begin/end markers around body ops

- **WHEN** `log.batch(.swift, label: "rename") { lb in lb.append(.setText(...), source: .swift); lb.append(.setParagraphStyle(...), source: .swift) }` is called
- **THEN** `log.entries.count` SHALL equal `4`
- **AND** the entries SHALL be `[batchBegin(label: "rename"), setText(...), setParagraphStyle(...), batchEnd]` in that order

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
