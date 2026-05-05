# Design: word-aligned-state-sync

## Context

ooxml-swift 0.x has accumulated a typed-model parser that handles a fixed set of OOXML element classes per `Paragraph`, `Run`, `Table`, `SectionProperties`, `Settings`, etc. Five days of bug filings (PsychQuant/ooxml-swift #62 / #63 / #64 / #65 / #67 / #69) on a single thesis fixture revealed that this approach is structurally lossy: every new element class, namespace, or schema feature requires another typed extension or `rawChildren` patch. Word-authored docx files contain ~60-150 internal parts and an unbounded set of element classes (VML, math, alternate content, RSIDs, themed fonts, custom XML, `mc:Choice`/`mc:Fallback`, w14/w15/w16 extensions). Typed-only round-trip cannot keep up.

The downstream pain is concrete. NTPU thesis rescue work has already required Python sidecar swaps to inject `<w:settings>` and `<w:sectPr>` back into ooxml-swift output because the library silently default-initialized them. Bidirectional editing (Word ↔ Swift) is currently impossible because Swift writes don't preserve what Word produces, so any "alignment" check fails.

This change resets the architecture for ooxml-swift 1.0. The library becomes:

```
docx file ↔ XmlNode tree (lossless DOM) ↔ Operation log (event-sourced history) ↔ Typed views (Paragraph/Run/Table)
```

Three artifacts share one tree per document:
1. **The on-disk docx** is the canonical OOXML.
2. **The op log** (sidecar JSONL) is the canonical edit history.
3. **The XmlNode tree** is the canonical in-memory state, derived from either by replay or by reading.

Stakeholders:
- ooxml-swift consumers: che-word-mcp (production MCP server, 234 tools), word-to-md-swift, md-to-word-swift, macdoc CLI.
- End users: NTPU thesis authors, advisors using Word's review/comment UI, AI agents driving che-word-mcp.
- Author / maintainer: Che Cheng (`kiki830621`).

Constraints:
- Word **strips unknown attributes** on save, so sync metadata cannot live inside the docx. All sync state must be sidecar.
- OOXML elements **already carry stable IDs** in many cases (`w14:paraId`, `w:bookmarkId`, `r:id`, `w:id` on comments); IDs must reuse these where present, only generating UUIDs to fill gaps.
- ooxml-swift already has a `Run.rawElements` raw-passthrough pattern (since v0.14.0+ #52). The new tree generalizes the same idea.
- Round-trip must be byte-equal on **untouched sub-trees** but is allowed to canonicalize (attribute order, namespace prefix collapse) on *touched* sub-trees. This is the same content-equality contract as `structural-editing-paradigm.md §3`.
- Swift 5.9, macOS 13+, no new external runtime deps. XML I/O stays pure-Swift (no libxml2 binding).
- che-word-mcp must continue to compile and pass its 271-test suite during the migration. Migration is staged across multiple `0.x → 1.0` releases.

## Goals

- `read(write(state)) ≡ state` for all states (tree-equality, not byte-equality, but byte-equal on untouched sub-trees).
- `write(read(docx)) ≡ docx` byte-equal on every sub-tree the caller did not modify; canonicalized on touched sub-trees.
- Every state transition between two `read`/`write` checkpoints is recoverable from the op log. `state(t) = replay(ops[0..t])` is total and deterministic.
- A docx can be constructed end-to-end from an op log with no prior docx file; equivalently, a Swift script can author a complete docx by appending operations.
- Word user edits become first-class operations: importing the docx after Word saves it appends a non-empty op set to the log that, if subsequently exported as a Swift script, reproduces the user's edits.
- Conflict policy is a typed enum (`SyncPolicy`) with explicit `swiftWins` / `wordWins` / `abortOnConflict` cases. The default is `abortOnConflict`.
- All five che-word-mcp consumer tool families compile and pass their existing tests against the new ooxml-swift without API changes (mutations route through op log internally).
- Round-trip golden corpus passes byte-equal on a documented fixture set: multi-section thesis, VML-rich, full-settings CJK, comment-anchored.

## Non-Goals

- **Real-time concurrent editing on the same docx**. Word and Swift writers are turn-based: at any instant, only one of them holds the file lock. CRDT and OT are explicitly rejected because (a) Word strips in-document sync metadata, breaking any embedded vector-clock approach; (b) the use case is one author with two editing surfaces, not a live multi-user product.
- **Cross-document log merging / branching / rebase**. The op log is per-document. Users who want branching workflows commit the sidecar log to git and use git for branching.
- **Forced-overwrite while Word holds the file lock**. Swift writes refuse with a structured error. Recovery is "close Word, then retry" — Swift does not race Word.
- **Format conversion** (Word ↔ Markdown / HTML / PDF). The macdoc `convert` pipeline remains separate. This change is strictly Word ↔ Swift state alignment.
- **Public XmlNode API**. The tree is an internal representation. Callers continue to use typed views. Exposing the tree API would re-introduce the very tight coupling to OOXML element shapes this change exists to remove.
- **Replacing che-word-mcp's MCP tool surfaces**. Tool names, schemas, and observable behavior stay identical. Only ooxml-swift internals change.

## Decisions

### Decision 1: Generic XmlNode tree as the single internal representation

ooxml-swift moves to a generic, fully-preserving XML DOM as the internal canonical state. `XmlNode` carries element name, namespace, attributes (ordered, namespace-prefixed), children (mixed text + element), and an interned source-XML offset for deterministic re-emission of unchanged sub-trees.

**Why**: The bug cluster proves that any typed-only model leaks information. docx-js (`ImportedXmlComponent` in `src/file/xml-components/imported-xml-component.ts`) shows the inverse approach works for round-trip preservation: it reads everything as a generic tree and only types the patcher's narrow operations. Adopting the same shape — but coupled with a typed view layer for caller ergonomics — gives byte-preserving round-trip by construction.

**Alternatives considered**:
- *Keep typed model, add `rawChildren: [String]` per type*: This is the current trajectory (#67 Phase A, #69 sketch). It works but every new spec gap requires another patch, every model class needs walker+writer extension, and `rawChildren` is a string-XML escape hatch with no normalization. Rejected as a long-term direction; will be deprecated as tree coverage lands.
- *Use libxml2 / SwiftSoup for the tree*: Adds a non-Swift native dep, complicates licensing, and loses control over namespace-prefix preservation rules. Rejected.
- *Use Apple `Foundation.XMLDocument`*: Available on macOS but not portable to other Apple platforms; namespace handling is opaque and reformats output; `parseError` recovery is poor on real-world docx. Rejected.

### Decision 2: Append-only operation log, persisted as JSONL sidecar

The canonical edit history lives in `<docx>.oplog.jsonl`. Every typed mutation appends one or more operations. The log is human-readable, `tail -f`-able, git-diffable, and append-only.

**Why**: Three needs converge on a log:
1. *Bidirectional sync*: when Word writes the docx, Swift recovers the user's intent by diffing the new tree against the last-synced snapshot, then encoding the diff as operations and appending. The log becomes the single chronological history regardless of writer.
2. *Time travel and blame*: `state(at: timestamp)` requires storing operations as the unit of change.
3. *Script-based authoring*: a Swift script that builds a docx is "the same code path" as replaying a log. JSONL is the interchange format; export/import to Swift code is mechanical.

JSONL specifically because:
- Append-friendly (no rewrite of prior state).
- One operation per line maps to git's per-line diff naturally.
- Plain text means it surfaces in editor diffs, code reviews, and `grep`.

**Alternatives considered**:
- *SQLite log*: queryable but binary, doesn't `tail -f`, and bundles a heavy dep for what is logically an append-only file.
- *Protobuf binary log*: smaller, faster, but unreadable. Premature optimization; logs at < 100k operations stay sub-megabyte in JSONL.
- *Embed the log inside the docx as a custom XML part*: Word strips unknown parts. Even when it doesn't, this couples the log to the file format and prevents using the log for branching/merging in git. Rejected.

### Decision 3: ID-based operations, never positional indices

Every structural element (paragraph, table, run, bookmark, comment, content control, etc.) has a stable ID. Operations reference IDs:

```
✓ insertParagraphAfter(id: paragraphID(uuid), text: "...")
✗ insertParagraph(at: 5, text: "...")
```

ID derivation order: existing OOXML `w14:paraId` (paragraph) / `w:id` (comment, bookmark) / `r:id` (relationship) → fall back to library-generated UUID stored on the XmlNode and serialized as a custom data attribute *only on Swift's internal copy*; on disk the docx loses these attributes after Word save (Word strips them), and the import path re-derives them by structural matching.

**Why**: Index-based operations (`InsertAt(5)`, `DeleteAt(7)`) invalidate one another when applied in different orders. Two independent mutations on different parts of the document should commute: that property fails under indices, holds under stable IDs.

**Alternatives considered**:
- *Positional indices with rebase logic*: This is OT. Workable but complex; OT's transformation tables are non-trivial and OOXML has many element types. Rejected as overkill.
- *Hash-based IDs (content hash)*: Same content collides, mutations to the content change the ID. Rejected.

### Decision 4: Typed APIs as views, not as the model

`Paragraph`, `Run`, `Table`, `SectionProperties`, etc. become **views**. Reading a typed property reads from the underlying XmlNode. Writing routes through the op log:

```swift
// Caller sees:
paragraph.text = "Hello"

// Internally:
log.append(.setText(elementID: paragraph.id, value: "Hello"))
log.materialize()  // updates the underlying XmlNode
// paragraph.text now reads "Hello" from the tree
```

**Why**: Callers continue to use the typed surface they already know. Behind the surface, the system maintains a single source of truth (tree + log). Avoids two-level state synchronization bugs (typed model out of sync with tree).

**Alternatives considered**:
- *Expose the XmlNode tree directly to callers*: Re-introduces tight coupling to OOXML element shapes. Rejected (also a non-goal).
- *Keep typed model as primary, tree as secondary*: Two sources of truth, two synchronization paths, two places where bugs hide. Rejected.

### Decision 5: Sidecar persistence, not in-document metadata

`<docx>.oplog.jsonl` and `<docx>.snapshot.json` live in the same directory as the docx. The docx file itself contains zero sync metadata.

**Why**: Word strips unknown attributes and unknown parts. Any sync metadata embedded in the docx survives one save cycle at most. Sidecar storage is the only durable option.

**Trade-off**: Users must distribute the sidecar files alongside the docx if they want history. We document this clearly. Sidecars are human-readable and small; committing them to git is cheap.

### Decision 6: Word-import diff via structural element-identity matching

When Word saves the docx, Swift detects the on-disk change (via mtime + content hash), reads the new tree, and computes the diff against the last-synced snapshot. Diff algorithm:

1. **Element identity matching**: For each element with an OOXML-stable ID (`w14:paraId`, `w:bookmarkId`, etc.), match by ID. For elements without stable IDs, match by structural fingerprint (path + tag + key attributes).
2. **Identity-noise normalization**: rsids, default attribute values, namespace-prefix differences, and empty-attribute presence are normalized before comparing. The normalization rules are part of the `ooxml-tree-io` spec.
3. **Operation generation**: matched-but-changed nodes produce `UpdateAttribute` / `SetText` ops; appeared nodes produce `InsertNode` ops; disappeared nodes produce `RemoveNode` ops.
4. **Append to log**: the inferred op set is appended to the log as a single transaction tagged with `source: "word"` (Swift mutations are tagged `"swift"`).

**Why**: This is *not* a generic tree-edit-distance problem (GumTree / Zhang-Shriver). OOXML elements have explicit identity for the structural ones that matter; we use it. Generic tree-diff complexity is unwarranted.

**Alternatives considered**:
- *GumTree port to Swift*: 2-3 weeks of work for an algorithm we don't need given OOXML's explicit IDs. Rejected.
- *Shell out to Python `xmldiff`*: Adds a Python runtime dep and would still need our identity-noise normalization to avoid false positives on rsids. Rejected.
- *Operational Transformation*: Requires a server. Rejected.

### Decision 7: Conflict policy is opt-in and explicit

`SyncOrchestrator.synchronize(policy:)` requires the caller to choose one of:
- `.abortOnConflict` (default): raise structured error listing conflicting element IDs; caller decides.
- `.swiftWins`: Swift's pending operations override Word's import for any element touched by both.
- `.wordWins`: Word's import overrides Swift's pending operations for any element touched by both.
- `.askUser(handler:)`: invoke handler per conflict; caller returns a per-element resolution.

**Why**: There is no universally correct policy. Library callers know their use case (CLI batch script vs. interactive tool). The default abort is safest because no silent data loss; opt-in to silent merges.

### Decision 8: Migration is staged across `0.x → 1.0`

The full architecture lands across multiple ooxml-swift releases:
- v0.x (current): typed model + ad-hoc `rawChildren` patches.
- v0.30+: introduce `XmlTreeReader` / `XmlTreeWriter` alongside the typed model; identity round-trip on the tree path proven via golden tests; typed model unchanged.
- v0.31+: typed views (`Paragraph`, `Run`, `Table`) become read-through wrappers over the tree; mutations still go through typed paths but are logged.
- v0.32+: log persistence and replay land. `OperationReducer.materialize()` is the canonical write path.
- v0.33+: Word-import diff path lands. Bidirectional sync is observable.
- v0.34+: script transcoder lands.
- v1.0: typed-only legacy paths removed; `rawChildren` deprecation completes.

**Why**: che-word-mcp is in production with 234 tools and 271 tests. A flag-day migration would break consumers for weeks. Staged migration lets each release ship through the existing 6-AI verify gate, and lets fixture coverage grow incrementally.

## Risks / Trade-offs

- [Risk: tree memory cost on large docs] → A 60-page thesis docx parses to a tree of ~30k-100k nodes. Memory should stay under 50 MB; benchmark on the NTPU thesis fixture before each milestone. Mitigation: source-XML offset interning and on-demand attribute parsing if needed.
- [Risk: typed view performance regression] → Reading `paragraph.text` traverses tree nodes; previously O(1) on cached strings. Mitigation: per-view cache invalidated on mutation; benchmark che-word-mcp's `get_paragraphs` on a 200-paragraph fixture before and after.
- [Risk: identity-noise normalization bugs producing false-positive conflicts] → If Word's rsid renumbering isn't normalized correctly, every Word save looks like edits everywhere. Mitigation: large fixture corpus of "Word save with no edits" docx pairs; round-trip diff must be empty op set.
- [Risk: log size growth on long-lived documents] → 100k operations in JSONL is roughly 10-20 MB. Acceptable for individual documents; needs compaction strategy for very long-lived files. Mitigation: snapshot + log truncation policy in v0.32+.
- [Risk: ID stability across Word saves] → Word may renumber `w14:paraId` on reorganization. Mitigation: import-path identity matcher uses structural fingerprint as fallback; library tracks Swift-internal UUIDs separately so its operations remain stable.
- [Risk: che-word-mcp test breakage during migration] → Tree-backed views may surface tiny attribute-order differences that existing string-comparison tests notice. Mitigation: each release runs full che-word-mcp + macdoc CLI test suites against the new ooxml-swift; failures block the release.
- [Risk: forgetting to dirty-mark a tree mutation] → A typed setter that updates only its cached value but not the tree creates ghost state. Mitigation: typed setters are required to call `tree.update(node:)`; debug-only assertion checks that `paragraph.text` post-write matches `tree.read(node:).text`.
- [Trade-off: typed setters now have non-trivial cost] → Every mutation is at minimum a tree update + log append. Throughput on bulk inserts (e.g., MCP `replace_text_batch`) may regress. Mitigation: add `OperationLog.batch { ... }` API that coalesces N mutations into one log transaction with one tree apply pass at the end.
- [Trade-off: sidecar files become "part of the document"] → Distributing a docx without its `.oplog.jsonl` loses history and breaks subsequent Word-imports (no snapshot to diff against). Mitigation: documented explicitly; `SyncOrchestrator.bootstrapFromDocx()` accepts a docx with no sidecar and treats it as a fresh start.

## Migration Plan

Migration is a multi-release sequence, each release independently shippable:

1. **Tree introduction (v0.30.0)**: Add `XmlTreeReader` / `XmlTreeWriter` with identity round-trip golden tests on the four-fixture corpus. Typed model and DocxReader unchanged. Tree is unused by typed paths. Acceptance: golden tests pass byte-equal on untouched sub-trees.

2. **Typed views over tree (v0.31.0)**: Switch `Paragraph` / `Run` / `Table` / `SectionProperties` / `Settings` to read through the tree. Mutations still go through typed paths but emit op log entries (log persistence not yet wired). Acceptance: che-word-mcp test suite passes 100%.

3. **Operation log persistence (v0.32.0)**: Wire op log to disk as `<docx>.oplog.jsonl`. `OperationReducer.materialize()` becomes the write path. Acceptance: replay any log → byte-equal docx output.

4. **Word-import diff (v0.33.0)**: Implement the Word-import diff algorithm and `SyncOrchestrator`. Acceptance: Word-saved docx fixture produces a non-empty op set on import; round-trip through the system reproduces the saved state.

5. **Script transcoder (v0.34.0)**: Implement script export/import. Acceptance: round-trip a docx through script form and back; outputs equal.

6. **Cleanup (v1.0.0)**: Remove typed-only DocxReader/Writer paths and ad-hoc `rawChildren`. Acceptance: codebase has one IO path (tree-based); deprecation cycle complete.

Rollback strategy: each release is a separate git tag. che-word-mcp pins ooxml-swift by version and can downgrade. The sidecar log format is forward-compatible (newer log readers handle older logs); a corrupt or absent sidecar is treated as a fresh-start by `SyncOrchestrator.bootstrapFromDocx()`.

## Open Questions

- **Q1**: Should the sidecar log be opt-in or default-on? Default-on means every docx open creates a log file even if the caller doesn't use sync. Default-off means sync is opt-in but `read(write(state))` invariants don't depend on the log.
  - *Working answer*: Opt-in via `Document.open(url, withLog: true)`. Default reads/writes don't touch sidecars. Sync features require explicit opt-in.
- **Q2**: Op log granularity for very fine mutations (single attribute change)? `UpdateAttribute(elementID, key, value)` is 1 op per attribute; bulk reformat could produce 10k ops.
  - *Working answer*: Provide `OperationLog.batch` that emits one `BatchUpdate` op carrying many sub-changes. Unbatched updates are still 1-op-1-attr.
- **Q3**: How does the tree represent mixed content (`<w:r><w:t>foo</w:t><w:tab/><w:t>bar</w:t></w:r>`)? As ordered children of `XmlNode`, with text nodes interleaved? Or text-as-leaf-attribute?
  - *Working answer*: Ordered children with explicit text-node type (`XmlNode.text(String)` case). Matches docx-js's `ImportedXmlComponent` which stores text as positional children.
- **Q4**: Should the `SyncOrchestrator` watch the docx file even when Word hasn't saved (e.g., autosave)? Or only on Word's explicit save?
  - *Working answer*: Only on file-content-change (mtime + hash). Word's `~$file.docx` lock-file appears/disappears around saves; `SyncOrchestrator` watches the lock-file lifecycle to detect Word's edit boundary.
- **Q5**: Does the design allow concurrent Swift writers (two Swift processes editing the same docx)? Out of v1.0 scope, but the log format should not preclude it.
  - *Working answer*: Single-writer assumed in v1.0. Append to the log is `O_APPEND`-locked at the OS level; concurrent Swift writers would collide on disk. v2 could add per-op vector clocks for true CRDT support if real demand emerges.
- **Q6**: How to handle the existing ad-hoc `rawChildren` field that #67-Phase-A and #69 are about to ship? Continue patching them now, or freeze the patches until v0.30.0 lands?
  - *Working answer*: Continue patching (#67-A is already in branch). The `rawChildren` patches are bridge code; v0.31.0 deprecates them when typed views move to the tree. Each patch has its own `Issue<N>RoundTripTests` that becomes a regression test once typed views land.
