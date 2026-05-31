# `EditAlgebra/` — Edit Type Contract

This directory is the runtime home for the **Word↔Swift edit-isomorphism** contract pinned in Spectra change `ooxml-edit-isomorphism-foundation` (see `openspec/changes/ooxml-edit-isomorphism-foundation/`).

## What lives here

The runtime ships in `packages/ooxml-swift/Sources/OOXMLSwift/EditAlgebra/`:

- `Edit.swift` — `Edit` protocol declaring `apply(to:) throws -> WordDocument` and `lower() -> [OOXMLEdit]`; plus `EditError` enum with 5 cases
- `OOXMLEdit.swift` — syntactic-layer enum (cases address OOXML elements by `ElementID`)
- `WordEdit.swift` — semantic-layer enum (cases address Word UI verbs); includes `WordRange` and `ParagraphRef` structs
- `OOXMLEdit+Operation.swift` — `operations() throws -> [Operation]` per-case mapping (Decision 1 in `openspec/changes/ooxml-edit-algebra-implementation/design.md`)
- `WordDocument+Apply.swift` — `WordDocument.apply(_ edit: any Edit) throws -> WordDocument` public method routing through `OperationLog` + `OperationReducer.materialize`

Phase 2 implementation shipped via:
- ooxml-swift PR #72 — OpLog Phase 2c reducer critical-path (4 of 14 cases)
- ooxml-swift PR #73 — Edit algebra runtime + e2e tests
- ooxml-swift PR #74 — Multi-part scoping + opID-determinism fix
- ooxml-swift PR #75 — Property-based canonical-identity tests (FullyFaithfulFunctorTests)
- macdoc PR #109 — Spectra change `ooxml-edit-algebra-implementation` (proposal/design/tasks/spec)

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

## Worked Examples — `OOXMLEdit` cases

### 1. `OOXMLEdit.insertParagraph(after:content:styleId:)` — body-level mutation

Inserts a new `<w:p>` after the target paragraph in `word/document.xml`. The simplest CD shape: single-arrow OOXML schema-level change, single-arrow Swift Edit apply, with `τ` mapping the XmlTree → typed WordDocument.

```
            OOXML schema change: insert <w:p> at body[targetIdx+1]
            ┌─────────────────────────────────────────────────────┐
            │                                                     │
   docx_in ─┼───────────────────────────────────────────────────► docx_out
            │   target ElementID = e; new <w:p>X</w:p> at idx+1   │
            │                                                     │
          τ │                                                     │ τ
            │                                                     │
            ▼                                                     ▼
   doc_in ─────────────────────────────────────────────────────► doc_out
            doc.apply(OOXMLEdit.insertParagraph(
                after: e, content: "X", styleId: nil))

CD obligation:
  τ(docx_out) == doc_out
  i.e., applying the Edit on the Swift side produces a WordDocument
  whose τ-equivalent matches the docx_out the schema-level change
  produces. Verified by FullyFaithfulFunctorTests
  testInsertParagraphCanonicalIdentity: all paragraphs at positions
  0..targetIdx and targetIdx+2..end remain bytewise-equal to input;
  the new paragraph occupies position targetIdx+1.

Determinism subtlety:
  The new paragraph's libraryUUID == entry.opID (Phase 2c convention).
  This makes re-materializing the persisted log yield the same tree
  (verified by MultiPartApplyTests.testApplyPersistedLogReplaysToSameTree).
```

### 2. `OOXMLEdit.insertParagraphBefore(before:content:styleId:)` — symmetric

Symmetric to `insertParagraph(after:)`. The only difference: new `<w:p>` inserts at body[targetIdx] instead of body[targetIdx+1].

```
            OOXML schema change: insert <w:p> at body[targetIdx]
            ┌─────────────────────────────────────────────────────┐
            │                                                     │
   docx_in ─┼───────────────────────────────────────────────────► docx_out
            │   target ElementID = e; new <w:p>X</w:p> at idx     │
            │                                                     │
          τ │                                                     │ τ
            │                                                     │
            ▼                                                     ▼
   doc_in ─────────────────────────────────────────────────────► doc_out
            doc.apply(OOXMLEdit.insertParagraphBefore(
                before: e, content: "X", styleId: nil))

CD obligation: τ(docx_out) == doc_out. Verified by
testInsertParagraphBeforeCanonicalIdentity.

Composition with insertParagraph(after:) — Both shift paragraphs by 1,
just on opposite sides of the target. Applying both in sequence:
  doc.apply([before, after]) yields original [..., new1, target, new2, ...].
This composition is associative-with-target-position and tested in
DocumentApplyTests sequence fold path.
```

