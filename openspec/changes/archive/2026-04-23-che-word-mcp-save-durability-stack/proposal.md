## Summary

Bundle 4 issues (PsychQuant/che-word-mcp #36 atomic save + #39 actor refactor + #38 .bak preservation + #37 autosave/checkpoint/recover) into a coherent 4-phase save durability + concurrency stack for `che-word-mcp` (and downstream `ooxml-swift`).

## Motivation

The 2026-04-23 incident (12 parallel `insert_image_from_path` + `save_document` → MCP crash → original docx deleted) exposed four interacting weaknesses in the save path:

1. **#36 (P0 bug)**: `DocxWriter.write` deletes target THEN does non-atomic `Data.write(to:)`. Any crash between those two steps leaves the user with an empty file. Confirmed via source audit at `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxWriter.swift:18-32`.

2. **#39 (P2 bug, fueling #36)**: `class WordMCPServer` has 8 unsynchronized `var` dictionaries (`openDocuments`, `documentDirtyState`, etc.). Concurrent mutations from parallel async tasks → Swift `Dictionary` data race → corrupted hash table → save-time crash. Confirmed via source audit at `mcp/che-word-mcp/Sources/CheWordMCP/Server.swift:9-22`.

3. **#37 (P1 enhancement)**: in-memory edits accumulate until explicit `save_document`. Crash before save = full session loss. Existing `autosave: true` flag (v3.0.0) is eager-save (every mutation full save), not throttled checkpoint to a separate file with recovery flow.

4. **#38 (P1 enhancement)**: `save_document` overwrites target with no rollback path. Silent OOXML damage from a save bug (e.g., the v3.4.0 header strip, the v3.5.0 rels regen) permanently destroys the original.

These four issues form one durability stack: write integrity (#36) → concurrency safety (#39) → post-write rollback (#38) → in-memory checkpointing (#37). Bundling them into one Spectra change keeps the design coherent; shipping as 4 separate phases keeps each verifiable independently.

## Proposed Solution

Four sequential phases, each ships as its own release with idd-implement → idd-verify → idd-close cycle:

### Phase 1: ooxml-swift atomic save (closes #36)

`DocxWriter.write(_:to:)` adopts atomic-rename pattern:
- Write to `<target>.tmp.<UUID>` temp file
- `FileHandle.synchronize()` (fsync)
- `FileManager.default.replaceItemAt(target, withItemAt: tempURL, ...)` (POSIX atomic rename on same volume)
- `defer { try? FileManager.default.removeItem(at: tempURL) }` cleanup

Removes pre-emptive `removeItem(at: url)`. Crash anywhere in the chain leaves target untouched.

**Ship**: `ooxml-swift v0.13.2` + `che-word-mcp v3.5.3` (dep bump).

### Phase 2: actor refactor (closes #39)

`class WordMCPServer` → `actor WordMCPServer`. All 8 mutable dictionaries become actor-isolated. Compiler enforces every external access via `await`. Audit reentrancy (any path that does `await self.<method>()` from within a mutation needs invariant check).

**Ship**: `che-word-mcp v3.5.4` (no `ooxml-swift` change).

### Phase 3: .bak preservation (closes #38)

Server.swift `persistDocumentToDisk` rename target → `<target>.bak` BEFORE delegating to `DocxWriter.write` (which uses Phase 1 atomic-rename). Default opt-out (`keep_bak: false`); `save_document` MCP tool gains `keep_bak: bool` arg.

`.bak` lives at `che-word-mcp` server layer NOT `ooxml-swift` (so `macdoc` CLI consumers don't get unwanted `.bak` files).

**Ship**: `che-word-mcp v3.5.5` (no `ooxml-swift` change).

### Phase 4: autosave + checkpoint + recover_from_autosave (closes #37)

- `open_document(autosave_every: Int = 0)` — counter increments per mutation; when `counter % N == 0`, dispatch checkpoint (default `0 = disabled`)
- New tool `checkpoint(doc_id, path?)` — manual checkpoint to autosave file
- New tool `recover_from_autosave(doc_id)` — explicitly merge autosave file into current session
- Autosave file = single fixed name `<target>.autosave.docx` (overwritten each checkpoint, NOT timestamped)
- `open_document` returns `autosave_detected: true, autosave_path: "..."` warning when detecting an existing autosave file (NOT auto-recover — explicit tool required)
- Successful `save_document` cleans up `.autosave.docx`

**Ship**: `che-word-mcp v3.6.0` (MINOR bump for new tools).

## Non-Goals

- **WAL / journal-based recovery (Option C from #37 diagnosis)**: deferred. Per-mutation log replay is significantly more complex than per-N-mutations checkpoint and the diagnosis judged the value delta not worth the cost.
- **Time-based autosave throttle**: deferred. Per-N-mutations is simpler and sufficient for the stated incident pattern (12 mutations → 1 save).
- **`.bak` rotation / timestamped backups**: deferred. Single `<target>.bak` overwritten each save is the v1 default; rotation can be a follow-up issue.
- **Hidden directory placement (`.che-word-mcp/`)** for either `.autosave.docx` or `.bak`: deferred. User-visible files in same directory are the v1 default.
- **`DispatchQueue` or `NSLock` concurrency primitives** for #39 fix: rejected. `actor` is the Swift 6 idiomatic choice; compiler-checked safety beats manual locking.
- **Auto-recover on `open_document`**: rejected. Silent state mutation is dangerous when target was edited externally between MCP sessions (e.g., Word.app saved newer content). Explicit `recover_from_autosave` tool required.
- **Atomic save in `che-word-mcp` server layer**: rejected. Push to `ooxml-swift` `DocxWriter` so all consumers (macdoc CLI, future Swift callers) benefit — not duplicated per-consumer.
- **`.bak` in `ooxml-swift` `DocxWriter`**: rejected. Escape-hatch policy is consumer concern (server layer); macdoc CLI users don't need `.bak` litter.
- **Single combined release**: rejected. Phase 1 (#36) is P0 data safety; deferring it to wait for Phase 4 (#37 autosave) would prolong user exposure unnecessarily.

## Alternatives Considered

- **One Spectra change vs four**: bundled chosen. Four separate changes would duplicate background context (the durability stack rationale) across four proposals; design decisions interact (e.g., Phase 3 .bak depends on Phase 1 atomic-rename infra).
- **`class WordMCPServer` + `NSLock`**: rejected per Non-Goals. Manual lock is error-prone and Swift compiler can't verify completeness.
- **Eager-save (current v3.0.0 `autosave: true` behavior) repurposed for #37**: rejected. Eager-save writes to target path itself, defeating the recovery-without-clobbering invariant.
- **Backups via git auto-commit hooks**: rejected. File-system layer protection is orthogonal to version control; assumes user has git initialized in target directory.

## Impact

- Affected specs:
  - **Modified**: `che-word-mcp-session-state-api` — adds autosave throttle, checkpoint, recover_from_autosave tool surface; documents actor isolation; documents .bak interaction with save flow
  - **New**: `ooxml-atomic-save` — atomic-rename contract for `DocxWriter.write` and any other ooxml-swift writer entry points

- Affected code:
  - Modified:
    - `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxWriter.swift` (Phase 1: atomic-rename refactor of `write(_:to:)`)
    - `mcp/che-word-mcp/Sources/CheWordMCP/Server.swift` (Phase 2: class → actor; Phase 3: .bak rename in `persistDocumentToDisk`; Phase 4: autosave throttle counter, new tool registrations, recovery detection)
    - `mcp/che-word-mcp/Package.swift` (Phase 1: bump ooxml-swift dep to v0.13.2)
    - `mcp/che-word-mcp/CHANGELOG.md` (per-phase entry: v3.5.3 / v3.5.4 / v3.5.5 / v3.6.0)
    - `mcp/che-word-mcp/README.md` + `README_zh-TW.md` (Phase 4: document new autosave/checkpoint/recover tools)
    - `mcp/che-word-mcp/mcpb/manifest.json` (per-phase version bump)
    - `packages/ooxml-swift/CHANGELOG.md` (Phase 1: v0.13.2 entry)
  - New:
    - `packages/ooxml-swift/Tests/OOXMLSwiftTests/AtomicSaveTests.swift` (Phase 1: crash-injection regression tests)
    - `mcp/che-word-mcp/Tests/CheWordMCPTests/ActorIsolationStressTests.swift` (Phase 2: 50-concurrent-call stress test under TSan)
    - `mcp/che-word-mcp/Tests/CheWordMCPTests/BakPreservationTests.swift` (Phase 3: .bak round-trip tests)
    - `mcp/che-word-mcp/Tests/CheWordMCPTests/AutosaveCheckpointTests.swift` (Phase 4: throttle counter, checkpoint round-trip, recover_from_autosave flow)
  - Removed: (none)
