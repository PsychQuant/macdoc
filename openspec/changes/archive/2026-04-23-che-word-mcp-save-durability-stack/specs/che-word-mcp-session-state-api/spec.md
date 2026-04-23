## ADDED Requirements

### Requirement: WordMCPServer is an actor for concurrent-safe session state

The `che-word-mcp` `WordMCPServer` SHALL be declared as a Swift `actor` (not `class`). All mutable session state dictionaries (`openDocuments`, `documentOriginalPaths`, `documentDirtyState`, `documentAutosave`, `documentTrackChangesEnforced`, `documentDiskHash`, `documentDiskMtime`, plus any new dictionaries added by Phase 4) SHALL be actor-isolated stored properties. All cross-actor access SHALL be via `await` (compiler-enforced).

This requirement closes a class of data race where parallel async tasks (e.g., 12 concurrent `insert_image_from_path` calls) mutate the same dictionary without synchronization, causing Swift `Dictionary` hash table corruption and subsequent process crash.

#### Scenario: 50 concurrent mutations do not crash or corrupt state

- **WHEN** 50 concurrent `insert_image_from_path` tasks targeting the same `doc_id` are dispatched via `await withTaskGroup`
- **AND** the test runs 100 iterations under ThreadSanitizer (`swift test -Xswiftc -sanitize=thread`)
- **THEN** no iteration crashes, throws unexpected errors, or triggers a TSan data race report
- **AND** `openDocuments[docId]?.images.count` after all tasks complete equals exactly 50 (no lost mutations from race)

#### Scenario: Actor reentrancy preserves mutation invariants

- **WHEN** a mutating handler `H1` calls `await self.<helper>()` mid-mutation
- **AND** another handler `H2` is suspended waiting for the actor
- **THEN** when `H2` resumes, the session state H2 observes is consistent (no half-written dictionaries)

### Requirement: save_document supports keep_bak opt-in for rollback escape hatch

The `save_document` MCP tool SHALL accept an optional `keep_bak: Bool` parameter, default `false`. When `keep_bak == true`, before delegating to `DocxWriter.write`, the server SHALL rename the existing target file to `<target>.bak` (overwriting any prior `.bak` at the same path). If the target file does not yet exist, no rename occurs (no-op). The `.bak` rename uses `FileManager.default.moveItem` which is atomic within the same filesystem.

The `.bak` file SHALL persist after the save. The server SHALL NOT auto-delete `.bak` files on `close_document` or any other tool call. Cleanup is the caller's responsibility.

The `.bak` policy lives at the `che-word-mcp` server layer (in `Server.swift` `persistDocumentToDisk`), NOT in `ooxml-swift` `DocxWriter`. Other consumers of `ooxml-swift` (e.g., `macdoc` CLI) SHALL NOT receive `.bak` side effects.

#### Scenario: keep_bak true preserves pre-save bytes

- **WHEN** `save_document(doc_id: "d1", path: "/tmp/test.docx", keep_bak: true)` is called and `/tmp/test.docx` previously contained 169584-byte original
- **THEN** after the call, `/tmp/test.docx` contains the new bytes
- **AND** `/tmp/test.docx.bak` exists and its SHA256 matches the original 169584-byte hash

#### Scenario: keep_bak default is opt-out (false)

- **WHEN** `save_document(doc_id: "d1", path: "/tmp/test.docx")` is called without `keep_bak` arg
- **THEN** after the call, `/tmp/test.docx.bak` does NOT exist
- **AND** `/tmp/test.docx` contains the new bytes

#### Scenario: Consecutive saves overwrite .bak

- **WHEN** two consecutive `save_document(...keep_bak: true)` calls run on the same target
- **THEN** after the second call, `<target>.bak` contains the bytes from BEFORE the second call (i.e., the result of the first call), not the original-original bytes

#### Scenario: First-time save with no existing target

- **WHEN** `save_document(doc_id: "d1", path: "/tmp/new.docx", keep_bak: true)` is called and `/tmp/new.docx` does not exist
- **THEN** after the call, `/tmp/new.docx` exists with new bytes
- **AND** `/tmp/new.docx.bak` does NOT exist (nothing to back up)