### 3. `OOXMLEdit.setBold(target:value:)` — run-level mutation

Sets or removes the `<w:b/>` marker inside a `<w:r>`'s `<w:rPr>`. Requires `<w:rPr>` element handling (create if missing; remove if empty after operation).

```
                  Word UI action: Cmd-B on selected run
            ┌─────────────────────────────────────────────┐
            │                                             │
   docx_in ─┼──────────────────────────────────────────► docx_out
            │   "type 'hello' then select + Cmd-B"        │
            │                                             │
          τ │                                             │ τ
            │                                             │
            ▼                                             ▼
   doc_in ─────────────────────────────────────────► doc_out
                  doc.apply(OOXMLEdit.setBold(target: runID, value: true))

CD obligation:
  τ(docx_out) == doc_out  (i.e., applying setBold on the Swift side
  produces the same state τ-equivalent to Word's behavior)

Subtlety — rPr management:
  - value: true → ensure <w:b/> present in <w:rPr>; create <w:rPr> if missing
  - value: false → remove <w:b/>; remove <w:rPr> entirely if empty
  - value: nil — NOT a valid OOXMLEdit input; setBold takes Bool, not Bool?

Verified by FullyFaithfulFunctorTests.testSetBoldCanonicalIdentity:
all non-target runs' bold flag unchanged; target run's bold = true.
```

### 4. `OOXMLEdit.removeParagraph(target:)` — body-level negative case

Removes the target `<w:p>` from body.children. Stresses the canonical-identity invariant because the body's children indices shift up by 1 for paragraphs after the target.

```
            OOXML schema change: remove <w:p> at body[targetIdx]
            ┌─────────────────────────────────────────────────────┐
            │                                                     │
   docx_in ─┼───────────────────────────────────────────────────► docx_out
            │   target ElementID = e; body[targetIdx] removed     │
            │                                                     │
          τ │                                                     │ τ
            │                                                     │
            ▼                                                     ▼
   doc_in ─────────────────────────────────────────────────────► doc_out
            doc.apply(OOXMLEdit.removeParagraph(target: e))

CD obligation: τ(docx_out) == doc_out. Verified by
FullyFaithfulFunctorTests.testRemoveParagraphCanonicalIdentity.

Stress on canonical-identity:
  Paragraphs at positions targetIdx+1..end now occupy positions
  targetIdx..end-1 in result. Their ElementIDs MUST be unchanged
  (only their array index shifted). The property test asserts
  Array(after.suffix(from: targetIdx)) == Array(before.suffix(from: targetIdx + 1))
  — same elements, just at lower indices.

MVP limitation (tracked in macdoc#110):
  Cross-part orphan refs (comments / footnotes / bookmarks pointing
  TO the removed paragraph) are NOT collected. A real .docx using
  removeParagraph on a paragraph with comment anchors would leave
  dangling references. Phase 2c follow-up.
```

### 5. `OOXMLEdit.insertHyperlink(target:href:displayText:)` — dual-part atomic (STUBBED)

The most complex CD: a single OOXMLEdit lowers to TWO `Operation` calls (`insertNode` for `<w:hyperlink>` in document.xml + `updateAttribute` for the Relationship Target in `_rels/document.xml.rels`). Atomicity is enforced at Edit level.

