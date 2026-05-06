## Why

ooxml-swift today is a destroy-and-rebuild parser: `DocxReader` projects a docx into a typed model that doesn't cover every OOXML element class (multi-section `<w:sectPr>`, rich `word/settings.xml`, VML, `mc:AlternateContent`, `<w:rsids>`, comment-reference-only Runs), and `DocxWriter` reconstructs from that lossy projection. Cluster-bug evidence in five days (PsychQuant/ooxml-swift #62 / #63 / #64 / #65 / #67 / #69) shows this architecture cannot reach round-trip fidelity by patching: every new file class needs another typed extension, while users encounter Word-cleared content (CJK font fallback, headerReference activation, page-number formatting) on docs the library successfully "round-trips."

The downstream goal is bigger than just lossless I/O. Authors want to:
1. Treat ooxml-swift as a library where round-trip is a hard architectural invariant, not a cluster of patched bugs;
2. Edit a docx in Swift and let Word continue editing the same file, with both sides acting as legitimate writers;
3. Reconstruct any past state from a complete operation history — including building a docx end-to-end from a Swift script;
4. State the success criterion as "the file ooxml-swift writes aligns with what Word would have written" — i.e., **align with Word**.

This change introduces an event-sourced, tree-backed state model that satisfies all four goals simultaneously. Operation log replaces direct mutation; generic XmlNode tree replaces lossy typed parser; typed APIs become projections (read views + op emitters) over the same shared tree.

## What Changes

