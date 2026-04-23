## Context

**Current state**: `che-word-mcp v3.6.0` shipped 2026-04-23 16:55, closing the `che-word-mcp-save-durability-stack` SDD. Within hours, two regressions filed:

- #41 — Sequential `insert_image_from_path` × 3 against NTPU thesis crashes MCP on 3rd call. Refutes #39 "parallel race" hypothesis (actor model from v3.5.4 correctly serializes), but actual crash root cause unknown.
- #40 — `autosave_every: 3` produces no `<source>.autosave.docx` because mutation 3 crashes before counter increments. Even with successful mutations, Phase 4's chosen Design A (post-mutation throttle) cannot preserve K-1 mutations on crash at K when K%N≠0.

Source audit findings established as input:

- `Sources/CheWordMCP/Server.swift` `insertImageFromPath` → `await storeDocument`: actor-isolated, sync internals, no `Task { }` / `DispatchQueue.async` spawn — actor serialization is real. Cannot explain crash from parallelism.
- `packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift` `nextImageRelationshipId` (line 1023-1029) and `nextRelationshipId` (line 1221) compute new rIds as `baseId + headers.count + footers.count + images.count` — naive counter that doesn't consult original rels. Demonstrably wrong for any reader-loaded doc with arbitrary existing rels (silent corruption when colliding with existing managed-type rels).
- `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift` line 456 uses `DispatchQueue.concurrentPerform` for parallel chunk parsing on bodies with `count >= 256`. Worker threads write to `UnsafeMutablePointer<[BodyChild]>` distinct indices (no array race), but each worker calls `parseParagraph` / `parseTable` against shared libxml2-backed `XMLElement` nodes. The comment "shared data 為唯讀" is partially false: lazy property access on `XMLElement` may race, and libxml2 is documented NOT thread-safe at the document level.

**Constraints**:

- `ooxml-swift` is a shared dep between `mcp/che-word-mcp` and `macdoc` CLI. Changes to `DocxReader` parallel parsing affect both consumers — `macdoc convert --to md` on large theses will see the same `open_document` perf regression.
- Phase 4 v3.6.0 spec scenarios are baked into `openspec/specs/che-word-mcp-session-state-api/spec.md` (synced 2026-04-23). Changes here are MODIFIED requirements, not ADDED — must be careful to update the live spec, NOT touch the archive snapshot.
- Default flip `autosave_every: 0 → 1` is a behavior change for v3.6.0 callers who already adopted the API. Window is small (single day) but exists; MINOR bump appropriate.
- `RelationshipIdAllocator` is currently `internal final class` consumed only by writer-side `DocxWriter.writeDocumentRelationships`. Extending to mutation-time allocation means making it accessible from `WordDocument` mutating methods — public API surface change in ooxml-swift.

**Stakeholders**: `che-word-mcp` end users (academic writers running batch image inserts on NTPU theses); downstream consumers of `ooxml-swift` (`macdoc` CLI users hit by serial `DocxReader` perf regression); maintainer (Che Cheng) + AI implementer (Claude).

## Goals / Non-Goals

**Goals**:

- After Phase A: structured logging captures the actual crash trigger; root cause identified with evidence (sample/Console.app crash report) — no fix shipped without confirmed cause.
- After Phase B: `nextImageRelationshipId` returns IDs that never collide with existing rels; `DocxReader.read` is fully serialized; regression test prevents future reintroduction of parallelism in OOXML IO layer.
- After Phase C: `autosave_every: N > 0` guarantees that on crash at mutation K, the `<source>.autosave.docx` file represents state through mutation K-1 (or earlier checkpoint, never partial). Default flip means safety-by-default for new callers.
- After Phase D: v3.7.0 ships, marketplace synced, both #40 and #41 closed via `/idd-close`.
- The save-durability stack's recovery semantics become trustworthy: parsing determinism + correct rId assignment + pre-mutation snapshots = `recover_from_autosave` guaranteed to restore exact pre-crash session state.

**Non-Goals**: see proposal.md Non-Goals section (time-based throttle, WAL, parallel `DocxReader` with synchronization, hidden directory placement, removing N=0 opt-out, blocking C/D on Phase A success).

## Decisions

