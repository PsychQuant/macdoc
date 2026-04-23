## MODIFIED Requirements

### Requirement: open_document supports autosave_every for periodic checkpoint

The `open_document` MCP tool SHALL accept an optional `autosave_every: Int` parameter, **default `1`** (changed from `0` in v3.7.0). When `autosave_every > 0`, the server SHALL maintain a per-`doc_id` mutation counter (`autosaveCounter`) initialized to `0` at session creation. Mutating handlers SHALL invoke a checkpoint dispatch helper at the START of execution (Design B, pre-mutation snapshot), BEFORE applying the mutation. When `autosaveCounter[docId] > 0` AND `autosaveCounter[docId] % autosave_every == 0`, the server SHALL synchronously write the CURRENT in-memory state (i.e., the state representing all mutations 1..K-1 successfully applied so far) to `<source>.autosave.docx` via `DocxWriter.write` (atomic-rename). After the checkpoint write completes (or is skipped because the modulus does not match), the mutating handler SHALL proceed to apply mutation K. After mutation K succeeds, `autosaveCounter[docId]` SHALL be incremented by 1.

The autosave file path is always `<source>.autosave.docx` in the same directory as the document's source path. There is exactly one autosave file per session — consecutive checkpoints overwrite the prior `.autosave.docx`.

`autosave_every: 0` means no automatic checkpointing (caller must use explicit `checkpoint` tool or `save_document` for durability). The default value `1` means every mutation triggers a pre-snapshot, providing maximum recovery safety at the cost of one `DocxWriter.write` per mutation.

#### Scenario: Default autosave_every preserves prior mutations on crash mid-batch

