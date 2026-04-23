## Context

**Current state**: Four independent weaknesses in the `che-word-mcp` save path combine into a single failure mode: 2026-04-23 incident of 12 parallel `insert_image_from_path` + `save_document` → MCP crash → target docx deleted. Source audit confirmed:

- `DocxWriter.write` at `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxWriter.swift:18-32` does `removeItem(at: url)` + non-atomic `Data.write(to:)`.
- `class WordMCPServer` at `mcp/che-word-mcp/Sources/CheWordMCP/Server.swift:9-22` holds 8 `var` dictionaries with no synchronization.
- Existing `autosave: true` flag (v3.0.0) writes every mutation to target path (not checkpointed).
- `save_document` overwrites target unconditionally (no `.bak`).

**Constraints**:

- `ooxml-swift` is a shared dep between `mcp/che-word-mcp` and `macdoc` CLI. Changes to `DocxWriter` affect both consumers.
- `class WordMCPServer` → `actor WordMCPServer` is a source-level refactor; MCP swift-sdk's request dispatcher must tolerate actor isolation (likely yes since handlers are already `async throws`, but must be verified in Phase 2).
- User-visible files in target directory (`.bak`, `.autosave.docx`) interact with Dropbox/iCloud sync; naming must be predictable so users can `.gitignore` or sync-exclude them.
- Breaking changes to existing MCP tools are undesirable; prefer additive API surface (new arg with default, new tool) over altered signatures.

**Stakeholders**: `che-word-mcp` end users (academic writers editing NTPU theses via Claude Code); downstream consumers of `ooxml-swift` (`macdoc` CLI, future Swift callers); maintainer (Che Cheng) + AI implementer (Claude).

## Goals / Non-Goals

**Goals**:

- After Phase 1: any crash during `save_document` leaves target file intact (either original bytes or fully-written new bytes, never partial or empty).
- After Phase 2: parallel MCP tool calls against the same `doc_id` cannot corrupt session state; compiler enforces synchronization.
- After Phase 3: successful `save_document` with `keep_bak: true` leaves `<target>.bak` with pre-save bytes; user can manually `mv <target>.bak <target>` to roll back.
- After Phase 4: MCP crash before explicit `save_document` does not lose more than N mutations' worth of work (N configurable per open_document call).
- Each phase is independently shippable + verifiable; regressions in later phases don't block earlier ones.

**Non-Goals**: see `proposal.md` Non-Goals section (WAL, time-based throttle, timestamped `.bak`, hidden directories, NSLock, auto-recover, atomic save in server layer, `.bak` in ooxml-swift layer, single combined release).

## Decisions

### Decision: Atomic save goes in ooxml-swift DocxWriter

**What**: `DocxWriter.write(_:to:)` writes to `<target>.tmp.<UUID>` first, calls `FileHandle.synchronize()` (fsync), then `FileManager.default.replaceItemAt(target, withItemAt: tempURL, ...)`. Pre-emptive `removeItem(at: url)` (current line 19-21) is removed. A `defer { try? FileManager.default.removeItem(at: tempURL) }` ensures no orphan temp files on throw paths.

**Why**: Atomic-rename is the industry-standard pattern for durable writes. POSIX `rename()` within the same filesystem is atomic at the kernel level; `replaceItemAt` uses it when possible and falls back to copy+delete across volumes. Pushing to ooxml-swift means `macdoc` CLI and any future Swift consumer also gets the fix.

**Alternatives considered**:
- `Data.write(to:url, options: .atomic)` — works but less explicit about fsync timing and orphan cleanup; `replaceItemAt` gives clearer semantics.
- Implementing atomic-rename in `che-word-mcp` `persistDocumentToDisk` — rejected: duplicates the logic per-consumer and leaves `DocxWriter` as a data-loss landmine for other callers.

### Decision: class → actor refactor for concurrency safety

**What**: `class WordMCPServer` becomes `actor WordMCPServer`. All 8 mutable dictionaries stay as stored properties; actor isolation handles synchronization. Audit every `await self.<method>()` path for reentrancy invariant preservation.