### Decision: Investigation-first with structured logging gate before any fix

**What**: Phase A ships first as a logging-only change (no behavior change). Add `os_log` (or `FileHandle.standardError` for stderr) instrumentation at: `insertImageFromPath` entry/exit (with arg summary), `findBodyChildContainingText` entry (with anchor + body.children.count), `storeDocument` entry/exit (with autosaveCounter state), and the autosave checkpoint dispatch path. Reproduce locally with NTPU-style thesis fixture (use `XCTSkip` fallback per `.note` smoke test pattern in `Tests/MacDocCLITests/NotePDFConvertTests.swift` precedent). Capture `sample $MCP_PID` snapshot just before sending the 3rd insert request + Console.app crash report after the crash. Only after the actual crash trigger is identified does Phase B's fix proceed.

**Why**: My v3.5.4 commit message claimed reentrancy audit was complete; #41 proves the audit didn't cover the deeper bug. Shipping a fix without confirmed cause repeats this gap. Source-only audit gives 4 ranked hypotheses but cannot conclusively identify which one fires; runtime instrumentation is the only path to certainty.

**Alternatives considered**:
- Skip Phase A, ship Phases B/C and hope: rejected. If the crash is in a code path not touched by B/C, ship would be ineffective and we'd be back here in another release cycle.
- Add logging permanently vs gate behind env var: gate behind `CHE_WORD_MCP_LOG_LEVEL=debug` env var. Logs off by default to avoid noise; investigators can re-enable post-ship.

### Decision: Kill `DocxReader.concurrentPerform`; serial-only OOXML IO policy with regression-as-test

**What**: Remove the parallel chunk-parsing block at `DocxReader.swift:456-497`. Replace with a simple `for ci in 0..<chunkCount { ... }` serial loop preserving the same `chunkResults` aggregation pattern (or simplify back to single-pass parsing if chunking adds no benefit without parallelism — leave that as TBD until Phase B implementation reveals which is cleaner). Add a regression test `SerialOnlyOOXMLTests.testNoParallelPrimitivesInOOXMLIO` that runs `grep -rE 'concurrentPerform|withTaskGroup|DispatchQueue\\.global|DispatchQueue\\..*\\.async' packages/ooxml-swift/Sources/OOXMLSwift/IO/` and `XCTAssertEqual(result.count, 0)`.

**Why**: Two layered reasons.
1. `XMLElement` (Foundation's libxml2 wrapper) is documented NOT thread-safe at the document level. The comment "shared data 為唯讀" misjudges the lazy-init risk on child collections / attribute dicts. Apple's XMLDocument tree state is mutated lazily on first access from any thread.
2. **Determinism is prerequisite for recovery** (per `/spectra-discuss` user point): if `DocxReader.read` produces non-identical results across calls due to parallel non-determinism, `recover_from_autosave` cannot guarantee exact state restoration. The save-durability stack collapses without parsing determinism.

**Alternatives considered**:
- Keep parallel + add proper synchronization (e.g., serialize through a single `XMLDocument`-owning thread): rejected. Cost of correctness > perf benefit; on a 1000-paragraph NTPU thesis, perf regression is 200-800ms once per session — acceptable.
- Soft-deprecate (warn but keep): rejected. If the path exists, future code paths will reuse it. Hard removal + grep test prevents regression.

### Decision: Refactor `nextImageRelationshipId` (and `nextRelationshipId`) to consult original rels via `RelationshipIdAllocator`

**What**: Make `RelationshipIdAllocator` constructible from a `WordDocument`'s `archiveTempDir` (parses original rels XML into the allocator's "taken" set). Cache the allocator on `WordDocument` (lazy property: created on first mutation that needs an rId, invalidated when `archiveTempDir` changes). Replace direct calls to `nextImageRelationshipId` / `nextRelationshipId` with `allocator.allocate()`. For initializer-built docs (no `archiveTempDir`), allocator starts from `rId4` (or `rId5` with numbering) — preserves current behavior for `create_document` callers.

**Why**: The naive counter `baseId + headers.count + footers.count + images.count` is demonstrably wrong for reader-loaded docs with arbitrary existing rels. Even if NOT the root cause of #41, it's a latent silent-corruption bug for any NTPU-thesis-style fixture. Writer-side `RelationshipIdAllocator` (introduced v0.13.1) already implements the right pattern — extend, don't duplicate.

