## ADDED Requirements

### Requirement: SyncOrchestrator coordinates Word and Swift writers

The library SHALL provide `SyncOrchestrator` that owns the bidirectional state alignment between an in-memory `OperationLog` and an on-disk `.docx` file. The orchestrator SHALL detect out-of-band docx changes (Word saves), import them as operations into the log, and serialize Swift-originated changes back to the docx.

#### Scenario: Word save is detected and imported

- **GIVEN** a `SyncOrchestrator` watching `report.docx` and a current snapshot taken at time `t0`
- **WHEN** Word saves the docx at time `t1 > t0` with edits to paragraph `p`
- **THEN** the orchestrator detects the change (by mtime + content hash), reads the new docx into a tree, computes the diff against the snapshot, and appends one or more operations to the log with `source: "word"`

#### Scenario: Swift mutation flushes to docx

- **WHEN** Swift code calls `paragraph.text = "x"` and the orchestrator's `flush()` runs
- **THEN** the orchestrator materializes the log against the base tree, serializes the resulting tree to `report.docx` via `XmlTreeWriter`, and updates the on-disk snapshot

### Requirement: Word-import diff via element identity matching

The Word-import diff algorithm SHALL match elements first by stable OOXML ID (`w14:paraId`, `w:bookmarkId`, `w:id` on comments), then by structural fingerprint (tag + namespace + key attributes + parent path) for elements lacking stable IDs. Identity-noise (rsids, default attributes) SHALL be normalized before comparison per `ooxml-tree-io`'s `XmlNode.normalizedFingerprint()`.

#### Scenario: Matched-by-ID element with text change produces SetText

- **GIVEN** a snapshot tree containing paragraph with `w14:paraId="ABC"` and text `"original"`, and a re-read tree containing the same paraId with text `"modified"`
- **WHEN** the diff runs
- **THEN** the inferred operation set is `[SetText(elementID: paraID("ABC"), value: "modified")]`

#### Scenario: rsid-only difference produces empty op set

- **GIVEN** a Word save where every `w:rsidR` value changed but no content changed
- **WHEN** the diff runs against the prior snapshot
- **THEN** the inferred operation set is empty

#### Scenario: New paragraph in Word produces InsertParagraphAfter

- **GIVEN** a snapshot with paragraphs `[p1, p2]`, and a re-read tree with `[p1, p_new, p2]` where `p_new` has new content
- **WHEN** the diff runs
- **THEN** the operation set contains `InsertParagraphAfter(after: p1.id, ...)` carrying `p_new`'s content

### Requirement: Conflict detection on overlapping mutations

When the diff produces an operation that targets an element already mutated by Swift-originated operations not yet flushed, the orchestrator SHALL emit a `ConflictReport` listing each conflicting `ElementID`, the Swift-originated op_id, and the Word-inferred op.

#### Scenario: Overlapping text edit raises conflict

- **GIVEN** Swift's pending log contains `SetText(elementID: p, value: "swift_text")` not yet flushed, and Word saves the docx with `p`'s text changed to `"word_text"`
- **WHEN** the orchestrator imports
- **THEN** a `ConflictReport` is emitted with one entry referencing `p`, both op identifiers, and both proposed values

### Requirement: Typed conflict policy

The orchestrator's import API SHALL accept a `SyncPolicy` enum with at minimum cases `.abortOnConflict` (default), `.swiftWins`, `.wordWins`, and `.askUser(handler:)`.

#### Scenario: abortOnConflict throws structured error

- **WHEN** a conflict occurs and the policy is `.abortOnConflict`
- **THEN** the orchestrator throws `SyncError.conflict(report: ConflictReport)`; the log is not modified

#### Scenario: swiftWins drops Word's conflicting ops

- **WHEN** a conflict occurs and the policy is `.swiftWins`
- **THEN** the orchestrator's import path retains all non-conflicting Word ops, drops Word ops conflicting with pending Swift ops, and the conflicting Swift ops remain in the pending state

#### Scenario: askUser handler decides per element

- **WHEN** a conflict occurs and the policy is `.askUser(handler:)`
- **THEN** the orchestrator invokes `handler(conflict: ConflictReport)` synchronously; the handler returns a `Resolution` per conflicting element (`.takeSwift` / `.takeWord`); the orchestrator applies the chosen resolutions

### Requirement: File watcher contract

The orchestrator SHALL detect docx changes by combining file modification time and SHA-256 content hash. The watcher SHALL NOT depend on inotify/fsevents APIs unavailable across all macOS versions ooxml-swift supports; polling at a configurable interval (default 1 second) is acceptable.

#### Scenario: mtime-only change without content change is ignored

- **WHEN** an external tool touches the docx (`mtime` updates) but the file content hash is unchanged
- **THEN** the orchestrator does not trigger an import

#### Scenario: Content change triggers import

- **WHEN** the file content hash changes between consecutive watcher polls
- **THEN** the orchestrator invokes the import path with the new content

