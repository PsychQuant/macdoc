# Design — word-mcp-session-lifecycle

## Context

che-word-mcp's current session model (`Server.swift`) holds `openDocuments: [String: WordDocument]` — a bare value dictionary. No metadata about where the doc came from, whether it's been saved, whether disk has drifted externally. Three issues (#12 / #13 / #15) each patch a symptom; this change adds the missing session-metadata layer once and exposes it via four new MCP tools + two modified tool signatures.

Relevant existing code:

| Location | Current state |
|----------|---------------|
| `Server.swift` open/close/save handlers | `openDocuments[docId] = doc` / `openDocuments.removeValue(forKey: docId)`. No metadata. |
| `Server.swift` get_document_session_state tool | Reports only dirty-tracking state that individual tools manually maintain — not disk-relative. |
| `Server.swift` 148 tool handlers | ~40 mutate `openDocuments[docId]` via `var doc = openDocuments[docId]!` → edits → `try await storeDocument(doc, for: docId)`. All must be updated to go through the new `SessionState` wrapper. |
| `Server.swift` open_document handler | Track changes enabled by default via `enable_track_changes` side-effect call inside `open_document`. |
| `Server.swift` close_document handler | Implicitly saves if dirty, unconditionally removes from `openDocuments`. No discard path. |
| macOS platform | CryptoKit's `SHA256` available on macOS 13+, che-word-mcp `Package.swift` already targets `.macOS(.v13)`. |

Constraints:

- che-word-mcp already shipped at v2.3.0; this change will land as **v3.0.0** (major bump) because it changes `open_document` default behavior (breaking).
- No new external deps. SHA256 via CryptoKit.
- All ~40 `openDocuments[docId]` call sites in Server.swift must migrate; the refactor is mechanical (replace `doc` access pattern with `state.document`) but large.
- Must not regress existing `finalize_document`, `save_document`, `get_document_session_state` flows — those remain but now read through SessionState.

## Goals and Non-Goals

**Goals:**

1. Eliminate "silent divergence" between in-memory doc and disk — drift detection surfaces in tool responses + via explicit `check_disk_drift` tool.
2. Make close path explicit: either save, discard, or finalize — never implicitly lose data.
3. Opt-in track changes — sensible default for majority of workflows (clean edits), opt-in for review workflows.
4. Single SessionState struct consolidates metadata that was previously scattered (or missing): source path, disk hash, disk mtime, dirty flag, track-changes flag.
5. Preserve all existing tool signatures and behaviors except the two explicitly documented BREAKING changes.

**Non-Goals (explicitly out of scope):**

1. **Multi-session concurrent editing.** If two Claude sessions open the same docx, last-write-wins. No locking, no conflict resolution. Out of scope — users typically have one session per doc.
2. **Undo / redo beyond revert_to_disk.** We don't maintain an edit log; `revert_to_disk` is the only rollback primitive. Fine-grained undo is a separate future capability.
3. **File watching / auto-reload on disk change.** Drift detection is lazy (only on tool call). No FSEvents subscription.
4. **Partial reload (reload only certain paragraphs).** `reload_from_disk` is all-or-nothing.
5. **Cross-process session persistence.** Restart kills in-memory state. Caller responsible for save-on-shutdown via `save_document` or `finalize_document`.
6. **Diff-display of drift.** `check_disk_drift` returns booleans + timestamps + hash match; does NOT diff paragraph-by-paragraph. A follow-up tool could layer on `compare_documents`.
7. **Track-changes migration helper.** Callers upgrading from 2.x to 3.x who relied on default-on track changes must explicitly pass `track_changes: true` to `open_document`. No automatic detection + warning.

## Decisions

### Extend existing parallel-map session state (no single-struct refactor)

**Implementation reality discovered during apply phase** (2026-04-22): Server.swift already maintains 5 parallel dictionaries for session state: `openDocuments` (`[String: WordDocument]`), `documentOriginalPaths`, `documentDirtyState`, `documentAutosave`, `documentTrackChangesEnforced`. The single write choke-point is `persistDocumentToDisk(_:docId:path:)` at Server.swift:154 and the single in-memory update choke-point is `storeDocument(_:for:markDirty:)` at Server.swift:163. ~235 grep matches of `openDocuments[` are mostly read accesses that don't need to change.

Decision: **Do not refactor to a single SessionState struct**. Add 2 more parallel dictionaries (`documentDiskHash: [String: Data]`, `documentDiskMtime: [String: Date]`) + `SessionStateView` read-only struct for `get_session_state` response serialization. Inject hash/mtime updates at the existing 2 choke-points (`persistDocumentToDisk` on save, `open_document` handler on read).

**Rationale**: The original "single source of truth" argument is moot because `persistDocumentToDisk` + `storeDocument` already serve that role — they're the only places state mutation happens. Adding 2 more maps keyed by `docId` follows the established pattern. Refactoring 235 accesses to `openDocuments[docId]!.document` is mechanical churn with regression risk. Extending the existing model is the smaller, safer delta that still satisfies every spec requirement (the spec describes behavior, not implementation data layout).

**Consequence**: The spec `SessionState wraps open documents with metadata` requirement can be satisfied by a per-docId accessor helper `sessionState(for docId: String) -> SessionStateView?` that reads across the 7 parallel dicts. The struct exists for response serialization and tests, not internal storage.

### Disk drift detection is lazy, not watched

`checkDiskDrift(currentPath:)` on SessionState computes current file hash and compares to stored hash. Called on demand:

- By `check_disk_drift` tool (explicit)
- By `close_document` if not discarding (warn user in response if drift detected)
- By every tool that mutates the doc (optional — Phase 2 decision; Phase 1 only surface in explicit check + close)

**Rationale**: Alternative is FSEvents subscription to watch source path. Rejected — (1) adds complexity (dispatch queue, cancellation), (2) inconsistent with MCP's stateless tool-call model, (3) 99% of workflows don't have external editors racing the MCP server. Lazy check on save paths covers the important case (don't overwrite external edits).

### Track-changes default flips off (BREAKING)

`open_document` adds `track_changes: Bool = false`. Callers who previously relied on implicit default-on behavior must explicitly pass `track_changes: true`.

**Rationale**: Track changes is a review workflow artifact. Majority of MCP callers (scripted edits, R→Word, batch replace, thesis caption renumber) want clean edits with no tracking. Historical default was artifact of copying `enable_track_changes` into `open_document` without thinking about the common case. Breaking is deliberate and documented.

**Alternative considered**: Keep default on, add param to disable. Rejected — perpetuates the wrong default. CHANGELOG 3.0.0 clearly calls out the flip, callers adjust once.

### close_document without discard_changes refuses on dirty docs

`close_document` adds `discard_changes: Bool = false`. If `isDirty == true` and `discard_changes == false`, return `E_DIRTY_DOC` with message pointing caller to three options: `save_document`, `close_document(discard_changes: true)`, or `finalize_document`.

**Rationale**: Previous behavior was "close_document unconditionally tries save-then-release, partial failures silent". New behavior is explicit — caller must choose. Gives data-loss protection (accidentally closing with dirty state no longer silently saves or silently discards).

**Alternative considered**: Default close_document to save-then-close (preserve old). Rejected — keeps the silent-save-on-close footgun; #12 specifically asks for an escape hatch from it.

### revert_to_disk vs reload_from_disk

Two tools, not one, because they serve different intents:

- `revert_to_disk(doc_id)` — "Forget everything I did this session, re-read source file." No force flag needed; the intent is clearly destructive. Dirty state doesn't matter.
- `reload_from_disk(doc_id, force: Bool = false)` — "Pick up external edits, but not at the cost of my uncommitted work." If dirty, default behavior is error; `force: true` overrides.

**Rationale**: Conflating into one tool with a flag hides the intent. "Revert" is destructive-by-design; "reload" is cooperative. Two names make the call site readable.

**Alternative considered**: Single `reload_from_disk(doc_id, discard_unsaved: Bool)`. Rejected — ambiguous at call site, grep-ability worse.

### check_disk_drift returns informational status, not error

`check_disk_drift(doc_id) → { drifted, disk_mtime, stored_mtime, disk_hash_matches }`. Never errors (unless doc_id missing). Pure query.

**Rationale**: It's a checking primitive. Callers decide what to do. Making it error on drift would force callers to catch-and-branch, worse than just returning the status.

### Hashing algorithm: SHA256 via CryptoKit

`SessionState.diskHash: Data?` = SHA256 of file bytes. Computed on `open_document` (after successful read) and on `save_document` (after successful write). Cheap enough (~10ms for 2MB docx on M1) to not warrant optimization.

**Rationale**: CryptoKit is built-in, no new dep. SHA256 collision resistance is overkill for drift detection (a CRC32 would do), but the standard-library API is simpler and collision is not a real concern.

**Alternative considered**: mtime-only comparison. Rejected — mtime can be fragile across sync tools (Dropbox, rsync), hash-based is authoritative.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| ~40 call-site migration introduces regressions | Mechanical refactor following established pattern (`state.document`); full existing test suite must pass before release; smoke-test common workflows (open → edit → save) against thesis fixture |
| SHA256 on large docs (>50MB) adds latency | Document behavior in CHANGELOG; fallback to mtime-only for docs >100MB is a Phase 2 option if users report issues |
| `track_changes: false` default breaks review workflows | CHANGELOG 3.0.0 calls out the flip with migration line; `enable_track_changes` still exists for session-level toggle |
| `E_DIRTY_DOC` error from `close_document` breaks existing client code that relied on silent save | Intentional. Error message enumerates 3 recovery paths. Clients that wanted silent-save behavior pass `finalize_document` |
| Drift detection surfacing hint in every tool response adds noise | Scope: Phase 1 surfaces only in `close_document` + explicit `check_disk_drift`. Never in mid-edit tool responses. |
| Missing migration test coverage for `openDocuments` refactor | Task includes explicit migration test: open a doc, walk every tool that mutates, verify dirty bit flips, verify save resets hash |
| `reload_from_disk` on dirty doc without force could surprise callers who assumed merge | Documented error message explicitly says "your in-memory changes would be lost; pass force: true to discard them or save_document first" |

## Migration Plan

1. Land `SessionState.swift` new file with struct + helpers. Unit-test the helpers (hash + drift compute) in isolation.
2. Refactor `Server.swift` `openDocuments` type + all ~40 call sites to use SessionState wrapper. No new tool signatures yet — just internal refactor. Run full test suite, smoke-test against fixture docx. Commit as intermediate checkpoint.
3. Add 4 new tool schemas (`revert_to_disk`, `reload_from_disk`, `check_disk_drift`, `get_session_state`) + handlers.
4. Modify `open_document` (add `track_changes: Bool = false`) and `close_document` (add `discard_changes: Bool = false` + `E_DIRTY_DOC` path) schemas + handlers.
5. Update `CHANGELOG.md` with 3.0.0 entry: BREAKING section listing the two behavior changes, Added section listing 4 new tools + SessionState.
6. Version bump: `mcpb/manifest.json` 2.3.0 → 3.0.0. Build universal binary. Tag `v3.0.0`.
7. GitHub release + upload CheWordMCP binary + che-word-mcp.mcpb.
8. Plugin marketplace bump 2.3.0 → 3.0.0. Push marketplace + `claude plugin update`.

**Rollback:** Users pin to che-word-mcp `v2.x` via plugin marketplace version. Wrapper's version-aware auto-download (shipped in plugin 2.0.1) honors pinned versions.

## Open Questions

1. Should `reload_from_disk` preserve `doc_id`? Current design: yes, same `doc_id` continues to work post-reload. Alternative: return new `doc_id`. Current answer keeps call sites stable — agreed.
2. Does `get_session_state` deprecate `get_document_session_state`? Current plan: no, both coexist, `get_document_session_state` remains as shallow summary, `get_session_state` is superset. Reconsider at 3.1 if callers consolidate.
3. Track-changes state after `reload_from_disk` — reset to false or preserve caller's opt-in? Current answer: preserve session's trackChangesEnabled (it's a session-level toggle, not a doc-level state).
4. On drift detection during `save_document`, warn-and-proceed or error-and-require-force? Current answer: warn in response, proceed (aligns with "last write wins" from Non-Goal #1). Callers who want safety check use `check_disk_drift` pre-save.

## References

- PsychQuant/che-word-mcp issues #12 / #13 / #15 diagnosis comments (2026-04-22 batch).
- CryptoKit `SHA256` documentation (`https://developer.apple.com/documentation/cryptokit/sha256`).
- Existing Spectra change `word-mcp-insertion-primitives` v2.0.0 — precedent for major-version MCP schema changes.
- che-word-mcp CHANGELOG 2.3.0 — prior release establishing the text-anchor compound tool pattern.
