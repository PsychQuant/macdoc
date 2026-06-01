## Why

`word-builder-swift` 0.9.0 ships a write-only struct-serialization API (`Document(sections:)`) that mirrors `docx.js` 9.6.x. Per `ooxml-edit-isomorphism-foundation` ADR-008, this model must migrate to a **lens-model** architecture so word-builder-swift participates in the Edit-algebra contract (Word↔Swift edit-isomorphism + fully faithful functor + canonical-identity round-trip) shipped by the foundation work in `ooxml-edit-algebra-implementation`.

ADR-008 originally prescribed a 3-month coexistence + deprecation cycle. Scout proved zero downstream callers exist (`grep -rln "import WordBuilderSwift" packages/ mcp/ Sources/ Tests/` → 0 hits; no `Package.swift` lists word-builder-swift as a dependency). With nothing to coexist with, the coexistence cycle protects nobody and adds parallel-API maintenance debt. This change cuts directly to the lens model in word-builder-swift 1.0.0.

## What Changes

- **BREAKING**: Remove the v0.9.0 struct-serialization API. The following public types are deleted: `Document`, `Section`, `SectionChild`, `Paragraph` (the word-builder-swift one), `Run` (the word-builder-swift one), `Table` (the word-builder-swift one), `Enums` (HeadingLevel, AlignmentType — already mirrored from OOXMLSwift), and the `Packer` enum.
- **BREAKING**: Remove `DocumentConverter` — the v0.9.0 → OOXMLSwift bridge is no longer needed because LensDocument wraps WordDocument directly.
- **NEW**: `LensDocument` struct that wraps `OOXMLSwift.WordDocument`. Public surface:
  - `init()` — empty document
  - `init(reading: URL) throws` — parse an existing `.docx`
  - `func apply(_ edit: any Edit) throws -> LensDocument` — applies a single Edit via the foundation's Edit protocol; returns a new LensDocument (immutable)
  - `func apply<S: Sequence>(_ edits: S) throws -> LensDocument where S.Element == any Edit` — sequence-folding apply
  - `func emit(to url: URL) throws` — serialize to disk via OOXMLSwift's DocxWriter
- **NEW**: All `examples/*.swift` files rewritten to use LensDocument + Edit. The lens-rooted authoring flow shows how to construct documents via the Edit protocol (e.g., starting from empty, applying `WordEdit.applyInsertParagraph`, then `emit`).
- **NEW**: README sections: "Migration from 0.9.0" with a 3-row table mapping old-call → new-call; "Architecture" section explaining the lens model + Edit-algebra integration.
- **MODIFIED**: `Package.swift` bumps version to `1.0.0`. `Tests/` rewritten to verify the lens surface.
- **REUSES**: The Edit protocol (`OOXMLSwift.Edit`) and OOXMLEdit/WordEdit enums from the foundation. No new `WordBuilderEdit` protocol is introduced.

## Non-Goals

- **Coexistence period**: Rejected per the no-callers observation. The struct API gets removed atomically, not deprecated-then-removed across versions.
- **A separate `WordBuilderEdit` protocol**: Rejected per ADR-009's "Layer 3/4 front-ends to the foundation" framing — duplicating the Edit protocol violates the single-source-of-truth principle and creates parallel functor algebras.
- **che-word-mcp and macdoc CLI adoption of LensDocument**: Out of scope. These packages do not currently import word-builder-swift; adoption (if it happens) is deferred to per-package Spectra changes that cite this one.
- **ooxml-swift modifications**: The Edit-algebra runtime is already complete (`ooxml-edit-algebra-runtime` capability spec). This change consumes it, does not modify it.
- **word-aligned-state-sync coordination beyond cross-references**: ADR-008 anticipated convergence in the v1.0.0 cleanup window. With this change scoped to API replacement only (no Reducer or OpLog changes), no convergence work is needed.
- **Preserving the `docx.js` parallel naming**: The v0.9.0 spec's "Public API mirrors docx.js top-level types" Requirement (`Document`, `Section`, `TextRun`, etc.) is removed. The lens model is fundamentally a different abstraction; pretending otherwise via type aliasing would mislead callers about the underlying semantics.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `word-builder-swift`: Replace the v0.9.0 docx.js-parallel struct-serialization Requirements with v1.0.0 lens-model Requirements. The capability's Purpose statement changes from "1:1 mirror of npm docx" to "lens-model handle wrapping OOXMLSwift.WordDocument that exposes the Edit-algebra contract for `.docx` authoring".

## Impact

- Affected specs:
  - `openspec/specs/word-builder-swift/spec.md` — Purpose + all v0.9.0 Requirements removed; new v1.0.0 Requirements added (LensDocument shape, Edit-protocol reuse, emit semantics).
- Affected code:
  - Modified: `packages/word-builder-swift/Package.swift` — version bump to 1.0.0.
  - Modified: `packages/word-builder-swift/README.md` — rewritten for lens model + Migration from 0.9.0 table + Architecture section.
  - Modified: `packages/word-builder-swift/CHANGELOG.md` (or create if absent) — v1.0.0 entry describing the BREAKING change + foundation references.
  - New: `packages/word-builder-swift/Sources/WordBuilderSwift/LensDocument.swift` — the lens-model handle.
  - New: `packages/word-builder-swift/Sources/WordBuilderSwift/WordBuilderSwift.swift` — module re-exports of OOXMLSwift's Edit / OOXMLEdit / WordEdit so callers don't need a second import.
  - Removed: `packages/word-builder-swift/Sources/WordBuilderSwift/Document.swift`
  - Removed: `packages/word-builder-swift/Sources/WordBuilderSwift/Packer.swift`
  - Removed: `packages/word-builder-swift/Sources/WordBuilderSwift/DocumentConverter.swift`
  - Removed: `packages/word-builder-swift/Sources/WordBuilderSwift/Paragraph.swift`
  - Removed: `packages/word-builder-swift/Sources/WordBuilderSwift/Run.swift`
  - Removed: `packages/word-builder-swift/Sources/WordBuilderSwift/Table.swift`
  - Removed: `packages/word-builder-swift/Sources/WordBuilderSwift/Enums.swift`
  - Modified: All files under `packages/word-builder-swift/examples/` — rewritten to use LensDocument + Edit (file paths preserved by example number).
  - Modified: All files under `packages/word-builder-swift/Tests/` — rewritten to verify lens surface.
- Affected processes:
  - GitHub Release flow for word-builder-swift bumps to 1.0.0 (BREAKING per semver).
  - No CI changes (the package's existing CI continues to run `swift test`).
- Cross-repo coordination:
  - `ooxml-edit-isomorphism-foundation` ADR-008 (archived) is the originating mandate; no modifications to that change.
  - `ooxml-edit-algebra-implementation` (archived as `ooxml-edit-algebra-runtime` capability spec) provides the Edit protocol this change consumes.
  - `word-aligned-state-sync` continues independently; cross-reference is informational, no action required from that change.
  - macdoc#101 — closes after this change archives.
