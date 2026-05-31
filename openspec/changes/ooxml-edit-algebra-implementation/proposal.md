## Why

PsychQuant/macdoc#99 (`ooxml-edit-isomorphism-foundation`, merged in PR #106 commit `648e5a5`) **locked the architectural contract** but explicitly deferred the runtime implementation. Phase 1 shipped: spec.md with 8 normative Requirements, 9 ADRs in design.md, 4 canonical CD diagrams (ADR-002 Worked Examples), PR template requiring CD diagrams for `EditAlgebra/` PRs, CD discipline README. Phase 2 — the actual Swift code that makes `Edit` / `OOXMLEdit` / `WordEdit` / `Document.apply(_:)` real types — has zero implementation.

Meanwhile, ooxml-swift v0.31.x has shipped a substantial chunk of the runtime mechanism that the foundation was supposed to build on:
- `OOXMLSwift/OpLog/Operation.swift` — `public enum Operation` with ~20 cases (insertParagraphAfter, removeParagraph, setText, setRunFormat, insertTable, insertNode fallback, updateAttribute fallback, batchBegin/End, undo/redo, unknown forward-compat)
- `OOXMLSwift/OpLog/OperationLog.swift` — `public struct OperationLog: Equatable, Sendable` (append-only log)
- `OOXMLSwift/OpLog/OperationReducer.swift` — `public enum OperationReducer { static func materialize(log: OperationLog, base: XmlTree) throws -> XmlTree }`
- `OOXMLSwift/OpLog/OperationLog+JSONL.swift` — JSONL serialization

**The implication for #99's design.md ADRs** (especially ADR-002 "runtime backing is overlay/markDirty"): the backing has changed under the foundation. The proper Phase 2 design routes `Edit.apply(to:)` through `Operation` enum + `OperationLog` + `OperationReducer`, NOT through the older `Document.applyOverlay()` / `markDirty()` patterns. This change captures the corrected design and ships the code.

## What Changes

- **NEW**: `EditAlgebra/` subdirectory in `packages/ooxml-swift/Sources/OOXMLSwift/` containing:
  - `Edit.swift` — `public protocol Edit { func apply(to: Document) throws -> Document; func lower() -> [OOXMLEdit] }` + `public enum EditError: Error { case pathNotFound(ElementID); case preserveViolation(part: String); case unsupportedOperation(String); case notImplemented }`
  - `OOXMLEdit.swift` — `public enum OOXMLEdit: Edit` with ~5 cases (insertParagraph, setBold, insertHyperlink, plus 2 selected during apply per ADR-005)
  - `WordEdit.swift` — `public enum WordEdit: Edit` with corresponding semantic-layer cases (applyBold, applyLink, applyInsertParagraph)
  - `OOXMLEdit+Operation.swift` — 1:1 (or 1:N) mapping from `OOXMLEdit` cases to `Operation` cases (the canonical mapping table, verifiable via property tests)

- **NEW**: `Document.apply(_ edit: any Edit) throws -> Document` public method. Implementation routes through existing `Operation` + `OperationLog` + `OperationReducer.materialize` infrastructure. Returns new Document (immutable apply — input unchanged).

- **NEW**: `Tests/OOXMLSwiftTests/EditAlgebraTests/` test target:
  - `EditProtocolTests.swift` — protocol conformance smoke tests for OOXMLEdit + WordEdit
  - `DocumentApplyTests.swift` — apply API behavior (immutable apply, pathNotFound throwing, preserveViolation defensive check)
  - `FullyFaithfulFunctorTests.swift` — property-based tests asserting canonical-identity invariant on 3-5 OOXMLEdit cases against NTPU thesis fixture
  - `WordEditLowerTests.swift` — `lower()` correctness for WordEdit cases (including range-crossing-paragraph)
  - `NaturalityTests.swift` — `(a ∘ b).lower() == a.lower() ∘ b.lower()` for composable WordEdit pairs