```
            OOXML dual-part schema change:
              (a) insert <w:hyperlink r:id="rNN">...</w:hyperlink> in document.xml
              (b) add <Relationship Id="rNN" Target="href"/> in _rels/document.xml.rels
            ┌─────────────────────────────────────────────────────────────┐
            │                                                             │
   docx_in ─┼───────────────────────────────────────────────────────────► docx_out
            │   target = e; href = url; displayText = text                │
            │                                                             │
          τ │                                                             │ τ
            │                                                             │
            ▼                                                             ▼
   doc_in ─────────────────────────────────────────────────────────────► doc_out
            doc.apply(OOXMLEdit.insertHyperlink(
                target: e, href: url, displayText: text))

CD obligation:
  τ(docx_out) == doc_out, AND atomicity invariant holds:
  if EITHER sub-operation fails validation, NEITHER is applied
  (no partial state visible to caller).

Current status — STUBBED:
  Pending §5 composite design checkpoint (macdoc#105 tasks.md §5).
  5 open design questions:
    (1) target type semantics (wrap existing Run vs insert new wrapper?)
    (2) atomicity strategy (Operation.batchBegin/End or pre-validation?)
    (3) rels XML coordination (same Operation or cross-part composite?)
    (4) displayText nil → use href as displayed text?
    (5) run-splitting when range partial-covers a Run

  Until §5 ships, OOXMLEdit.insertHyperlink.operations() throws
  notImplemented. FullyFaithfulFunctorTests covers this case as
  XCTSkip with documented reason.

  Additionally requires ooxml-swift#71 follow-up cases:
  insertNode + updateAttribute reducer implementations (not yet in
  PR #72's critical-path subset).
```

## Worked Examples — `WordEdit` cases

The `WordEdit` enum lives at the semantic layer: case names follow Word UI verbs. Each case's `lower()` method translates to one or more `OOXMLEdit` cases, satisfying the naturality invariant `(a ∘ b).lower() == a.lower() ∘ b.lower()` for composable pairs.

### 6. `WordEdit.applyBold(range: WordRange)` — Word UI Cmd-B

The range-crossing-paragraph case is the most interesting: a single Word UI action (Cmd-B over a selection that spans paragraphs) lowers to N `OOXMLEdit.setBold` cases, one per affected paragraph.

```
              Word UI action: select text + Cmd-B
            ┌─────────────────────────────────────────────────────┐
            │                                                     │
   docx_in ─┼───────────────────────────────────────────────────► docx_out
            │   selection spans M runs across N paragraphs        │
            │                                                     │
          τ │                                                     │ τ
            │                                                     │
            ▼                                                     ▼
   doc_in ─────────────────────────────────────────────────────► doc_out

   The Swift side decomposes into two arrows:
   ┌────────────────────────────────────────────────────────────┐
   │                                                            │
   doc_in ─lower()─► [OOXMLEdit.setBold(...) × M] ─apply─► doc_out

   Lower step:
     WordEdit.applyBold(range: r).lower() returns N OOXMLEdit
     elements when range crosses paragraph boundaries (one per
     affected paragraph), per foundation ADR-002 Worked Example 4.

   Apply step:
     doc.apply([oOXMLEdit1, ..., oOXMLEditN]) chains through
     sequence-folding apply, mutating xmlTrees per OOXMLEdit.

CD obligation (this is the FULLY-FAITHFUL FUNCTOR property):
  τ(docx_out) == doc_out
  AND
  τ(WordEdit.applyBold(r)(docx_in)) == OOXMLEdits.fold(τ(docx_in))
  where OOXMLEdits = WordEdit.applyBold(r).lower().

  i.e., applying the Word UI action then translating to Swift gives
  the same result as translating first then applying the lowered
  OOXMLEdit chain. This is the diagram's commutativity claim.

Implementation status:
  WordEdit.lower() currently returns [] (stub). When §7 ships
  (macdoc#105 tasks.md §7.1), single-Run case (startRun == endRun)
  is the trivial mapping; multi-Run / multi-paragraph case requires
  document context to resolve which runs are inside the range
  (lower() is no-arg per Edit protocol, so multi-paragraph case
  needs design — likely lower-with-context or split-on-apply).
```

### 7. `WordEdit.applyLink(range: WordRange, url: URL)` — Word UI Cmd-K

Lowers to `OOXMLEdit.insertHyperlink`. Atomicity (document.xml + rels-part update) is handled at the OOXMLEdit layer.