### Requirement: open_document supports autosave_every for periodic checkpoint

The `open_document` MCP tool SHALL accept an optional `autosave_every: Int` parameter, default `0` (disabled). When `autosave_every > 0`, the server SHALL maintain a per-`doc_id` mutation counter. Every successful mutating handler SHALL increment the counter. When `counter % autosave_every == 0`, the server SHALL dispatch a checkpoint write to `<target>.autosave.docx` using `DocxWriter.write` (which internally uses Phase 1 atomic-rename).

The autosave file path is always `<target>.autosave.docx` in the same directory as the document's source path. There is exactly one autosave file per session — consecutive checkpoints overwrite the prior `.autosave.docx`.

`autosave_every` of `0` means no automatic checkpointing (caller must use explicit `checkpoint` tool or `save_document` for durability).

#### Scenario: autosave fires at every Nth mutation

- **WHEN** `open_document(path: "/tmp/test.docx", doc_id: "d1", autosave_every: 3)` is called
- **AND** 7 mutating tool calls (`insert_paragraph`, etc.) are issued sequentially
- **THEN** `/tmp/test.docx.autosave.docx` exists after the 3rd mutation
- **AND** `/tmp/test.docx.autosave.docx` is overwritten after the 6th mutation
- **AND** `/tmp/test.docx.autosave.docx` is NOT updated after the 7th mutation (next dispatch would be at 9)

#### Scenario: autosave_every of 0 disables autosave

- **WHEN** `open_document(path: "/tmp/test.docx", doc_id: "d1", autosave_every: 0)` is called
- **AND** 100 mutating tool calls are issued
- **THEN** `/tmp/test.docx.autosave.docx` does NOT exist at any point during or after the calls

#### Scenario: Successful save_document cleans up .autosave.docx

- **WHEN** an autosave file `/tmp/test.docx.autosave.docx` exists from prior checkpoints
- **AND** `save_document(doc_id: "d1", path: "/tmp/test.docx")` succeeds
- **THEN** after the call, `/tmp/test.docx.autosave.docx` no longer exists
- **AND** `/tmp/test.docx` contains the new bytes (consistent with autosave content modulo any post-checkpoint mutations)

##### Example: Counter at N=3 with 7 mutations

Given `autosave_every: 3`:
- Mutation 1 (counter=1, `1 % 3 = 1`) → no checkpoint
- Mutation 2 (counter=2, `2 % 3 = 2`) → no checkpoint
- Mutation 3 (counter=3, `3 % 3 = 0`) → checkpoint fires, write `<target>.autosave.docx`
- Mutation 4 (counter=4) → no checkpoint
- Mutation 5 (counter=5) → no checkpoint
- Mutation 6 (counter=6, `6 % 3 = 0`) → checkpoint fires, OVERWRITE `<target>.autosave.docx`
- Mutation 7 (counter=7) → no checkpoint

### Requirement: checkpoint MCP tool for manual session state write

The `che-word-mcp` server SHALL expose a `checkpoint` MCP tool with signature `checkpoint(doc_id: String, path: String?)`. When called, it SHALL write the current in-memory session state for `doc_id` to disk:
- If `path` is provided, write to that path using `DocxWriter.write` (atomic-rename).
- If `path` is omitted, write to `<source_path>.autosave.docx` (same path the autosave_every counter would use).

Checkpoint SHALL NOT clear the session's `is_dirty` flag (unlike `save_document` which represents a "real" save). Checkpoint SHALL NOT update the `disk_hash` or `disk_mtime` session fields (those track the canonical target path, not the autosave path).

`checkpoint` is callable regardless of whether `autosave_every` was set on `open_document`. It is the manual complement to the automatic per-N-mutations throttle.

#### Scenario: Manual checkpoint writes to autosave path by default