- **GIVEN** `open_document(path: "/tmp/test.docx", doc_id: "d1")` is called WITHOUT explicit `autosave_every` (so default `1` applies)
- **WHEN** `insert_paragraph(doc_id: "d1", text: "MUT_1")` runs successfully (counter goes 0 → 1)
- **AND** `insert_paragraph(doc_id: "d1", text: "MUT_2")` runs successfully (counter goes 1 → 2; pre-mutation snapshot at start captured state with MUT_1 only)
- **AND** `insert_paragraph(doc_id: "d1", text: "MUT_3")` invokes pre-mutation snapshot capturing state with MUT_1 + MUT_2, then crashes during the insert itself
- **THEN** `/tmp/test.docx.autosave.docx` exists with state representing MUT_1 + MUT_2 (the pre-snapshot from mutation 3's start)
- **AND** the in-memory state (now lost from crash) would have included MUT_1 + MUT_2 + MUT_3 if mutation 3 had succeeded
- **AND** post-restart `open_document(path: "/tmp/test.docx", ...)` returns `autosave_detected: true`; caller can `recover_from_autosave` to restore MUT_1 + MUT_2

#### Scenario: autosave fires before every Nth mutation

- **GIVEN** `open_document(path: "/tmp/test.docx", doc_id: "d1", autosave_every: 3)` is called
- **WHEN** 7 sequential mutating tool calls (`insert_paragraph`, etc.) are issued
- **THEN** before mutation 1 the counter is 0, snapshot is skipped (counter not yet > 0); after mutation 1 succeeds, counter goes to 1
- **AND** before mutation 2 the counter is 1, 1 % 3 ≠ 0, snapshot skipped; after mutation 2 succeeds, counter goes to 2
- **AND** before mutation 3 the counter is 2, 2 % 3 ≠ 0, snapshot skipped; after mutation 3 succeeds, counter goes to 3
- **AND** before mutation 4 the counter is 3, 3 % 3 == 0, SNAPSHOT FIRES capturing post-MUT_3 state; after mutation 4 succeeds, counter goes to 4
- **AND** before mutation 7 the counter is 6, 6 % 3 == 0, SNAPSHOT FIRES capturing post-MUT_6 state; after mutation 7 succeeds, counter goes to 7

##### Example: Counter trajectory at N=3 with 7 mutations

Given `autosave_every: 3`:
- Pre-mutation 1 (counter=0): no snapshot. Mutation succeeds. Counter → 1.
- Pre-mutation 2 (counter=1, 1%3≠0): no snapshot. Mutation succeeds. Counter → 2.
- Pre-mutation 3 (counter=2, 2%3≠0): no snapshot. Mutation succeeds. Counter → 3.
- Pre-mutation 4 (counter=3, 3%3=0): **SNAPSHOT** captures state with MUT_1, MUT_2, MUT_3 applied. Mutation 4 then runs. Counter → 4.
- Pre-mutation 5 (counter=4, 4%3≠0): no snapshot. Mutation succeeds. Counter → 5.
- Pre-mutation 6 (counter=5, 5%3≠0): no snapshot. Mutation succeeds. Counter → 6.
- Pre-mutation 7 (counter=6, 6%3=0): **SNAPSHOT** OVERWRITES with state through MUT_6. Mutation 7 then runs. Counter → 7.

Crash during mutation 4: autosave file holds state through MUT_3 (the pre-snapshot just captured). Crash during mutation 7: autosave file holds state through MUT_6.

#### Scenario: autosave_every of 0 disables autosave

- **GIVEN** `open_document(path: "/tmp/test.docx", doc_id: "d1", autosave_every: 0)` is called explicitly
- **WHEN** 100 mutating tool calls are issued
- **THEN** `/tmp/test.docx.autosave.docx` does NOT exist at any point during or after the calls
- **AND** the autosave counter is never incremented

#### Scenario: Successful save_document cleans up .autosave.docx

- **GIVEN** an autosave file `/tmp/test.docx.autosave.docx` exists from prior pre-mutation snapshots
- **WHEN** `save_document(doc_id: "d1", path: "/tmp/test.docx")` succeeds
- **THEN** after the call, `/tmp/test.docx.autosave.docx` no longer exists
- **AND** `/tmp/test.docx` contains the new bytes
- **AND** `autosaveCounter[docId]` is reset to `0` (next mutation cycle starts fresh)

## ADDED Requirements

### Requirement: WordMCPServer logs structured diagnostics under CHE_WORD_MCP_LOG_LEVEL env var

The `WordMCPServer` actor SHALL emit structured diagnostic logs to `FileHandle.standardError` when the environment variable `CHE_WORD_MCP_LOG_LEVEL=debug` is set at process start. Logs SHALL be off by default (no env var or any other value → silent). When enabled, the following events SHALL be logged with timestamps and structured key-value pairs:

- `insertImageFromPath` entry: doc_id, anchor type (before_text/after_text/intoTableCell/index), anchor target, image path
- `insertImageFromPath` exit: doc_id, returned image rId, elapsed ms
- `findBodyChildContainingText` entry: doc_id, search text (truncated to 40 chars), nthInstance, body.children.count
- `storeDocument` entry: doc_id, autosaveCounter, autosaveEvery
- `storeDocument` exit: doc_id, new autosaveCounter, checkpoint dispatched (true/false)
- `dispatchAutosaveCheckpoint` entry/exit: doc_id, autosave path, snapshot bytes written, elapsed ms

The log format SHALL be one line per event in the form `[YYYY-MM-DDTHH:MM:SS.sssZ] LEVEL EventName key1=value1 key2=value2`. The implementation SHALL use a single private logger function inside `WordMCPServer` to ensure all events follow the same format.

#### Scenario: Logging disabled by default

- **GIVEN** `WordMCPServer` is started without `CHE_WORD_MCP_LOG_LEVEL` set in the environment
- **WHEN** any number of MCP tool calls are processed
- **THEN** `FileHandle.standardError` receives zero log output from the diagnostic logger (other server warnings unaffected)

#### Scenario: Debug logging captures handler entry/exit

- **GIVEN** the server process is started with `CHE_WORD_MCP_LOG_LEVEL=debug`
- **AND** a session is opened on `/tmp/test.docx` as `doc_id: "d1"` with `autosave_every: 3`
- **WHEN** an `insert_image_from_path(doc_id: "d1", before_text: "圖43", path: "...")` call is processed
- **THEN** stderr contains lines tagged `insertImageFromPath` (entry + exit), `findBodyChildContainingText` (entry), `storeDocument` (entry + exit) in chronological order
- **AND** the `storeDocument` entry line includes `autosaveCounter=2` and `autosaveEvery=3` (assuming this is the 3rd insert)