```
              Word UI action: select text + Cmd-K (insert hyperlink)
            ┌─────────────────────────────────────────────────────┐
            │                                                     │
   docx_in ─┼───────────────────────────────────────────────────► docx_out
            │   selection = r; href = url; displayText = r.text   │
            │                                                     │
          τ │                                                     │ τ
            │                                                     │
            ▼                                                     ▼
   doc_in ─────────────────────────────────────────────────────► doc_out

   Lower step:
     WordEdit.applyLink(range: r, url: u).lower() returns
     [OOXMLEdit.insertHyperlink(target: rangeRoot, href: u,
                                displayText: rangeText)]

   Apply step:
     OOXMLEdit.insertHyperlink handles dual-part atomicity (per its
     own CD diagram above).

CD obligation:
  Same fully-faithful-functor structure as applyBold; the chain
  of arrows commutes.

Implementation status:
  Doubly stubbed: WordEdit.lower() (§7 macdoc#105) AND
  OOXMLEdit.insertHyperlink (§5 macdoc#105) both pending.
  This case is fully blocked until both ship.
```

### 8. `WordEdit.applyInsertParagraph(after: ParagraphRef, content: String)` — Word UI Enter + type

Simplest WordEdit case: 1:1 lowering to `OOXMLEdit.insertParagraph(after:)`.

```
              Word UI action: cursor at end-of-paragraph + Enter + type
            ┌─────────────────────────────────────────────────────┐
            │                                                     │
   docx_in ─┼───────────────────────────────────────────────────► docx_out
            │   ParagraphRef = p; new paragraph content = X       │
            │                                                     │
          τ │                                                     │ τ
            │                                                     │
            ▼                                                     ▼
   doc_in ─────────────────────────────────────────────────────► doc_out

   Lower step:
     WordEdit.applyInsertParagraph(after: p, content: X).lower()
     returns [OOXMLEdit.insertParagraph(after: p.elementID,
                                        content: X, styleId: nil)]

   Apply step:
     Routes through OOXMLEdit.insertParagraph's apply (see CD #1).

CD obligation: τ(docx_out) == doc_out. Naturality with composing
cases (e.g., applyInsertParagraph ∘ applyBold) verified by §9
NaturalityTests (macdoc#110 follow-up).

Implementation status:
  WordEdit.lower() returns [] (stub). When §7 ships (macdoc#105
  tasks.md §7.3), this case is the simplest 1:1 mapping.
```

## Status

The Edit type contract is **implemented and shipping** (no longer in decision-pinning state). Phase 2 runtime landed via the PRs listed above. Property-based canonical-identity tests + multi-part scoping + opID-determinism contracts are pinned. Remaining work tracked in [macdoc#110](https://github.com/PsychQuant/macdoc/issues/110):

- §5 `OOXMLEdit.insertHyperlink` composite (pending design checkpoint)
- §7 `WordEdit.lower()` per-case implementations
- §9 `NaturalityTests` (depends on §7)
- §10.2 Performance benchmark
- Item #8: stale typed-views resync after apply
- Stub-cascade test cleanup (depends on §5)

Downstream consumers:

- `che-word-mcp` (#162) — MCP tool surface refactor to `WordEdit` (deferred per ADR-009)
- `word-builder-swift` (#101) — lens-model migration (deferred per ADR-008)
- macdoc PR #94 / #95 / #96 / #97 / #98 — re-framing to Layer 3 / 4 front-ends (deferred per ADR-009)

## Related documents

- Spectra change (foundation): `openspec/changes/ooxml-edit-isomorphism-foundation/`
- Spectra change (Phase 2 runtime): `openspec/changes/ooxml-edit-algebra-implementation/`
- Capability spec (foundation): `openspec/changes/ooxml-edit-isomorphism-foundation/specs/ooxml-edit-algebra/spec.md`
- Capability spec (Phase 2 runtime): `openspec/changes/ooxml-edit-algebra-implementation/specs/ooxml-edit-algebra-runtime/spec.md`
- Prior-art docs: `docs/lossless-conversion.md`, `docs/structural-editing-paradigm.md`, `docs/functional-correspondence.md`
- Active runtime change: `openspec/changes/word-aligned-state-sync/` (provides the event-sourced runtime mechanism this contract types over)
