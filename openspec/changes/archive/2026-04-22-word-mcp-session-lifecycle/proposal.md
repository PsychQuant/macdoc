## Why

che-word-mcp session model (open_document → edits → save_document → close_document) has three state-visibility gaps surfaced by GitHub issues #12 / #13 / #15:

- **#12 `close_document` 缺 discard_changes flag + `revert_to_disk` / `reopen` 未提供**. Once a doc is dirty, the only escape is `close_document` (loses the state) followed by fresh `open_document` (2-step dance). No inline "throw away my changes" primitive.
- **#13 `open_document` 預設 track changes = on, 無 param 關閉**. Track changes is opinionated default; workflows that want clean edits (R→Word export, batch replace) must disable track changes by separate tool call. Should be opt-in.
- **#15 Sync / revert tools — 無機制將 in-memory state 與 disk 重新對齊**. When external editor modifies the .docx between MCP calls, in-memory state becomes silently divergent. No `reload_from_disk` / drift-detection tool. Users have no signal until save overwrites their external edits.

All three share one underlying gap: **che-word-mcp has no explicit session-state metadata layer**. Currently `openDocuments[docId]` holds only a `WordDocument` value — no disk mtime, no content hash, no dirty bit, no knowledge of whether disk has drifted. Adding piecemeal tools for each symptom would grow the API surface without addressing the root cause.

## What Changes

### Session metadata layer (new abstraction)

- **`SessionState` struct** wrapping each open document: `{ document: WordDocument, sourcePath: String, diskHash: Data?, diskMtime: Date?, isDirty: Bool, trackChangesEnabled: Bool }`. Stored as `openDocuments[docId]: SessionState` (replacing bare `WordDocument` value). Every existing handler that mutates the doc flips `isDirty = true`; every save refreshes `diskHash` + `diskMtime` and resets `isDirty = false`.
- **Disk drift detection**: on any tool call that reads `openDocuments[docId]`, lazily compare `diskHash` / `diskMtime` against the file on disk. Surface a `disk_drift: { current_mtime, stored_mtime }` hint in tool responses when drift detected (not an error — informational, handler still proceeds against in-memory state).

### MCP tool API additions

- **`revert_to_disk(doc_id)`** — discard in-memory changes, re-read from `sourcePath`, reset `isDirty = false`. Closes #15 revert path.
- **`reload_from_disk(doc_id, force: Bool = false)`** — if doc has no uncommitted changes, re-read from disk to pick up external edits; if dirty, require `force: true` to override. Closes #15 sync path.
- **`check_disk_drift(doc_id)`** — explicit check returning `{ drifted: Bool, disk_mtime, stored_mtime, disk_hash_matches: Bool }`. Use as pre-save guard.
- **`get_session_state(doc_id)`** — return full `SessionState` snapshot without side effects. Superset of existing `get_document_session_state`.

### MCP tool API modifications

- **BREAKING `close_document`** — new optional `discard_changes: Bool = false`. When `true`, skips the implicit save and releases in-memory state without touching disk. When `false` (default) and doc is dirty, errors with `E_DIRTY_DOC` telling caller to `save_document`, pass `discard_changes: true`, or use `finalize_document` for save+close. Existing "autosave-on-close" behavior documented but explicit now. Closes #12.
- **BREAKING `open_document`** — new optional `track_changes: Bool = false`. Track changes now **off by default**; callers who want tracked edits must opt-in. Existing `enable_track_changes` / `disable_track_changes` tools preserved for mid-session toggles. Closes #13.

### Out of scope (Non-Goals)

(Captured in `design.md`.)

## Capabilities

### New Capabilities

- `che-word-mcp-session-state-api`: Layer 4 MCP tools and session-metadata layer covering (a) disk drift detection + reconciliation (`revert_to_disk`, `reload_from_disk`, `check_disk_drift`), (b) explicit dirty-state semantics on `close_document` (`discard_changes` flag + `E_DIRTY_DOC` error path), (c) opt-in track changes on `open_document`, (d) augmented `SessionState` exposed via `get_session_state`.

### Modified Capabilities

*(none — this change introduces a single new capability. No existing spec is modified.)*

## Impact

- **Affected specs**: 1 new (`che-word-mcp-session-state-api`). No existing specs modified.
- **Affected code**:
  - `mcp/che-word-mcp/Sources/CheWordMCP/Server.swift` — replace `openDocuments: [String: WordDocument]` with `openDocuments: [String: SessionState]`. Every handler that reads/writes `openDocuments[docId]` must be updated (~40 call sites). Add 4 new tool schemas + handlers (`revert_to_disk`, `reload_from_disk`, `check_disk_drift`, `get_session_state`). Modify `open_document` + `close_document` schemas + handlers for new params.
  - `mcp/che-word-mcp/Sources/CheWordMCP/SessionState.swift` — **new file**. Struct + helpers (`computeDiskHash(path:)` via SHA256 of file bytes, `checkDiskDrift(currentPath:)` returning a `DriftStatus` enum).
- **Tests**: `mcp/che-word-mcp/Tests/CheWordMCPTests/SessionStateTests.swift` — new file covering drift detection, dirty flag, revert/reload paths with fixture docx.
- **Dependencies**: No new external deps (`SHA256` via `CryptoKit`, already available on macOS 13+).
- **APIs**: 2 BREAKING MCP tool signature changes (`open_document` default flips, `close_document` gains `discard_changes` + `E_DIRTY_DOC`). 4 new tools added. Documented in CHANGELOG as 3.0.0 (major bump — changes default behavior of top-level `open_document`).
- **Issues closed on landing**: #12 (fully — discard_changes + revert_to_disk + reload_from_disk cover the close/reopen gaps), #13 (fully — track_changes opt-in default), #15 (fully — revert/reload/drift detection).
