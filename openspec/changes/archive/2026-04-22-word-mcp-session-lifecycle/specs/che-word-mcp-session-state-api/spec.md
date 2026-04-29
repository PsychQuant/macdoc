## ADDED Requirements

### Requirement: Session state tracks source path, disk hash, mtime, dirty bit, and track-changes flag per open document

The `che-word-mcp` server SHALL maintain per-`doc_id` session metadata covering: (a) `sourcePath: String` — file path from which the doc was read; (b) `diskHash: Data` — SHA256 of file bytes as of last successful read or write; (c) `diskMtime: Date` — file modification timestamp as of last successful read or write; (d) `isDirty: Bool` — true iff in-memory doc has been mutated since last write; (e) `trackChangesEnabled: Bool` — whether edit tools emit tracked revisions. Implementation MAY use separate parallel dictionaries keyed by `doc_id` (matching the existing Server.swift pattern for `documentOriginalPaths` / `documentDirtyState` / `documentAutosave` / `documentTrackChangesEnforced`) or a single struct — either satisfies the requirement. A read-only `SessionStateView` struct SHALL be used for tool response serialization.

Every handler that mutates the document SHALL set the session's `isDirty` to `true`. Every successful `save_document` / `finalize_document` SHALL refresh `diskHash` + `diskMtime` from the just-written file and set `isDirty` to `false`.

#### Scenario: Opening a document initializes session metadata with hash and mtime

- **WHEN** `open_document(path: "doc.docx", doc_id: "d1")` is called on an existing .docx file
- **THEN** `get_session_state(doc_id: "d1")` returns `source_path == "doc.docx"`, `disk_hash_hex == SHA256(fileBytes) hex`, `disk_mtime_iso8601 == file's modification date ISO8601`, `is_dirty == false`, `track_changes_enabled == false` (default per separate requirement)

#### Scenario: Mutation flips isDirty