**Why**: Swift 6 concurrency idiomatic. Compiler enforces all cross-actor access via `await`. Eliminates the class of bug where a developer forgets to acquire a lock. MCP swift-sdk handlers are already `async throws`, so the signature change surface is small.

**Alternatives considered**:
- `NSLock` around dictionary access — rejected in Non-Goals. Manual locking misses paths as codebase grows.
- `DispatchQueue` serial queue — rejected. Less idiomatic in Swift 6; interoperates awkwardly with `async/await`.
- Sendable struct with copy-on-write — rejected. 8 dictionaries × COW == memory pressure + cache miss cost for every read.

### Decision: .bak preservation at che-word-mcp server layer, opt-in

**What**: `persistDocumentToDisk` in `Server.swift` renames `<target>` → `<target>.bak` before calling `DocxWriter.write(doc, to: target)`. Guarded by `keep_bak: Bool = false` arg on `save_document` MCP tool (additive, default opt-out). `.bak` overwrites any previous `.bak` (single-slot, no rotation).

**Why**: `.bak` is a UX escape hatch for the caller, not a file-format durability invariant. Placing it at the server layer keeps `ooxml-swift` unopinionated about file-system side effects so `macdoc` CLI users don't get unwanted `.bak` files. Default opt-out preserves backward compat with existing v3.5.2 callers; caller explicitly opts in per-save.

**Alternatives considered**:
- Placement at `ooxml-swift` `DocxWriter` level — rejected (forces all consumers to handle the flag).
- Default opt-in (`keep_bak: true`) — rejected: Dropbox/iCloud sync noise, surprise disk usage for callers who don't expect the extra file.
- Rotation (`<target>.bak.1` / `.bak.2` / ... / `.bak.N`) — deferred to follow-up issue; single-slot v1 is sufficient for the stated use case.
- Hidden directory (`.che-word-mcp/backups/`) — rejected: invisibility defeats the "user can see escape hatch exists" UX.

### Decision: Autosave throttle = per-N-mutations with explicit recover tool

**What**: `open_document(autosave_every: Int = 0)` adds a per-session mutation counter. When `counter % N == 0` (N > 0), writer dispatches a checkpoint write to `<target>.autosave.docx` using atomic-rename (Phase 1 infra). New tool `checkpoint(doc_id, path?)` for manual trigger. New tool `recover_from_autosave(doc_id)` explicitly merges `.autosave.docx` into current session. `open_document` detects existing `.autosave.docx` and returns `autosave_detected: true, autosave_path: "..."` in session state; caller decides whether to recover. Successful `save_document` cleans up `.autosave.docx`.

**Why**: Per-N-mutations throttle is the simplest model that captures the stated incident pattern (12 mutations → 1 save). Explicit recovery tool prevents silent state mutation when autosave is stale (e.g., Word.app saved newer content externally between sessions).

**Alternatives considered**:
- Time-based throttle (autosave every 30s) — deferred to follow-up. Requires `DispatchSourceTimer` + actor-isolated firing coordination.
- WAL journal — rejected in Non-Goals (over-engineered).
- Auto-recover on `open_document` — rejected (silent state mutation risks clobbering external edits).
- Timestamped `.autosave-<ts>.docx` with rotation — rejected (adds retention policy decision; single overwriteable file is sufficient for in-flight recovery).

### Decision: Ship as 4 sequential phases, each verifiable independently