### Requirement: Word file-lock interaction

When Word holds the docx open with its `~$<filename>.docx` lock file present, Swift writes to the docx SHALL refuse with `SyncError.fileLockedByWord`. The orchestrator SHALL detect Word's lock-file lifecycle as the boundary of a Word edit session.

#### Scenario: Swift write while Word holds lock

- **GIVEN** Word has the docx open and `~$report.docx` exists in the same directory
- **WHEN** the orchestrator's `flush()` is called
- **THEN** it throws `SyncError.fileLockedByWord` and does not write to the docx

#### Scenario: Lock-file disappearance triggers final import

- **GIVEN** Word has been editing and `~$report.docx` exists
- **WHEN** Word closes and the lock-file is removed
- **THEN** the orchestrator schedules an import to capture Word's final saved state

### Requirement: Sidecar persistence of snapshot and log

The orchestrator SHALL persist the operation log as `<docx-stem>.oplog.jsonl` and the most-recently-imported snapshot tree as `<docx-stem>.snapshot.json` in the same directory as the docx. The orchestrator SHALL NOT write metadata into the docx itself.

#### Scenario: Sidecar files created on first sync

- **WHEN** `SyncOrchestrator.bootstrapFromDocx(url:)` runs on a docx with no existing sidecar files
- **THEN** `<docx-stem>.oplog.jsonl` is created (initially empty) and `<docx-stem>.snapshot.json` is created with the initial tree snapshot

#### Scenario: docx contains zero sync metadata

- **WHEN** the orchestrator writes the docx via `flush()`
- **THEN** the resulting docx contains no library-generated UUIDs, no `<library:*>` elements, and no custom relationship parts beyond what was already present

### Requirement: Bootstrap from existing docx

The orchestrator SHALL provide `SyncOrchestrator.bootstrapFromDocx(url:)` that initializes a sync session from any docx file (with or without existing sidecars). When sidecars are absent the orchestrator SHALL treat the current docx as the initial snapshot and start with an empty op log.

#### Scenario: Fresh docx without sidecars

- **GIVEN** `report.docx` exists with no `report.oplog.jsonl` and no `report.snapshot.json`
- **WHEN** `bootstrapFromDocx(url:)` runs
- **THEN** sidecars are created with the docx's current state as the snapshot and an empty log; subsequent Swift mutations append to the new log

#### Scenario: Existing sidecars are reused

- **GIVEN** `report.docx`, `report.oplog.jsonl` (with prior history), and `report.snapshot.json` (from prior session) all exist
- **WHEN** `bootstrapFromDocx(url:)` runs
- **THEN** the orchestrator loads the existing log and snapshot; if the docx has changed since the snapshot's timestamp, an import diff is run to capture the intervening changes

### Requirement: Sidecar persistence is opt-in（spec-frozen from design Q1）

Sidecar files SHALL be written and read only through the explicit opt-in APIs（`WordDocument.saveWithSidecars(to:)` / `openWithSidecars(from:)` and the `SyncOrchestrator` bootstrap）. Plain `DocxWriter.write` / `DocxReader.read` SHALL NOT create, read, or modify sidecar files. Callers that never opt in never see sidecar files on disk.

#### Scenario: plain IO never touches sidecars

- **WHEN** a docx is read and written through the plain `DocxReader.read` / `DocxWriter.write` path
- **THEN** no `.oplog.jsonl` or `.snapshot.json` file is created, read, or modified

### Requirement: Word edit boundary is detected by content change, not save events（spec-frozen from design Q4）

The sync layer SHALL detect Word-side changes exclusively from file content change — mtime fast-path confirmed by SHA-256 content hash（`DocxChangeDetector`）— and SHALL treat the `~$<name>.docx` owner-file lifecycle（`WordLock`）as the edit-session boundary signal. The sync layer SHALL NOT hook Word save events, AppleScript notifications, or autosave timers.

#### Scenario: mtime-only touch is not an edit

- **WHEN** the docx's mtime changes but its content hash is unchanged
- **THEN** no Word-side change is reported

### Requirement: Single-writer assumption for the op log（spec-frozen from design Q5）

v1.0 SHALL assume a single Swift-side writer per docx: sidecar writes are atomic whole-file replaces and concurrent Swift writers are unsupported（last write wins — callers requiring multi-writer coordination must serialize externally）. The JSONL wire format（append-friendly lines, UUID `op_id` per entry）SHALL NOT be changed in ways that preclude a future multi-writer/CRDT extension（e.g., per-op vector clocks may be added as new optional envelope fields）.

#### Scenario: wire format leaves room for v2 coordination fields

- **WHEN** a future version adds a coordination field（e.g., `vclock`）to the line envelope
- **THEN** v1.0 readers decode such lines via the forward-compat rule（unknown envelope fields ignored; unknown op_types preserved byte-equal）
