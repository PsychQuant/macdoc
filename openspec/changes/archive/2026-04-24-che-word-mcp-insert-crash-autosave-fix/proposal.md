## Summary

Fix two coupled v3.6.0 production blockers ([che-word-mcp#40](https://github.com/PsychQuant/che-word-mcp/issues/40) autosave-not-firing + [che-word-mcp#41](https://github.com/PsychQuant/che-word-mcp/issues/41) sequential 3rd `insert_image_from_path` crash) and harden the OOXML pipeline against future regressions by enforcing a "Word ops fully serialized" policy.

## Motivation

The 2026-04-23 v3.6.0 release closed `che-word-mcp-save-durability-stack` (Phases 1–4 covering #36/#37/#38/#39). Within hours of release, two regressions were filed:

- **#41**: Sequential (NOT parallel) `insert_image_from_path` × 3 against an NTPU thesis fixture crashes the MCP process on the 3rd call. The v3.5.4 actor refactor (Phase 2) was claimed to close #39 by serializing parallel mutations — sequential repro refutes "parallel race" as the root cause and the actual crash trigger remains unidentified.
- **#40**: With `autosave_every: 3`, the user's mutation 3 crashes BEFORE `storeDocument` increments the throttle counter, so no `<source>.autosave.docx` is ever produced. Even if it were produced, Phase 4's chosen Design A (post-mutation counter check) captures state AFTER the mutation completes — so on crash mid-batch, the autosave file represents N-mutation state only when N is a multiple of `autosave_every`. For arbitrary K%N≠0, mutations between checkpoints are lost.

Bundled because both issues share the same trigger (3+ inserts on a reader-loaded doc) and require coordinated decisions across `che-word-mcp-session-state-api` (autosave semantics) + `ooxml-content-insertion-primitives` (rId allocator). Splitting would mean shipping #41 fix first then later #40, leaving the half-broken autosave UX in production for the gap.

A `/spectra-discuss` session also surfaced a third concern: `DocxReader.read` uses `DispatchQueue.concurrentPerform` for parallel chunk parsing on large bodies. The shared libxml2-backed `XMLElement` nodes are not thread-safe; the comment "shared data 為唯讀" misjudges lazy property access risk. Without serialized parsing, `recover_from_autosave` cannot guarantee determinism — re-parsing the same autosave file across runs may produce subtly different in-memory state, making any "recovered" doc unverifiable. This makes "Word ops fully serialized" a load-bearing prerequisite for the entire save-durability stack, not just defense-in-depth.

## Proposed Solution

Four sequential phases within a single SDD, shipped together as `che-word-mcp v3.7.0` MINOR (default behavior change for `autosave_every`):

### Phase A — Investigation-first

Add structured logging to `insertImageFromPath`, `storeDocument`, `findBodyChildContainingText`, and the autosave checkpoint dispatch path. Reproduce locally with an NTPU-style thesis fixture (or `XCTSkip` fallback per `.note` smoke test pattern). Capture `sample $MCP_PID` snapshot + Console.app crash report for the 3rd-insert crash. The fix in Phase B depends on what Phase A reveals; Phases C–D are independently valuable and ship regardless.

### Phase B — rId allocator refactor + serial-only `DocxReader`

Replace `WordDocument.nextImageRelationshipId` (`packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift:1023-1029`) and `nextRelationshipId` (line 1221) with the writer-side `RelationshipIdAllocator` pattern — at WordDocument mutation layer, consult original rels (if `archiveTempDir != nil`) before assigning new rIds. Eliminates silent corruption when a naive counter collides with existing rels of different types (managed-type collision drops the original via overlay merge).

Kill `DocxReader.swift:456 DispatchQueue.concurrentPerform`. Fall back to serial chunk parsing always. Add a regression test that greps `packages/ooxml-swift/Sources/OOXMLSwift/IO/` for `concurrentPerform` / `withTaskGroup` / `DispatchQueue.global` / `DispatchQueue.async` and asserts none exist.

### Phase C — Autosave Design A → Design B with `autosave_every: 1` default

Refactor `storeDocument`'s autosave throttle from post-mutation counter check (Design A) to pre-mutation snapshot (Design B). Move the throttle check to the START of mutating handlers — when `count > 0 && count % N == 0`, snapshot the CURRENT (pre-mutation) state to `<source>.autosave.docx`, THEN run the mutation. With `autosave_every: 1` default, snapshot fires before every mutation → crash on mutation K preserves K-1 mutations.

Spec change is MODIFIED on `che-word-mcp-session-state-api` (the requirement "open_document supports autosave_every for periodic checkpoint" gets new scenarios for crash-mid-batch durability and updated semantics for the throttle firing point). Default flip from `autosave_every: 0` (disabled) to `autosave_every: 1` (every mutation snapshots) is the MINOR-bumping behavior change.

### Phase D — Release ceremony + close issues

Single release `v3.7.0` MINOR. Bump ooxml-swift to `v0.13.3` for the rId allocator + serial DocxReader changes (PATCH, no API break). Standard release ceremony per past phases (universal binary, mcpb repackage, marketplace sync, `/idd-close #40 #41`).

## Non-Goals

- **Time-based autosave throttle** (autosave every 30s): rejected. Per-N-mutations covers stated incident pattern; time-based requires `DispatchSourceTimer` + actor-isolated firing coordination.
- **WAL / journal-based recovery**: rejected (deferred from prior SDD; per-N snapshots are sufficient).
- **Parallel `DocxReader` with proper synchronization**: rejected. The cost of correctly synchronizing libxml2-backed `XMLElement` access across worker threads (likely requires serializing through a single thread anyway) outweighs the perf benefit. Serial parsing on a large NTPU thesis is a 200–800ms regression on `open_document` once per session — acceptable trade for determinism.
- **Hidden directory placement** for autosave file: rejected (deferred from #37 SDD; user-visible same-dir file is v1 default).
- **`autosave_every: 0` removed**: rejected. Keep N=0 as explicit opt-out for callers who want zero autosave overhead (e.g., one-shot batch importers). Default flips from 0 to 1.
- **Phase A may not yield repro**: explicit non-goal to BLOCK Phases C/D on Phase A success. If Phase A does not produce a deterministic crash trigger, ship Phases C+D anyway. Phase B's rId allocator + serial DocxReader is independently valuable.

## Alternatives Considered

- **Two separate SDDs (one per issue)**: rejected. Spec changes overlap (`che-word-mcp-session-state-api`); coordinated decisions on autosave timing + rId allocator + serialization policy benefit from one cohesive design narrative.
- **Phase B with rId allocator only (skip serial DocxReader)**: rejected per `/spectra-discuss` user point — without parsing determinism, recovery cannot be verified, undermining the entire save-durability stack.
- **Add NSLock inside actor body**: rejected as redundant. Actor is the synchronization primitive; adding NSLock just adds noise.
- **Ship Phase A logging permanently** vs. remove after investigation: ship permanently for production observability, gated behind a `CHE_WORD_MCP_LOG_LEVEL` env var (off by default).

## Impact

- **Affected specs**:
  - **MODIFIED**: `che-word-mcp-session-state-api` — autosave Design A → Design B, default flip `autosave_every: 0 → 1`, new scenarios for crash-mid-batch durability semantics
  - **MODIFIED**: `ooxml-content-insertion-primitives` — rId allocation contract: WordDocument mutation layer SHALL consult original rels (if `archiveTempDir != nil`) before assigning new rIds
- **Affected code**:
  - Modified:
    - `mcp/che-word-mcp/Sources/CheWordMCP/Server.swift` (Phase A logging + Phase C `storeDocument` Design B refactor + `open_document` default flip + tool description update)
    - `packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift` (Phase B rId allocator refactor for `nextImageRelationshipId` + `nextRelationshipId`)
    - `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift` (Phase B remove `DispatchQueue.concurrentPerform` block; serial parsing always)
    - `packages/ooxml-swift/Sources/OOXMLSwift/IO/RelationshipIdAllocator.swift` (Phase B make allocator constructible from WordDocument state, not just at write time)
    - `mcp/che-word-mcp/Package.swift` (Phase D bump ooxml-swift dep to 0.13.3)
    - `mcp/che-word-mcp/CHANGELOG.md` (Phase D v3.7.0 entry)
    - `mcp/che-word-mcp/README.md` + `README_zh-TW.md` (Phase C autosave default change documentation)
    - `mcp/che-word-mcp/mcpb/manifest.json` (Phase D version bump)
    - `packages/ooxml-swift/CHANGELOG.md` (Phase B v0.13.3 entry)
  - New:
    - `mcp/che-word-mcp/Tests/CheWordMCPTests/InsertCrashRegressionTests.swift` (Phase A repro test against NTPU-style fixture; `XCTSkip` fallback per `.note` smoke pattern)
    - `mcp/che-word-mcp/Tests/CheWordMCPTests/AutosaveDesignBTests.swift` (Phase C crash-mid-batch durability scenarios)
    - `packages/ooxml-swift/Tests/OOXMLSwiftTests/RelationshipIdAllocatorMutationTests.swift` (Phase B rId allocation against reader-loaded fixture)
    - `packages/ooxml-swift/Tests/OOXMLSwiftTests/SerialOnlyOOXMLTests.swift` (Phase B grep-based regression — fails if `concurrentPerform` / `withTaskGroup` / `DispatchQueue.global` reappears in OOXML IO sources)