- **WHEN** `checkpoint(doc_id: "d1")` is called on a session opened from `/tmp/test.docx`
- **THEN** `/tmp/test.docx.autosave.docx` exists with current in-memory session bytes
- **AND** `get_session_state(doc_id: "d1")` still reports `is_dirty: true` (checkpoint doesn't reset dirty)

#### Scenario: Manual checkpoint with explicit path

- **WHEN** `checkpoint(doc_id: "d1", path: "/tmp/snapshot-001.docx")` is called
- **THEN** `/tmp/snapshot-001.docx` exists with current in-memory session bytes
- **AND** `/tmp/test.docx.autosave.docx` is NOT modified by this call

### Requirement: open_document detects existing autosave file

When `open_document(path: <target>, doc_id: <id>)` is called, the server SHALL check whether `<target>.autosave.docx` exists in the same directory. If it exists, the server SHALL include `autosave_detected: true` and `autosave_path: "<target>.autosave.docx"` in the session state returned by `get_session_state(doc_id)` and `get_document_session_state(doc_id)`. Otherwise these fields SHALL be `false` and `null` respectively.

`open_document` SHALL NOT auto-recover from the autosave file. Recovery requires explicit `recover_from_autosave(doc_id)` invocation.

The detection check is a single `FileManager.default.fileExists(atPath:)` call — performance impact is negligible.

#### Scenario: Stale autosave file flagged in session state

- **WHEN** `/tmp/test.docx.autosave.docx` exists from a prior crashed session
- **AND** `open_document(path: "/tmp/test.docx", doc_id: "d1")` is called
- **THEN** `get_session_state(doc_id: "d1")` returns `autosave_detected: true, autosave_path: "/tmp/test.docx.autosave.docx"`
- **AND** the in-memory session state matches the bytes at `/tmp/test.docx` (NOT the autosave file)

#### Scenario: No autosave file present

- **WHEN** `/tmp/test.docx.autosave.docx` does NOT exist
- **AND** `open_document(path: "/tmp/test.docx", doc_id: "d1")` is called
- **THEN** `get_session_state(doc_id: "d1")` returns `autosave_detected: false, autosave_path: null`

### Requirement: recover_from_autosave MCP tool replaces session state with autosave bytes

The `che-word-mcp` server SHALL expose a `recover_from_autosave(doc_id: String, discard_changes: Bool = false)` MCP tool. When called:
- If `<target>.autosave.docx` does not exist for the session's source path, return error `E_NO_AUTOSAVE`.
- If the current session is dirty (`is_dirty == true`) and `discard_changes != true`, return error `E_DIRTY_DOC` listing recovery paths (matching `close_document` dirty-check pattern).
- Otherwise: read the autosave file via `DocxReader.read`, replace `openDocuments[doc_id]` with the loaded `WordDocument`, set `is_dirty = true` (caller still needs explicit `save_document` to commit), do NOT delete the autosave file (cleanup happens on next successful `save_document`).

Recovery is "replace current state with autosave bytes" — NOT a 3-way merge. The autosave file IS the source of truth for the recovered state.

#### Scenario: Recovery replaces session state with autosave bytes

- **WHEN** session `d1` was opened from `/tmp/test.docx` (5 paragraphs)
- **AND** `/tmp/test.docx.autosave.docx` exists with 12 paragraphs from a prior crashed session
- **AND** session `d1` has not been mutated since open (`is_dirty == false`)
- **AND** `recover_from_autosave(doc_id: "d1")` is called
- **THEN** `openDocuments["d1"].body.children.count` is 12 (not 5)
- **AND** `get_session_state(doc_id: "d1")` returns `is_dirty: true`
- **AND** `/tmp/test.docx.autosave.docx` still exists (cleanup deferred to next save)

#### Scenario: Recovery refused on dirty session without discard_changes

- **WHEN** session `d1` has 3 in-memory mutations (`is_dirty == true`)
- **AND** `recover_from_autosave(doc_id: "d1")` is called WITHOUT `discard_changes: true`
- **THEN** the call returns error `E_DIRTY_DOC` listing the 3 recovery options (`save_document` / `discard_changes: true` / `finalize_document`)
- **AND** the in-memory session state is NOT modified

#### Scenario: Recovery error when no autosave file

- **WHEN** `/tmp/test.docx.autosave.docx` does NOT exist
- **AND** `recover_from_autosave(doc_id: "d1")` is called
- **THEN** the call returns error `E_NO_AUTOSAVE`
