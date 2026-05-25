## Why

The macdoc OOXML toolchain has shipped working infrastructure for canonical-identity round-trip (ooxml-swift v0.13.0+ overlay save through v0.20.3's 5 preservation classes) and a write-only DSL (word-builder-swift 0.9.0), but the **architectural contract binding these together has never been pinned**. Downstream efforts — #92 (dxedit declarative CLI), #88 (R → WordBuilderSwift generator), #90 (che-pptx-mcp) — are advancing as parallel design negotiations, each implicitly assuming a different mental model for what an "edit" is and what "round-trip safe" means.

Issue #99 consolidates a four-stage discussion (论文 rescue → library is the goal → radical translation chosen over reference-template/hand-craft → canonical-identity over byte-identity over semantic-equivalence → Tree + Lens over Struct serialization → Edit as fully-faithful-functor) into one architectural commitment: **the macdoc OOXML toolchain treats Word↔Swift edit-isomorphism (fully faithful functor) as its core architectural contract, not a library-internal implementation detail.**

Without locking this contract now, every downstream proposal (PR #94/#95/#96/#97/#98 already blocked on spec ambiguity per 6-AI verify reports) will continue surfacing the same five missing decisions: edit semantics, two-layer algebra mechanics, CD review discipline, module split, and where the boundary between "decision-pin" and "implement" lives.

## What Changes

This change pins the architectural contract via:

- **Edit as first-class type** (NEW). Currently `Edit` is an architectural primitive expressed through `Document.applyOverlay()` and `Document.markDirty()` patterns shipped in v0.13.0+. This change elevates `Edit` to a first-class Swift type that carries its own equality, composition, and `lower()` semantics. Existing overlay-save infrastructure becomes the runtime backing; the type-level contract becomes explicit.

- **Two-layer edit algebra** (NEW). Define `WordEdit` (semantic, Word-UI-mirroring) and `OOXMLEdit` (syntax-level, byte-precise) as separate Swift types with `WordEdit.lower(): [OOXMLEdit]` as the bridge. The naturality property — `WordEdit(a) ∘ WordEdit(b)` lowers equivalently to `(WordEdit(a) ∘ WordEdit(b)).lower()` — becomes a normative invariant.

- **Canonical-identity contract** (NEW spec, formalizing existing behavior). The contract `parse(x) → mutate → serialize` produces output where the unmodified subtree (after c14n) is bytewise-equal to its input form. v0.20.3's 5 preservation classes already enforce this empirically; this change writes it as a normative spec Requirement with explicit Scenarios for sectPr / comments / watermarks / vendor extensions / Zotero customXml.

- **CD discipline as PR review gate** (NEW process). Every PR introducing a new `OOXMLEdit` or `WordEdit` case SHALL attach a commutative diagram + commute proof (ASCII ladder, IETF-style). Reviewer rejects PRs without it. The diagram serves three roles: verification spec generator, documentation standard, and incompatibility-surface detector.

- **9 ADRs** (NEW design.md sections) capture the per-decision rationale: round-trip contract (ADR-001), Edit-as-first-class (ADR-002), two-layer algebra (ADR-003), module split (ADR-004), operation naming (ADR-005), Word UI as ground truth (ADR-006), conformance suite extension (ADR-007), word-builder-swift lens migration path (ADR-008 deferred), downstream rerouting (ADR-009).

- **Module split** (NEW, deferred implementation). `OOXMLSyntax` (Layer 0+1, lossless tree + typed lens) vs `OOXMLSemantic` (Layer 2, Word-UI-mirroring semantic API) vs `OOXMLDSL` (Layer 3, result-builder front-end). ADR-004 documents the split; actual module reorganization deferred to follow-up changes.

- **Apply phase scope** (Hybrid, per spectra-discuss conclusion): implement ONLY ooxml-swift `Edit` type elevation + property-based fully-faithful-functor test on 3–5 representative `OOXMLEdit` operations (e.g., `insertParagraph`, `setBold`, `insertHyperlink`) using the existing NTPU thesis fixture. **All other migrations explicitly deferred** to follow-up Spectra changes citing this foundation.

**BREAKING**: None in this change's apply scope. The Edit type elevation is additive (existing callers continue working). Lens migration for `word-builder-swift` is a future BREAKING change deferred to its own Spectra change (per ADR-008).

## Non-Goals (optional)

Captured in design.md Non-Goals section per template guidance. Key Non-Goals:

- Implementing `word-builder-swift` lens-model migration (deferred to dedicated follow-up Spectra change per ADR-008)
- Refactoring `che-word-mcp` MCP tool boundary to expose `WordEdit` directly (deferred to follow-up; current Document-mutation API stays during transition)
- Re-routing downstream issues (#92 dxedit, #88 R-wordbuilder, #90 pptx-mcp) operationally; this change documents the rerouting *intent* via ADR-009 but the operational re-framing is a separate change per downstream
- Automated CD-diagram validation tooling (manual reviewer discipline only; automated tools may follow if proven necessary)
- Implementing the full `[OOXMLEdit]` surface — only 3–5 representative operations for property-test validation

## Capabilities

### New Capabilities

- `ooxml-edit-algebra`: The architectural contract for Word↔Swift edit-isomorphism. Defines `Edit` type semantics, two-layer algebra (`WordEdit` / `OOXMLEdit`), `lower()` bridge naturality, canonical-identity round-trip contract, CD discipline as review gate, and the relationship between this contract and existing prior-art documents (`lossless-conversion.md`, `structural-editing-paradigm.md`, `functional-correspondence.md`).

### Modified Capabilities

(none — this change introduces a new cross-cutting capability rather than modifying existing per-tool/per-area specs)

## Impact

- Affected specs: `ooxml-edit-algebra` (new capability under `openspec/specs/ooxml-edit-algebra/`)
- Affected code:
  - New: `packages/ooxml-swift/Sources/OOXMLSwift/EditAlgebra/Edit.swift` (Edit type elevation)
  - New: `packages/ooxml-swift/Sources/OOXMLSwift/EditAlgebra/OOXMLEdit.swift` (3–5 representative cases)
  - New: `packages/ooxml-swift/Sources/OOXMLSwift/EditAlgebra/WordEdit.swift` (corresponding semantic-layer cases)
  - New: `packages/ooxml-swift/Tests/EditAlgebraTests/FullyFaithfulFunctorTests.swift` (property-based test using NTPU thesis fixture)
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Document.swift` (add Edit-type convenience constructors; existing applyOverlay/markDirty unchanged)
- Affected docs:
  - Modified: `docs/structural-editing-paradigm.md` (add cross-reference to new `ooxml-edit-algebra` capability)
  - Modified: `docs/lossless-conversion.md` (add cross-reference)
- Affected processes:
  - New PR template requirement: PRs touching `EditAlgebra/` must attach CD diagram (per ADR-002)
- Active Spectra changes coordination:
  - `word-aligned-state-sync` — design.md must add "Relationship to ooxml-edit-isomorphism-foundation" section; their Decision 3 (ID-based operations) becomes a refinement of this foundation's Edit-type contract, not a parallel design

**ASSUMPTION** (documented per UNATTENDED MODE directive): The Edit type's runtime backing is `Document.applyOverlay()` machinery shipped in v0.13.0+. If this assumption is wrong (e.g., overlay save's commit model is incompatible with first-class Edit composition), the apply scope expands to redesigning the overlay layer — out of this change's scope and would require splitting into pre-foundation + foundation Spectra changes.

**ASSUMPTION**: 3–5 representative OOXMLEdit operations cover enough surface to validate the fully-faithful-functor property for the contract-pinning purpose. If property tests reveal naturality violations beyond these 3–5 operations, those become follow-up issues, NOT scope expansion within this change.
