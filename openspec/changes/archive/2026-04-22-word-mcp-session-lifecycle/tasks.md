# Tasks — word-mcp-session-lifecycle

## 1. SessionState foundation (new file + existing infrastructure extension)

- [x] 1.1 Create `mcp/che-word-mcp/Sources/CheWordMCP/SessionState.swift` containing: (a) `struct SessionStateView` for response serialization with fields `sourcePath: String`, `diskHash: Data?`, `diskMtime: Date?`, `isDirty: Bool`, `trackChangesEnabled: Bool`; (b) `static func computeSHA256(path: String) throws -> Data` — applies the Hashing algorithm: SHA256 via CryptoKit decision; (c) `static func readMtime(path: String) throws -> Date` (FileManager `.modificationDate`); (d) `enum DriftStatus { case inSync, driftedMtime, driftedHash }`; (e) `static func checkDriftStatus(path: String, knownHash: Data?, knownMtime: Date?) -> DriftStatus` — applies the Disk drift detection is lazy, not watched decision. Covers the foundation piece of the Session state tracks source path, disk hash, mtime, dirty bit, and track-changes flag per open document requirement.

- [x] 1.2 Add 2 new parallel maps in `Server.swift` alongside existing session state maps: `private var documentDiskHash: [String: Data] = [:]` + `private var documentDiskMtime: [String: Date] = [:]`. Ensure `removeSession(docId:)` (Server.swift:122) also `removeValue(forKey:)` for these two — applies the Extend existing parallel-map session state (no single-struct refactor) decision

- [x] 1.3 Write `mcp/che-word-mcp/Tests/CheWordMCPTests/SessionStateTests.swift` covering: (a) `computeSHA256` deterministic across calls on same file, (b) `readMtime` returns file's actual modification timestamp, (c) `checkDriftStatus` returns `.inSync` for untouched file, (d) `checkDriftStatus` returns `.driftedHash` after byte modification, (e) `checkDriftStatus` returns `.driftedMtime` if mtime changes but hash matches (rare; touch without content change). TDD: 8 tests all green.

## 2. Existing choke-point integration (no 40-site refactor)

- [x] 2.1 Modify `open_document` handler to call `SessionState.computeSHA256(path:)` + `SessionState.readMtime(path:)` on successful read, store in the new `documentDiskHash` / `documentDiskMtime` maps — applies the Extend existing parallel-map session state (no single-struct refactor) decision. Only 1 code site touched (the open handler).

- [x] 2.2 Modify `persistDocumentToDisk(_:docId:path:)` at Server.swift:159 to refresh `documentDiskHash[docId]` + `documentDiskMtime[docId]` after successful `DocxWriter.write`. Only 1 code site touched. This propagates to all callers automatically (`save_document`, `finalize_document`, autosave path in `storeDocument`).

- [x] 2.3 Add helper `sessionStateView(for docId: String) -> SessionStateView?` returning a snapshot combining `openDocuments` / `documentOriginalPaths` / `documentDirtyState` / `documentTrackChangesEnforced` / new hash/mtime maps. Returns `nil` if `doc_id` unknown.

- [x] 2.4 Confirm full `swift build` passes with zero compile errors.

- [x] 2.5 Run `swift test` on the existing test suite — 38/38 pass. One pre-existing test (`testGetDocumentSessionStateReportsDirtyAndFinalizeReadiness`) asserted old track-changes-default-on behavior and was updated to explicitly pass `track_changes: true` per the v3.0.0 BREAKING change.

## 3. New MCP tools — revert / reload / drift / session_state

- [x] 3.1 Add Tool schema `revert_to_disk` in `Server.swift`. args `{ doc_id }`; required `[doc_id]`. Description: "discards uncommitted edits, re-reads sourcePath, no force flag needed (revert is destructive-by-design)". Applies the revert_to_disk vs reload_from_disk decision. Covers the revert_to_disk drops in-memory changes requirement.

- [x] 3.2 Add Tool schema `reload_from_disk`. args `{ doc_id, force: Bool = false }`; required `[doc_id]`. Description documents dirty-doc error path. Covers the reload_from_disk requires force on dirty documents requirement.

- [x] 3.3 Add Tool schema `check_disk_drift`. args `{ doc_id }`; required `[doc_id]`. Description notes response shape `{ drifted, disk_mtime, stored_mtime, disk_hash_matches }`. Applies the check_disk_drift returns informational status, not error decision. Covers the check_disk_drift reports current drift status requirement.

- [x] 3.4 Add Tool schema `get_session_state`. args `{ doc_id }`; required `[doc_id]`. Description documents it's superset of existing `get_document_session_state`. Covers the get_session_state returns complete SessionState snapshot requirement.

- [x] 3.5 Wire 4 dispatch cases: `case "revert_to_disk"` / `"reload_from_disk"` / `"check_disk_drift"` / `"get_session_state"` in the main dispatch switch.

- [x] 3.6 Implement `revertToDisk(args:)` handler: re-read `DocxReader.read(from: documentOriginalPaths[docId]!)`, replace `openDocuments[docId]`, refresh hash + mtime, set `documentDirtyState[docId] = false`. Covers the revert_to_disk drops in-memory changes scenarios.