- **WHEN** `insert_paragraph(doc_id: "d1", text: "x")` is called after `open_document`
- **THEN** `get_session_state(doc_id: "d1")` returns `is_dirty == true` and `disk_hash_hex` still equals the on-open value (not yet re-hashed — disk hasn't been written)

#### Scenario: Save resets dirty and refreshes hash

- **WHEN** `save_document(doc_id: "d1", path: "d1.docx")` succeeds after one or more mutations
- **THEN** `get_session_state(doc_id: "d1")` returns `is_dirty == false`, `disk_hash_hex == SHA256(newly-written bytes) hex`, `disk_mtime_iso8601 == freshly-written file's mtime`

### Requirement: open_document defaults track_changes to false

The `che-word-mcp` server's `open_document` MCP tool SHALL accept an optional `track_changes: Bool` parameter defaulting to `false`. When `true`, the server SHALL enable track changes on the opened document (equivalent to calling `enable_track_changes` immediately after open). When `false` or absent, track changes SHALL remain disabled. This is a BREAKING change from prior versions where track changes was enabled unconditionally.

#### Scenario: Default track_changes is off

- **WHEN** `open_document(path: "doc.docx", doc_id: "d1")` is called without `track_changes` argument
- **THEN** `openDocuments["d1"].trackChangesEnabled == false` and edits subsequently made via other tools do NOT produce `<w:ins>` / `<w:del>` revision marks

#### Scenario: Opt-in track_changes preserves prior-version behavior

- **WHEN** `open_document(path: "doc.docx", doc_id: "d1", track_changes: true)` is called
- **THEN** `openDocuments["d1"].trackChangesEnabled == true` and subsequent edits are recorded as tracked revisions

### Requirement: close_document rejects dirty documents without discard_changes

The `che-word-mcp` server's `close_document` MCP tool SHALL accept an optional `discard_changes: Bool` parameter defaulting to `false`. When the targeted document has `isDirty == true` and `discard_changes == false`, the server SHALL return an error containing the literal string `E_DIRTY_DOC` and an actionable message listing the three recovery paths: (a) call `save_document` first, (b) pass `discard_changes: true`, (c) use `finalize_document` for save+close. When `discard_changes == true`, the server SHALL remove the doc from `openDocuments` without saving. When `isDirty == false`, the server SHALL close normally regardless of the `discard_changes` value.

#### Scenario: Dirty doc close without discard_changes errors with E_DIRTY_DOC

- **WHEN** `close_document(doc_id: "d1")` is called on a document where `openDocuments["d1"].isDirty == true`
- **THEN** the tool returns an error message containing `E_DIRTY_DOC` and enumerates `save_document` / `discard_changes: true` / `finalize_document`
- **AND** `openDocuments["d1"]` SHALL remain in the dictionary unchanged

#### Scenario: Dirty doc close with discard_changes succeeds

- **WHEN** `close_document(doc_id: "d1", discard_changes: true)` is called on a dirty document
- **THEN** `openDocuments["d1"]` is removed and no write occurs to `sourcePath`

#### Scenario: Clean doc close succeeds regardless of flag

- **WHEN** `close_document(doc_id: "d1")` is called where `openDocuments["d1"].isDirty == false`
- **THEN** `openDocuments["d1"]` is removed and no error is returned

### Requirement: revert_to_disk drops in-memory changes

The `che-word-mcp` server SHALL provide a `revert_to_disk(doc_id)` MCP tool that re-reads the document's `sourcePath`, replaces `openDocuments[doc_id].document` with the freshly parsed value, refreshes `diskHash` + `diskMtime` from the just-read file, and sets `isDirty = false`. The tool SHALL NOT require a force flag; revert is explicitly destructive-by-design.

#### Scenario: Revert discards uncommitted edits

- **WHEN** `insert_paragraph(doc_id: "d1", text: "edit")` is called and then `revert_to_disk(doc_id: "d1")` is called
- **THEN** `openDocuments["d1"].document` no longer contains "edit", `isDirty == false`, and `diskHash` equals the hash of the source file on disk

### Requirement: reload_from_disk requires force on dirty documents

The `che-word-mcp` server SHALL provide a `reload_from_disk(doc_id, force: Bool = false)` MCP tool. When `openDocuments[doc_id].isDirty == true` and `force == false`, the tool SHALL return an error naming the uncommitted state and instructing the caller to either `save_document` first or pass `force: true`. When `force == true` or `isDirty == false`, the tool SHALL re-read the source file and replace the in-memory document (same side effects as `revert_to_disk` except semantic: reload picks up external edits, revert drops local edits).

#### Scenario: Reload on clean doc succeeds without force

- **WHEN** `reload_from_disk(doc_id: "d1")` is called on a document with `isDirty == false`
- **THEN** the tool re-reads `sourcePath` and updates `openDocuments["d1"]`

#### Scenario: Reload on dirty doc without force errors

- **WHEN** `reload_from_disk(doc_id: "d1")` is called on a document with `isDirty == true` and `force` absent or false
- **THEN** the tool returns an error whose message contains the word `force` and points the caller to `save_document`

#### Scenario: Reload on dirty doc with force succeeds

- **WHEN** `reload_from_disk(doc_id: "d1", force: true)` is called on a dirty document
- **THEN** the in-memory document is replaced with disk contents, losing the uncommitted edits

### Requirement: check_disk_drift reports current drift status

The `che-word-mcp` server SHALL provide a `check_disk_drift(doc_id)` MCP tool that returns a JSON-ish response containing `{ drifted: Bool, disk_mtime: ISO8601, stored_mtime: ISO8601, disk_hash_matches: Bool }`. The tool SHALL NOT error unless `doc_id` is missing. The `drifted` field SHALL equal `true` when either `disk_mtime != stored_mtime` OR `disk_hash_matches == false`.

#### Scenario: Untouched external file reports not drifted

- **WHEN** `check_disk_drift(doc_id: "d1")` is called without any external modification to `sourcePath` since `open_document`
- **THEN** response contains `drifted: false` and `disk_hash_matches: true`

#### Scenario: External modification triggers drifted flag

- **WHEN** the source file is modified by an external editor and then `check_disk_drift(doc_id: "d1")` is called
- **THEN** response contains `drifted: true` and either `disk_hash_matches: false` (hash changed) or the `disk_mtime` differs from `stored_mtime`

### Requirement: get_session_state returns complete SessionState snapshot

The `che-word-mcp` server SHALL provide a `get_session_state(doc_id)` MCP tool returning the full `SessionState` (source path, disk hash as hex string, disk mtime ISO8601, isDirty, trackChangesEnabled). This is a superset of `get_document_session_state` (preserved for backward compat) and is side-effect-free.

#### Scenario: get_session_state returns all fields

- **WHEN** `get_session_state(doc_id: "d1")` is called on an open document
- **THEN** response includes `source_path`, `disk_hash_hex`, `disk_mtime_iso8601`, `is_dirty`, `track_changes_enabled`
- **AND** no `isDirty` flip, no side effect, no hash re-computation