- **MODIFIED (additive)**: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift` gains `apply(_:)` public method. Existing `modifiedPartsView`, `markPartDirty`, `partTree`, `xmlTrees` unchanged.

**BREAKING**: None. Edit type is additive; existing callers continue compiling.

## Non-Goals (optional)

Captured in design.md Non-Goals. Key:
- **NOT implementing** `word-builder-swift` lens migration (per #99 ADR-008 — separate follow-up Spectra change)
- **NOT implementing** `che-word-mcp` boundary refactor (per che-word-mcp#162 tracker — depends on this ship)
- **NOT extending** `Operation` enum surface — uses what v0.31.x already shipped; if a case needs an Operation case that doesn't exist, route through `Operation.insertNode` fallback OR file an ooxml-swift issue for the new Operation case
- **NOT implementing** the full WordEdit surface — only 3 cases for property-test validation (applyBold, applyLink, applyInsertParagraph)
- **NOT writing** automated CD-diagram validation tooling — manual reviewer discipline per #99 ADR-002 stays the v1.0 mechanism
- **NOT migrating** existing che-word-mcp tools to use `Document.apply(_ edit:)` — current Document-mutation API stays; che-word-mcp#162 is the separate migration tracker

## Capabilities

### New Capabilities

- `ooxml-edit-algebra-runtime`: The Swift runtime implementation of the type-level contract pinned in `ooxml-edit-algebra` (foundation #99). Defines `Edit` protocol, `OOXMLEdit` / `WordEdit` enums with at-minimum 5 / 3 cases respectively, `Document.apply(_:)` public method, and property-based functor tests against NTPU thesis fixture. Implementation routes through v0.31.x `Operation` / `OperationLog` / `OperationReducer` machinery.

### Modified Capabilities

(none — this change ships runtime for the foundation's contract; no existing capability spec changes its Requirements)

## Impact

- Affected specs: `ooxml-edit-algebra-runtime` (new, under `openspec/changes/ooxml-edit-algebra-implementation/specs/`)
- Affected code (ooxml-swift package):
  - New: `packages/ooxml-swift/Sources/OOXMLSwift/EditAlgebra/Edit.swift`
  - New: `packages/ooxml-swift/Sources/OOXMLSwift/EditAlgebra/OOXMLEdit.swift`
  - New: `packages/ooxml-swift/Sources/OOXMLSwift/EditAlgebra/WordEdit.swift`
  - New: `packages/ooxml-swift/Sources/OOXMLSwift/EditAlgebra/OOXMLEdit+Operation.swift`
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/EditAlgebraTests/EditProtocolTests.swift`
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/EditAlgebraTests/DocumentApplyTests.swift`
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/EditAlgebraTests/FullyFaithfulFunctorTests.swift`
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/EditAlgebraTests/WordEditLowerTests.swift`
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/EditAlgebraTests/NaturalityTests.swift`
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift` (add `apply(_:)` method only)
- Affected docs:
  - Modified: `docs/edit-algebra-cd-discipline.md` — add CD diagrams for the 5 implemented OOXMLEdit cases (links from `design.md` ADR-002 Worked Examples)
- Affected processes:
  - PR template's "Edit Algebra" checklist (already shipped in #99) now enforceable — first PRs touching `EditAlgebra/` ship under this change
- Cross-repo coordination:
  - `word-aligned-state-sync` Spectra change — runtime mechanism dependency satisfied (Operation/OperationLog/OperationReducer in v0.31.x)
  - macdoc#99 design.md ADR-002 — backing reference updates from `applyOverlay/markDirty` to `Operation/OperationLog/OperationReducer` (errata to be applied to closed #99 issue body or referenced from this change's design.md)

**ASSUMPTION** (documented per spectra-discuss conclusion + verified during scout): `Operation` enum already covers the operations needed for the 3 canonical cases (insertParagraph → `insertParagraphAfter`; setBold → `setRunFormat`; insertHyperlink → composition of `insertNode` + `updateAttribute` for the relationship part). If property tests reveal a gap, route via `insertNode` fallback + file ooxml-swift issue for new Operation case.

**ASSUMPTION**: NTPU thesis fixture remains the single shared fixture for property tests. Corpus expansion is deferred to #99 ADR-007 follow-up.