- [x] 3.7 Implement `reloadFromDisk(args:)` handler: if `documentDirtyState[docId] == true && !force` return error containing word `force` and instructing `save_document`; else same side effects as `revertToDisk`.

- [x] 3.8 Implement `checkDiskDrift(args:)` handler: call `SessionState.computeSHA256` + `SessionState.readMtime` on current `documentOriginalPaths[docId]`, compare to stored hash/mtime, return JSON-style response `{ drifted, disk_mtime, stored_mtime, disk_hash_matches }`. Applies the check_disk_drift returns informational status, not error decision — never throws unless doc_id missing.

- [x] 3.9 Implement `getSessionState(args:)` handler: call `sessionStateView(for:)` helper (from 2.3), serialize to response (hex-encode `diskHash`, ISO8601-encode `diskMtime`).

## 4. Tool schema + handler modifications — open_document + close_document

- [x] 4.1 `open_document` schema: add `track_changes: Bool` property (description: "default false; pass true to record edits as tracked revisions"); required list unchanged. Applies the Track-changes default flips off (BREAKING) decision. Covers the open_document defaults track_changes to false requirement.

- [x] 4.2 `open_document` handler: read `track_changes` arg (default **false**, previously implicit true). Set `documentTrackChangesEnforced[docId] = trackChanges` and only call the existing `enable_track_changes` internal path when true.

- [x] 4.3 `close_document` schema: add `discard_changes: Bool` property (description: "default false; pass true to release without saving"); required list unchanged. Applies the close_document without discard_changes refuses on dirty docs decision. Covers the close_document rejects dirty documents without discard_changes requirement.

- [x] 4.4 `close_document` handler: if `isDirty(docId:) == true && !discardChanges` return error containing the literal `E_DIRTY_DOC` and the three recovery paths (`save_document` / `discard_changes: true` / `finalize_document`); else proceed with existing cleanup path (`cleanupDocumentState(docId:)`).

## 5. Integration tests

- [x] 5.1 Add tests in `SessionStateTests.swift`: (a) `open_document` sets `is_dirty == false` via `get_session_state`, (b) `insert_paragraph` flips `is_dirty`, (c) `save_document` resets `is_dirty` + refreshes hash, (d) `revert_to_disk` drops edits + resets dirty, (e) `close_document` on dirty without flag returns `E_DIRTY_DOC`, (f) `close_document` with `discard_changes: true` succeeds on dirty, (g) `check_disk_drift` reports no drift on untouched file, (h) `check_disk_drift` reports drift after external edit (simulate by writing to file path between calls).

- [x] 5.2 Full suite green: `swift test`.

## 6. CHANGELOG + release v3.0.0

- [x] 6.1 Update `mcp/che-word-mcp/CHANGELOG.md` with `## [3.0.0]` entry: **BREAKING** section covering `open_document` track_changes default flip + `close_document` dirty-doc `E_DIRTY_DOC` error; **Added** section listing 4 new tools (`revert_to_disk`, `reload_from_disk`, `check_disk_drift`, `get_session_state`) + `SessionState` module. Applies the Breaking changes are acknowledged and documented in CHANGELOG decision context.

- [x] 6.2 Bump `mcp/che-word-mcp/mcpb/manifest.json` version to `3.0.0` + updated description mentioning session state primitives.

- [x] 6.3 Universal build: `swift build -c release --arch arm64` + `swift build -c release --arch x86_64` + `lipo -create` + `xattr -cr` + `codesign --force --sign -` per che-word-mcp's v2.x release convention.

- [x] 6.4 Rebuild `.mcpb` package: `rm -f mcpb/*.mcpb && cd mcpb && zip -r che-word-mcp.mcpb . -x ".*" -x "*.mcpb"`.

- [x] 6.5 Git commit all touched files, push `main`, tag `v3.0.0`, push tag.

- [x] 6.6 `gh release create v3.0.0` with CHANGELOG excerpt + upload `mcpb/server/CheWordMCP` + `mcpb/che-word-mcp.mcpb`.

## 7. Plugin marketplace sync + issue closure

- [x] 7.1 Bump `plugins/che-word-mcp/.claude-plugin/plugin.json` + root `.claude-plugin/marketplace.json` `che-word-mcp` entry to `3.0.0`, commit, push on the plugin marketplace repo.

- [x] 7.2 `claude plugin marketplace update psychquant-claude-plugins` + `claude plugin update che-word-mcp@psychquant-claude-plugins` — per `common-release-flow.md` post-release mandatory chain.

- [x] 7.3 Close `PsychQuant/che-word-mcp#12` with comment referencing v3.0.0 + `discard_changes` + `revert_to_disk`.

- [x] 7.4 Close `PsychQuant/che-word-mcp#13` with comment referencing v3.0.0 + `track_changes: false` default.

- [x] 7.5 Close `PsychQuant/che-word-mcp#15` with comment referencing v3.0.0 + `reload_from_disk` + `check_disk_drift`.