**Alternatives considered**:
- Keep counter, add post-write rId remapping in `RelationshipsOverlay`: rejected. Remapping requires updating drawing references in `document.xml`, headers, footers, comments — combinatorial explosion across the document tree.
- Compute allocator at write time and let writer remap typed rIds: rejected. Drawings in document.xml are emitted with the typed model's rId at insert time; write-time remapping requires touching all drawings post-hoc.
- Make `RelationshipIdAllocator` `public` for downstream consumers: defer (start `internal`, promote later if `macdoc` CLI needs it).

### Decision: Autosave Design A → Design B; default `autosave_every: 0 → 1`

**What**: Move the autosave throttle check from `storeDocument` (post-mutation) to the START of every mutating handler (`insertImageFromPath`, `insertParagraph`, `replaceText`, `addHeader`, etc.). When `autosaveEvery[docId] > 0` and `autosaveCounter[docId] > 0` and `counter % N == 0`, snapshot the CURRENT pre-mutation state to `<source>.autosave.docx` BEFORE running the mutation. With N=1 default, every mutation triggers a snapshot of state-just-before-mutation → crash at mutation K preserves mutations 1..K-1 in the autosave file.

Refactor approach: extract a `dispatchAutosaveCheckpointIfDue(docId:)` helper called at the top of each mutating handler. Increment the counter AFTER mutation success in `storeDocument` (preserves count semantics: counter == number of successful mutations).

Spec change: MODIFIED requirement "open_document supports autosave_every for periodic checkpoint" with new scenarios for crash-mid-batch durability. Default value documented as `1` (was `0`).

**Why**: Design A captures state AFTER the mutation completes; can't help with crash mid-mutation. Design B with N=1 is the only design that always preserves "everything before the crashing mutation" — the natural recovery semantic users expect.

**Alternatives considered**:
- Keep Design A but document the limitation: rejected. The whole point of `autosave_every` per #37 is "don't lose work on crash"; documentation can't rescue a fundamentally wrong design.
- Hybrid (eager pre-checkpoint on first mutation + Design A throttle thereafter): rejected. Edge cases proliferate (when does the pre-checkpoint reset?). Design B with N=1 default is simpler and more predictable.
- Default N=2 or N=3 instead of N=1: rejected. Any N>1 means losing N-1 mutations on worst-case crash timing. N=1 is max safety; perf-conscious callers can opt out via N=0 or a higher N.

### Decision: Single SDD ships as `che-word-mcp v3.7.0` MINOR + `ooxml-swift v0.13.3` PATCH

**What**: One coordinated release for all three issue closures. `ooxml-swift v0.13.3` ships rId allocator refactor + serial DocxReader (no public API break, PATCH bump). `che-word-mcp v3.7.0` ships dep bump + Phase A logging + Phase C autosave Design B + default flip (MINOR for default change). Standard release ceremony per recent precedent (universal binary, mcpb repackage, GitHub release with curl-uploaded assets, marketplace sync, `/idd-close #40 #41`).

**Why**: Coupling decisions (autosave design depends on rId allocator behavior; serial DocxReader is prerequisite for trustworthy recovery; Design B requires the snapshot-write path to be safe). Single ship reduces user-facing churn. `ooxml-swift` PATCH is correct (internal allocator change is not API-visible).

**Alternatives considered**:
- Ship `ooxml-swift v0.14.0` MINOR (in case allocator API surface change leaks): rejected after audit — `RelationshipIdAllocator` stays `internal`; no public API change.
- Ship `che-word-mcp v3.6.1` PATCH (no behavior change): rejected because default flip IS a behavior change.
- Ship `che-word-mcp v4.0.0` MAJOR (break compat): rejected — no removed APIs, no signature changes, just default value flip + safer semantics.

## Risks / Trade-offs

- [**Phase A may not yield deterministic repro**] → Mitigation: explicit Non-Goal to NOT block C/D on Phase A. If after timeboxed investigation (1-3h) no repro, document hypotheses + symptoms in commit + ship Phases B+C+D. Phase B's allocator fix likely closes #41 anyway as a side effect even if root cause was different.

