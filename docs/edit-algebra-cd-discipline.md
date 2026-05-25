# `EditAlgebra/` — Edit Type Contract

This directory is the runtime home for the **Word↔Swift edit-isomorphism** contract pinned in Spectra change `ooxml-edit-isomorphism-foundation` (see `openspec/changes/ooxml-edit-isomorphism-foundation/`).

## What lives here

When the deferred Phase 2 implementation Spectra change lands, this directory will contain:

- `Edit.swift` — `Edit` protocol declaring `apply(to:) throws -> Document` and `lower() -> [OOXMLEdit]`; plus `EditError` enum
- `OOXMLEdit.swift` — syntactic-layer enum (cases address OOXML elements by path)
- `WordEdit.swift` — semantic-layer enum (cases address Word UI verbs)

Currently this directory holds only this README. The Edit type is documented as a normative contract via the Spectra change's spec; runtime files arrive when the implementation Spectra change executes (see "Status" below).

## CD discipline (PR review gate)

**Every PR introducing a new `OOXMLEdit` or `WordEdit` enum case SHALL attach a commutative diagram + commute proof.** This is non-negotiable; reviewers reject PRs without a CD diagram.

### Why CD discipline

Per `ooxml-edit-isomorphism-foundation` design.md § ADR-002, commutative diagrams give us six concrete affordances that pure `Edit` typing alone doesn't:

1. **Verification spec generator** — each Edit case `e` gets a testable obligation `τ(e_word(s)) == e_swift(τ(s))` for all states `s`
2. **Documentation standard** — PR includes an ASCII ladder (IETF-RFC style) so future maintainers can see the design intent
3. **Test generator** — property tests `∀s. f₁(s) == f₂(s)` derive directly from the two CD paths
4. **Incompatibility-surface detector** — when a CD can't be drawn cleanly, the Edit has hidden state or a cross-layer leak that must be addressed before merge
5. **Compositional reasoning** — `e₁ ∘ e₂`'s CD = paste `e₁`'s + `e₂`'s
6. **Cross-layer cube** — two-layer algebra maps to a 3D CD; the 6 faces must commute

### How to draw a CD diagram

Use ASCII-art ladder format, modeled on IETF RFCs. Show:

1. The **Word UI action** that the Edit case corresponds to (top row, for `WordEdit`) or the **OOXML schema-level change** (top row, for `OOXMLEdit`)
2. The **τ translation** (vertical arrow labels) between Word UI semantics and Swift representation
3. The **commutativity claim** (two paths from input state to output state must reach the same destination)

Example for `OOXMLEdit.setBold`:

```
                  Word UI action: Cmd-B on selected text
            ┌─────────────────────────────────────────────┐
            │                                             │
   docx_in ─┼──────────────────────────────────────────► docx_out
            │   "type 'hello' then select + Cmd-B"        │
            │                                             │
          τ │                                             │ τ
            │                                             │
            ▼                                             ▼
   swift_in ─────────────────────────────────────────► swift_out
                  Document.apply(OOXMLEdit.setBold(at: runPath, value: true))

CD obligation:
  τ(docx_out) == swift_out  (i.e., applying setBold on the Swift side
  produces the same state τ-equivalent to Word's behavior)
```

### Worked examples

See `openspec/changes/ooxml-edit-isomorphism-foundation/design.md` § ADR-002 *Worked Examples* for fleshed-out CD diagrams for:

- `OOXMLEdit.insertParagraph(at:content:)` (body-level mutation, straightforward CD)
- `OOXMLEdit.setBold(at:value:)` (run-level mutation, requires rPr handling)
- `OOXMLEdit.insertHyperlink(at:href:)` (dual-part mutation requiring relationship-part update — non-trivial CD)
- `WordEdit.applyBold(range:)` with range-crossing-paragraph case (boundary-ambiguity CD: `lower()` produces multiple OOXMLEdit cases)

## Status

This Edit type contract is currently in **decision-pinning state**: the Spectra change `ooxml-edit-isomorphism-foundation` has shipped its proposal / design.md (9 ADRs) / spec.md (8 Requirements) / tasks.md (35 tasks). Runtime implementation (Edit protocol code, OOXMLEdit / WordEdit enum cases, property tests) is deferred to a Phase 2 follow-up Spectra change that cites this foundation.

Downstream consumers:

- `che-word-mcp` (#162) — MCP tool surface refactor to `WordEdit` (deferred per ADR-009)
- `word-builder-swift` (#101) — lens-model migration (deferred per ADR-008)
- macdoc PR #94 / #95 / #96 / #97 / #98 — re-framing to Layer 3 / 4 front-ends (deferred per ADR-009; tracking issues #102 / #103 / #104)

## Related documents

- Spectra change: `openspec/changes/ooxml-edit-isomorphism-foundation/`
- Capability spec: `openspec/changes/ooxml-edit-isomorphism-foundation/specs/ooxml-edit-algebra/spec.md`
- Prior-art docs: `docs/lossless-conversion.md`, `docs/structural-editing-paradigm.md`, `docs/functional-correspondence.md`
- Active runtime change: `openspec/changes/word-aligned-state-sync/` (provides the event-sourced runtime mechanism this contract types over)