- **NEW**: Generic `XmlNode` tree IO — `DocxReader` produces a fully-preserving DOM that retains every element, attribute, namespace, and namespace-prefix decision. `DocxWriter` serializes the tree without re-canonicalization; sub-trees that were not touched serialize byte-equal on round-trip.
- **NEW**: `OperationLog` infrastructure — append-only JSONL log of semantic operations (`InsertParagraph`, `SetText`, `InsertTable`, `RemoveNode`, `UpdateAttribute`, etc.) with stable element IDs (derive from existing OOXML `w14:paraId` / `w:bookmarkId` / `r:id` where present, generate UUID where absent). Operations reference IDs, never positional indices, so independent inserts do not invalidate one another.
- **NEW**: `OperationReducer` — pure folder that replays an op log onto a base XmlNode tree. `state(t) = replay(ops[0..t])`. Provides `materialize(log)`, `state(at: timestamp)`, `undo()`, `redo()`, `blame(elementID)`.
- **NEW**: Typed API as projection — `Paragraph` / `Run` / `Table` / `SectionProperties` and other typed views become **read accessors** on the shared tree and **op emitters** on mutation. `paragraph.text = "x"` is sugar for `log.append(.setText(elementID, "x"))`.
- **NEW**: `WordImport` path — `read(docx_modified_by_word)` produces a tree, structural diff against last-synced snapshot computes the inferred operation set, log appends it. Word user edits become first-class operations in the log.
- **NEW**: `SyncOrchestrator` — file-watcher driven coordinator that detects out-of-band docx changes, runs the import diff, and surfaces conflicts to the caller via a typed conflict policy (`SyncPolicy.swiftWins` / `.wordWins` / `.abortOnConflict`).
- **NEW**: `OperationLog` ↔ Swift script transcoder — export log as runnable Swift code; import a Swift script as the bootstrap of a new log. Building a docx from a script is the same code path as replaying any other log.
- **NEW**: Sidecar persistence — `<docx>.oplog.jsonl` (full history) and `<docx>.snapshot.json` (cached current state) live alongside the docx. The docx file itself never carries sync metadata, so Word's automatic stripping of unknown attributes does not break the system.
- **BREAKING**: Existing `DocxReader.read()` continues to return `WordDocument`, but `WordDocument` is no longer a flat typed struct holding parsed children. It is a typed view over an XmlNode tree plus an attached log handle. Direct array assignments like `doc.body.children = [...]` are replaced by typed operations that go through the log. Swift consumers that read fields are unaffected; consumers that bypass typed APIs to mutate model arrays directly require migration.
- **BREAKING**: Round-trip semantics tighten. `read(write(state)) ≡ state` and `write(read(docx)) ≡ docx` become hard invariants enforced by tests on representative fixtures (NTPU thesis, multi-section docs, VML-rich docs). Existing partial-coverage typed parsers that silently drop unknown children are replaced by the tree.
- **BREAKING for ooxml-swift internals only**: `DocxWriter.toXML()` builders that emit from typed-only fields are removed; serialization always runs through the tree. Public mutation APIs (`insertParagraph`, `setText`, etc.) keep their signatures and observable behavior.
- **DEPRECATION**: The `rawChildren: [String]` ad-hoc preservation pattern (introduced incrementally in #58 / #67-Phase-A / planned for #69) becomes redundant; once tree-backed reads land, model classes drop these fields.
- **NON-BREAKING**: All five che-word-mcp consumer tools (insert / replace / format / list / get-text families) keep their public schemas. The MCP server upgrades by bumping the lib dep; no MCP API change.

## Non-Goals (optional)

- **Real-time multi-user collaboration on .docx**: This change supports turn-based bidirectional sync (Word saves → Swift imports / Swift writes → Word reloads), not concurrent live editing. Two-actor concurrent typing in the same byte range is out of scope. CRDT and OT remain rejected because Word strips unknown attributes, defeating in-document sync metadata.
- **Cross-document operation merging (rebase across forks)**: The log is per-document. Merging logs of two divergent copies of the same docx is not a v1 feature; users are expected to commit the oplog sidecar to source control if they need branching.
- **Editing while Word holds the file lock**: When Word has the docx open and locked, Swift writes refuse with a structured error. Forced overwrite while Word is open is rejected as out-of-scope (Word would clobber Swift's write on next save anyway).
- **Format conversion** (Word ↔ Markdown / HTML / PDF): Out of scope. macdoc's `convert` pipeline remains a separate code path. This change is strictly about Word ↔ Swift state alignment.
- **Replacing the existing typed model with raw XmlNode access for callers**: Callers continue to use `Paragraph.text`, `Table.rows`, etc. The tree is internal. Exposing the tree directly is a deliberate non-goal so consumers don't bind to OOXML element shapes.

## Capabilities

### New Capabilities

- `ooxml-tree-io`: Lossless XmlNode tree reader and writer. Defines the round-trip-byte-equal contract on untouched sub-trees, the namespace-prefix preservation rules, and the identity-noise normalization (rsids, default attribute values).
- `ooxml-operation-log`: Append-only operation log format, operation taxonomy, stable element ID derivation rules, and the JSONL on-disk schema for the sidecar log.
- `ooxml-operation-reducer`: Pure replay engine and time-travel API. Defines `state(at:)`, `undo`, `redo`, `blame` semantics and the determinism guarantees on identical log replay.
- `ooxml-word-sync`: Bidirectional sync orchestrator. Defines the Word-import diff algorithm, the conflict detection rules, the conflict policy enum, the file-watcher contract, and the file-lock interaction with Word.
- `ooxml-script-transcode`: Swift-script ↔ operation-log transcoder. Defines the Swift code shape that maps to operations and the round-trip identity between scripts and logs.

### Modified Capabilities

- `docx-container-parsing`: Reader coverage tightens from "specific named parts" to "every part is round-trip-preserving via the tree". Container reading still populates typed views, but unknown elements are no longer dropped — they remain in the tree. Existing requirements about which parts are read remain valid; new requirements about preservation are added.
- `docx-revision-parsing`: Revision elements (`<w:ins>`, `<w:del>`, `<w:rPrChange>`, `<w:pPrChange>`, etc.) still parse into typed `Revision` accessors, but they are now views over the underlying tree nodes. Unknown revision children are preserved verbatim instead of being surfaced as "unknown" sentinels. Round-trip preservation of revision metadata becomes a hard invariant.

## External contract dependencies

This change does NOT introduce the following capabilities — they were locked by sibling changes archived earlier and are referenced here so Phase 4 (Script transcoder) implementation has the full contract chain. They appear in `openspec/specs/` as canonical specs; this section exists for reader navigation, not as new spec scope:

- mdocx-grammar (archived `2026-05-06-mdocx-syntax`, canonical at `openspec/specs/mdocx-grammar/spec.md`): Pins the `.mdocx` Swift DSL grammar that the script transcoder reads / writes. Phase 4 implements `ooxml-script-transcode` against this contract — `ScriptExporter` SHALL emit DSL source conforming to its 15 Requirements; `ScriptImporter` SHALL accept exactly that surface. The 14 placeholder Swift files at `packages/ooxml-swift/Sources/WordDSLSwift/` were landed by `mdocx-syntax` for Phase 4 to fill in.
- embedded-dsl-spec-pattern (archived `2026-05-06-embedded-dsl-spec-pattern-rule`, canonical at `openspec/specs/embedded-dsl-spec-pattern/spec.md`): Codifies the spec-shape rule (Requirements + Scenarios + SBE Examples + non-normative composition tree, no EBNF / PEG) that mdocx-grammar follows. Future grammar evolution inherits the same shape.

## Impact

- Affected specs:
  - New: `openspec/specs/ooxml-tree-io/spec.md`, `openspec/specs/ooxml-operation-log/spec.md`, `openspec/specs/ooxml-operation-reducer/spec.md`, `openspec/specs/ooxml-word-sync/spec.md`, `openspec/specs/ooxml-script-transcode/spec.md`
  - Modified: `openspec/specs/docx-container-parsing/spec.md`, `openspec/specs/docx-revision-parsing/spec.md`
- Affected code:
  - New:
    - packages/ooxml-swift/Sources/OOXMLSwift/Tree/XmlNode.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Tree/XmlTreeReader.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Tree/XmlTreeWriter.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/OperationLog/Operation.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/OperationLog/OperationLog.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/OperationLog/OperationReducer.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/OperationLog/ElementID.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Sync/SyncOrchestrator.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Sync/WordImport.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Sync/SyncPolicy.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Transcode/ScriptExporter.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Transcode/ScriptImporter.swift
    - packages/ooxml-swift/Tests/OOXMLSwiftTests/TreeRoundTripGoldenTests.swift
    - packages/ooxml-swift/Tests/OOXMLSwiftTests/OperationLogReplayTests.swift
    - packages/ooxml-swift/Tests/OOXMLSwiftTests/WordImportDiffTests.swift
    - packages/ooxml-swift/Tests/OOXMLSwiftTests/ScriptTranscodeTests.swift
  - Modified:
    - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxWriter.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Paragraph.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Run.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Table.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Section.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Settings.swift
  - Removed: ad-hoc `rawChildren: [String]` fields on Run / Paragraph / SectionProperties / Settings once the tree-backed view path covers them
- Affected dependencies:
  - che-word-mcp: bump ooxml-swift to v1.0 (this change is the v1 architectural reset). MCP tool surfaces unchanged; CHANGELOG migration note.
  - macdoc CLI consumers (`word-to-md-swift`, `md-to-word-swift` via lib): rebuild against new ooxml-swift; no API break in their facing direction.
- Affected fixtures (round-trip golden corpus to commit):
  - test-files/multi-section-thesis.docx (NTPU-shape, 3 sectPr)
  - test-files/vml-rich.docx (`<w:pict>` + `<mc:AlternateContent>`)
  - test-files/cjk-settings.docx (full `word/settings.xml`)
  - test-files/comment-anchored.docx (`<w:commentRangeStart>` triplets)