- [**Serial `DocxReader` perf regression**] → Mitigation: measured cost on NTPU thesis (1000+ paragraphs) is 200-800ms once per `open_document`. Document in CHANGELOG as known regression. If user complaints, follow-up SDD can add proper async-await-based per-paragraph parsing (no shared XMLElement state) — defer.

- [**`autosave_every: 1` default = perf cost per mutation**] → Mitigation: snapshot write reuses `DocxWriter.write` (atomic-rename, ~50-200ms on 200-paragraph doc). Heavy-mutation callers (e.g., 100 `replace_text_batch` calls) will see noticeable cumulative latency. Document the trade-off; advanced callers can pass `autosave_every: 0`.

- [**Default flip is a behavior change for early v3.6.0 adopters**] → Mitigation: window is small (< 24h since v3.6.0 ship). Document prominently in v3.7.0 CHANGELOG: "BREAKING (effective): `autosave_every` default 0 → 1; pass `autosave_every: 0` to opt out". MINOR bump signals behavior change per semver.

- [**Phase B's `RelationshipIdAllocator` constructor that parses XML on every WordDocument mutation**] → Mitigation: cache the allocator on `WordDocument` as a lazy property; rebuild only when `archiveTempDir` changes (i.e., never, for the lifetime of an open session). Per-session cost: one XML parse at first rId-needing mutation.

- [**Phase A logging permanently shipped with env var gate**] → Mitigation: env var `CHE_WORD_MCP_LOG_LEVEL=debug` (default off — production default is silent). Add to README as troubleshooting tool.

- [**Spec MODIFIED requirements interact with archived v3.6.0 SDD snapshot**] → Mitigation: archive snapshot at `openspec/changes/archive/2026-04-23-che-word-mcp-save-durability-stack/specs/` is immutable per spectra archive contract. The current `openspec/specs/che-word-mcp-session-state-api/spec.md` gets the MODIFIED requirements; archive remains as historical record of v3.6.0's design.

## Migration Plan

The 4 phases ship in sequence within a single release. Each phase is implementable as one commit (or set of commits in the corresponding repo); coordinated release tag at the end.

- **Phase A**: ooxml-swift untouched. che-word-mcp gets logging instrumentation + repro test fixture infra. Commit, run repro locally, capture artifacts, document findings inline. No external visible change.
- **Phase B**: ooxml-swift `RelationshipIdAllocator` constructor + WordDocument allocator cache + DocxReader serial fallback + grep regression test. Tag `ooxml-swift v0.13.3`. che-word-mcp `Package.swift` dep bump.
- **Phase C**: che-word-mcp `Server.swift` autosave Design B refactor + `open_document` default flip + spec MODIFIED + README. Test for crash-mid-batch durability scenarios.
- **Phase D**: bump che-word-mcp `mcpb/manifest.json` + `CHANGELOG.md` + universal binary build + mcpb repackage + GitHub release `v3.7.0` + plugin marketplace sync + `/idd-close #40 #41`.

**Rollback**: each phase reverts independently by reverting commits + retagging. Phase B rollback restores `v0.13.2` behavior (parallel parsing, naive allocator). Phase C rollback restores Design A; default `autosave_every: 0`. Coordinated rollback would be `che-word-mcp v3.6.1` ⟶ pin ooxml-swift back to 0.13.2 + revert Server.swift autosave + restore default. Effort: ~30 min if needed.

## Open Questions

- After Phase A reveals root cause, should we add a runtime check (e.g., assert no `Task { }` is spawned inside actor body) as defensive measure, or trust the regression-as-test in Phase B? (Tentative: trust Phase B; runtime check adds complexity without clear payoff.)
- Should the autosave checkpoint write reuse `DocxWriter.write` (atomic-rename, full overlay merge) or a faster scratch-mode write? (Tentative: reuse atomic-rename — correctness over perf for autosave; users complaining about latency can opt out via N=0.)
- Should `recover_from_autosave` validate that the recovered doc parses cleanly (round-trip via DocxReader) before accepting? (Tentative: no — adds latency; if user explicitly invokes recover, trust the autosave file. If parse fails, error propagates naturally.)