**What**: Phase 1 → `ooxml-swift v0.13.2` + `che-word-mcp v3.5.3` (dep bump). Phase 2 → `che-word-mcp v3.5.4`. Phase 3 → `che-word-mcp v3.5.5`. Phase 4 → `che-word-mcp v3.6.0` (MINOR for new tools). Each phase runs its own idd-implement → idd-verify → idd-close cycle on the corresponding issue (#36 / #39 / #38 / #37 respectively).

**Why**: Phase 1 is P0 data safety; deferring it to wait for Phase 4's larger scope prolongs user exposure. Incremental ship also gives real-world soak time between phases, catching regressions early. Pattern validated on the recent `che-word-mcp-true-byte-preservation` SDD which shipped in 2 phases (ooxml-swift v0.13.0 → che-word-mcp v3.5.0).

**Alternatives considered**:
- Single `v3.6.0` release covering all 4 — rejected (delays Phase 1 data-safety fix).
- Four separate Spectra changes — rejected (duplicates context, loses coherent design narrative; phases share decisions like "atomic-rename infra is used by Phase 1 + Phase 3 + Phase 4").

## Risks / Trade-offs

- **[Actor reentrancy breaks invariants]** → Mitigation: Phase 2 implementation audits every `await self.<method>()` site; adds `ActorIsolationStressTests.swift` with 50-concurrent-call stress test under ThreadSanitizer.

- **[MCP swift-sdk dispatcher incompatible with actor]** → Mitigation: verify in Phase 2 kickoff before committing to refactor. If incompatible, fallback to `NSLock` wrapper (accepting the error-prone cost). Probability low: handlers are already `async throws`.

- **[replaceItemAt fails across volumes]** → Mitigation: Foundation's `replaceItemAt` internally detects and falls back to copy+delete. Acceptable degradation (slower but still safe).

- **[Phase 3 .bak race with user deleting .bak manually]** → Mitigation: `.bak` overwrite in `persistDocumentToDisk` is best-effort; if rename fails (target was already moved/deleted by user), log warning and proceed with atomic-write. User's manual action is not MCP's invariant to preserve.

- **[Phase 4 autosave file stale after external Word.app edit]** → Mitigation: `open_document` reports `autosave_detected` but does NOT auto-recover. Caller must explicitly `recover_from_autosave(doc_id)`. UI/caller can compare mtime(target) vs mtime(autosave) and decide.

- **[Phase 2 performance regression from actor hop]** → Mitigation: actor hop is microsecond-level vs MCP RPC roundtrip (millisecond-level); orders-of-magnitude buffer. If measured regression appears, profile and optimize specific hot paths.

- **[Disk space from .bak + .autosave.docx both enabled for large docx]** → Mitigation: documented in README. For large docx (>100MB), user should opt-out one of them per-call.

- **[Phase 4 recover_from_autosave merge semantics ambiguous]** → Mitigation: "merge" here means "replace current in-memory session state with autosave file contents". It is NOT a 3-way merge; latest session state wins over autosave. This is captured in the Phase 4 spec requirement with an `##### Example` block.

## Migration Plan

The 4 phases ship sequentially. Each phase's release ceremony is fully detailed in the corresponding tasks.md sections (`## 1. Phase 1` through `## 4. Phase 4`) — refer there for exact commands and version bumps. Summary:

- **Phase 1** ships `ooxml-swift v0.13.2` + `che-word-mcp v3.5.3` (dep bump only). Closes che-word-mcp#36.
- **Phase 2** ships `che-word-mcp v3.5.4` patch. No API change visible to callers. Closes che-word-mcp#39.
- **Phase 3** ships `che-word-mcp v3.5.5` patch with `keep_bak` arg added to `save_document`. Closes che-word-mcp#38.
- **Phase 4** ships `che-word-mcp v3.6.0` MINOR with `autosave_every` arg + new `checkpoint` + `recover_from_autosave` tools + `autosave_detected` session state field. Closes che-word-mcp#37. Spectra archive.

**Rollback**: each phase reverts independently by reverting its commit and tag. Phase 1 rollback restores `v0.13.1` behavior (non-atomic save); users with in-flight saves at rollback moment are unaffected (rollback only prevents future saves from using atomic path). Phases 2-4 have no external-state changes so rollback is just `git revert` + release patch version.

## Open Questions

- Should Phase 4's `autosave_detected` detection on `open_document` run unconditionally, or only when caller passes `check_autosave: true`? Default unconditional (cheap filesystem check) unless profile shows latency regression.
- Should `recover_from_autosave` require `discard_changes: true` if current session has unsaved mutations, matching `close_document` dirty-check pattern? Leaning yes for symmetry; resolve in Phase 4 spec.
- Should `.autosave.docx` and `.bak` share a config knob (e.g., `durability_level: "off" | "basic" | "full"`) or stay independent? Leaning independent for v1 (Phases 3 + 4 are independently opt-in); combine in a follow-up if callers want it.
