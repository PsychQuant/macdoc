## Context

`macdoc`'s OOXML toolchain consists of four layers of working infrastructure that have evolved independently:

| Layer | Status | Where |
|---|---|---|
| Layer 0 — Lossless OOXML tree | Shipped v0.13.0+ (overlay save), v0.20.3 (5 preservation classes) | `packages/ooxml-swift/Sources/OOXMLSwift/` |
| Layer 1 — Typed lens (Run, Paragraph, Section) | Partially shipped (Paragraph, Run, Table, etc.) | `packages/ooxml-swift/Sources/OOXMLSwift/Models/` |
| Layer 2 — Semantic API (Word-UI-mirroring) | Not yet expressed as a layer | Scattered convenience methods on `Document` |
| Layer 3 — DSL frontend (result builder) | Shipped v0.9.0 (write-only) | `packages/word-builder-swift/Sources/WordBuilderSwift/` |
| Layer 4 — User authors / AI edits | (out of macdoc scope; consumer-side) | `*.swift` user scripts |

The architecture has been described informally across four prior-art documents (`lossless-conversion.md`, `structural-editing-paradigm.md`, `functional-correspondence.md`, `philosophy.md`) but never pinned as a normative contract. Downstream proposals (#92 dxedit, #88 R-wordbuilder, #90 pptx-mcp) each implicitly assume different mental models of "edit", causing the spec gaps surfaced by 6-AI verify on PRs #94/#95/#96/#97/#98.

The proposed contract draws on Quine's *radical translation* (1960) framing — translating between two representations (Word UI semantics ↔ Swift API semantics) is fundamentally underdetermined, and the architectural choice is *which* equivalence to preserve. Tools choose byte-identity (impossible), canonical-identity (achievable, our choice), or semantic-equivalence (too weak, loses information). Aligned with `swift-syntax`'s lossless-CST precedent and Roslyn's incremental-parse model.

## Goals / Non-Goals

**Goals:**

1. **Pin the architectural contract** between Word UI semantics and Swift API as a fully-faithful functor, with canonical-identity round-trip as the round-trip invariant. Make this contract normative (SHALL/MUST) rather than implicit-in-implementation.

2. **Elevate `Edit` to a first-class type** so equality, composition, and `lower()` semantics are expressible at the type level, not just as runtime patterns in `Document.applyOverlay()`.

3. **Establish two-layer edit algebra** (`WordEdit` / `OOXMLEdit`) so callers can choose semantic vs. syntactic granularity, and the `lower()` bridge makes the translation auditable case-by-case.

4. **Codify CD discipline** as a PR review gate: every new `OOXMLEdit` / `WordEdit` case requires a commutative diagram + commute proof attached to the PR.

5. **Validate the contract via property tests** on 3–5 representative operations (`insertParagraph`, `setBold`, `insertHyperlink`, plus 1–2 more selected during apply) using the NTPU thesis fixture already in `RealWorldDocxRoundTripSmokeTests`.

6. **Document migration paths** for downstream consumers (`word-builder-swift` lens migration; `che-word-mcp` boundary refactor; dxedit / R-wordbuilder / pptx-mcp front-end rerouting) without implementing those migrations in this change.

**Non-Goals:**

- **`word-builder-swift` lens-model migration** (deferred to follow-up Spectra change per ADR-008). Current struct-serialization model coexists during transition.
- **`che-word-mcp` MCP tool boundary refactor** to expose `WordEdit` directly. Current `Document`-mutation API stays; refactor is a future Spectra change.
- **Operational rerouting of downstream issues** (#92, #88, #90). This change documents *intent* via ADR-009; per-issue re-framing is a separate change per downstream.
- **Automated CD-diagram validation tooling**. Manual reviewer discipline only.
- **Full `[OOXMLEdit]` surface implementation**. Only 3–5 representative operations for property-test validation.
- **Implementation of the module split** (`OOXMLSyntax` / `OOXMLSemantic` / `OOXMLDSL`). ADR-004 documents the split; physical module reorganization deferred to follow-up.
- **Replacing existing `Document.applyOverlay()` / `markDirty()` patterns**. Edit type *wraps* this machinery, doesn't replace it.

## Decisions

### ADR-001: Round-trip contract = canonical-identity

**Decision**: The macdoc OOXML toolchain commits to **canonical-identity** as the round-trip contract: after `parse → mutate → serialize`, the subtree that was not modified is bytewise-equal to its input form after XML canonicalization (c14n). Modified subtrees are content-equivalent (semantically equal) to their intended new value.

**Alternatives considered**:

| Level | Contract | Verdict |
|---|---|---|
| Byte-identity | `serialize(parse(x)) == x` byte-by-byte | REJECTED — impossible. XML allows `<w:b/>`, `<w:b w:val="true"/>`, `<w:b w:val="1"/>` as semantically equal; multiple parsers produce different but valid byte sequences for the same input. |
| **Canonical-identity** | After c14n, unmodified subtree bytewise-equal | **CHOSEN** — achievable, empirically validated by v0.20.3's 5 preservation classes, aligns with `swift-syntax`/Roslyn precedent. |
| Semantic-equivalence | Word renders identically | REJECTED — too weak. Vendor extensions, comments, watermarks, customXml all dropped silently because they don't affect render. |

**Rationale**: Canonical-identity is the strongest contract empirically reachable. v0.13.0 onwards demonstrates it works in practice; this change writes it as normative SHALL.

### ADR-002: Core type = Edit (not Document); PR-must-attach-CD-diagram review discipline

**Decision**: `Edit` is a first-class Swift type with explicit equality, composition (associative `∘`), and `lower()` semantics. PRs that introduce new `Edit` cases SHALL attach a commutative diagram + commute proof.

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| `Document` as core (mutate-in-place) | REJECTED — current implicit model. Composition reasoning impossible; tests are ad-hoc; CD impossible to draw. |
| **`Edit` as first-class type** | **CHOSEN** — allows compositional reasoning, property-based tests, CD diagram per case. |
| `Operation` type (procedural framing) | REJECTED — same semantic content but loses the "algebra" framing that motivates two-layer separation. |

**CD discipline rationale** (per issue body): CD methodology gives 6 concrete affordances that pure `Edit` typing alone doesn't:

1. Verification spec generator — each Edit case `e` has obligation `τ(e_word(s)) == e_swift(τ(s))` for all `s`
2. Documentation standard — PR includes an ASCII ladder (IETF-RFC style)
3. Test generator — property tests `∀s. f₁(s) == f₂(s)` from the CD's two paths
4. Incompatibility-surface detector — non-drawable CD = hidden state or cross-layer leak in the proposed Edit
5. Compositional reasoning — `e₁ ∘ e₂`'s CD = paste `e₁`'s + `e₂`'s
6. Cross-layer cube — two-layer algebra (ADR-003) maps to 3D CD where 6 faces must commute

#### Worked Examples

The CD diagrams below are the canonical worked examples that `.github/PULL_REQUEST_TEMPLATE.md` and `docs/edit-algebra-cd-discipline.md` reference. When a new `OOXMLEdit` or `WordEdit` case is added, the PR's CD diagram should follow the same structure as one of these examples (ladder format, top arrow = Word UI action or schema change, vertical arrows = `τ`, bottom arrow = Swift Edit invocation, commutativity claim explicit at the end).

##### Example 1: `OOXMLEdit.insertParagraph(at:content:)` — body-level mutation

```
                  Word UI action: position cursor at body-children index N,
                  press Enter, type "hello"
            ┌────────────────────────────────────────────────────────┐
            │                                                         │
   docx_in ─┼────────────────────────────────────────────────────► docx_out
            │   body.children gains <w:p> with <w:r><w:t>hello</w:t> │
            │   at index N; sectPr / comments / customXml preserved   │
            │                                                         │
          τ │                                                         │ τ
            │                                                         │
            ▼                                                         ▼
   swift_in ─────────────────────────────────────────────────────► swift_out
                  Document.apply(OOXMLEdit.insertParagraph(at: N, content: "hello"))

CD obligation:
  τ(docx_out) == swift_out
  AND: c14n(docx_in.untouched_subtrees) == c14n(docx_out.untouched_subtrees)
       where untouched_subtrees = all body children at indices ≠ N + all parts outside word/document.xml
```

##### Example 2: `OOXMLEdit.setBold(at: runPath, value: Bool)` — run-level mutation with rPr handling

```
                  Word UI action: select text in Run R, press Cmd-B
            ┌────────────────────────────────────────────────────────┐
            │                                                         │
   docx_in ─┼────────────────────────────────────────────────────► docx_out
            │   Run R's <w:rPr> gains/loses <w:b/>; existing rPr     │
            │   children (font, color, etc.) preserved in order      │
            │                                                         │
          τ │                                                         │ τ
            │                                                         │
            ▼                                                         ▼
   swift_in ─────────────────────────────────────────────────────► swift_out
                  Document.apply(OOXMLEdit.setBold(at: runPath, value: true))

CD obligation:
  τ(docx_out) == swift_out
  AND: c14n(docx_in.untouched_runs) == c14n(docx_out.untouched_runs)
       — sibling Runs unaffected; Run R's text content unchanged; only rPr's <w:b/>
       presence toggled
```

##### Example 3: `OOXMLEdit.insertHyperlink(at: runPath, href: URL)` — dual-part mutation (non-trivial CD)

This example is non-trivial because the Edit modifies TWO parts atomically: `word/document.xml` (insert `<w:hyperlink>` element) AND `word/_rels/document.xml.rels` (add Relationship entry). The CD must show both legs commute.

```
                  Word UI action: select text in Run R, Insert → Hyperlink,
                  paste URL, click OK
            ┌────────────────────────────────────────────────────────┐
            │                                                         │
   docx_in ─┼────────────────────────────────────────────────────► docx_out
            │   - word/document.xml: Run R wrapped in <w:hyperlink   │
            │     r:id="rNN">; new rId allocated                      │
            │   - word/_rels/document.xml.rels: new <Relationship    │
            │     Id="rNN" Type="...hyperlink" Target="<url>"/>      │
            │   - Both modifications atomic; either both land or     │
            │     neither (no half-applied state)                    │
            │                                                         │
          τ │                                                         │ τ
            │                                                         │
            ▼                                                         ▼
   swift_in ─────────────────────────────────────────────────────► swift_out
                  Document.apply(OOXMLEdit.insertHyperlink(at: runPath, href: URL))

CD obligation:
  τ(docx_out) == swift_out
  AND atomicity: throws if rels-part write fails AFTER document.xml mutation
                 (no half-applied state in swift_out)
  AND: c14n(docx_in.parts \ {document.xml, document.xml.rels}) ==
       c14n(docx_out.parts \ {document.xml, document.xml.rels})
       — all other parts (styles, settings, customXml, etc.) bytewise-equal post-c14n
```

##### Example 4: `WordEdit.applyBold(range:)` with range-crossing-paragraph — boundary ambiguity CD

This example shows how a semantic-layer Edit lowers to MULTIPLE syntactic-layer Edits when the Word UI semantics cross structural boundaries. The CD must show that the WordEdit naturality property holds (i.e., `lower()` produces the same final state whether composed at the semantic layer or computed across separate per-paragraph OOXMLEdits).

```
                Word UI action: drag-select text spanning 2 paragraphs, press Cmd-B
                   ┌────────────────────────────────────────────────────────┐
                   │                                                         │
   docx_in ────────┼────────────────────────────────────────────────────► docx_out
                   │   Paragraph 1's affected Run: rPr gains <w:b/>         │
                   │   Paragraph 2's affected Run: rPr gains <w:b/>         │
                   │   Both Runs may need splitRun if range partial         │
                   │                                                         │
                 τ │                                                         │ τ
                   │                                                         │
                   ▼                                                         ▼
   swift_in       Document.apply(WordEdit.applyBold(range: ...))            swift_out
                                          │
                                          ↓ lower()
                                          │
                   ┌──────────────────────┴──────────────────────┐
                   │                                              │
                   ▼                                              ▼
   swift_in ─► Document.apply([                              swift_out
                  OOXMLEdit.splitRun(at: para1.run, at: rangeStart),
                  OOXMLEdit.splitRun(at: para2.run, at: rangeEnd),
                  OOXMLEdit.setBold(at: para1.runAfterSplit, value: true),
                  OOXMLEdit.setBold(at: para2.runBeforeSplit, value: true),
              ])

CD obligation (both legs commute):
  - WordEdit.applyBold(range:).apply(swift_in) == [4 OOXMLEdits].fold(apply)(swift_in)
  - Naturality: (WordEdit.applyBold(r1) ∘ WordEdit.applyBold(r2)).lower() ==
                WordEdit.applyBold(r1).lower() ∘ WordEdit.applyBold(r2).lower()
```

These four examples cover: (1) trivial body-level mutation, (2) run-level mutation with rPr handling, (3) dual-part mutation requiring atomicity, (4) semantic-layer Edit that lowers to multiple syntactic-layer Edits via range splitting. New Edit cases SHOULD follow the structure of whichever example most resembles them.

### ADR-003: Two-layer edit algebra (WordEdit / OOXMLEdit), lower() as bridge

**Decision**: Define `WordEdit` (semantic — `WordEdit.applyBold(range)`) and `OOXMLEdit` (syntactic — `OOXMLEdit.insertElement(at: rPr_path, element: <w:b/>)`) as separate types. `WordEdit.lower(): [OOXMLEdit]` bridges them. Naturality invariant: `WordEdit(a).lower() ∘ WordEdit(b).lower() = (WordEdit(a) ∘ WordEdit(b)).lower()` for composable operations.

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| Single Edit type, no semantic/syntactic split | REJECTED — Word UI semantics (Cmd-B on text crossing paragraph boundary) and OOXML syntax (split into per-paragraph rPr) diverge; conflating them buries decisions. |
| **WordEdit + OOXMLEdit with lower() bridge** | **CHOSEN** — both layers expressible, translation auditable. |
| WordEdit-only (lower implicit) | REJECTED — implementers debugging round-trip would have no syntactic-layer handle. |

**Rationale**: The two layers serve different audiences. `WordEdit` for callers expressing user intent (dxedit manifests, R-wordbuilder scripts). `OOXMLEdit` for tool implementers debugging serialization. `lower()` keeps them aligned by construction.

### ADR-004: Module split — OOXMLSyntax (L0/L1) / OOXMLSemantic (L2) / OOXMLDSL (L3)

**Decision**: The codebase splits along Layer boundaries (deferred to follow-up):

- `OOXMLSyntax` — Layer 0 (lossless tree, `OOXMLNode + trivia`) + Layer 1 (typed lens, `Run`, `Paragraph`, `Section`)
- `OOXMLSemantic` — Layer 2 (`WordEdit`, semantic-API methods, Word-UI behavior mirror)
- `OOXMLDSL` — Layer 3 (result-builder front-end, `Document { Chapter { ... } }`)

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| Keep single `OOXMLSwift` module | REJECTED — Layer mixing prevents Layer 3 callers from importing only the DSL. |
| **3-module split** | **CHOSEN** — clean Layer boundaries, smaller per-module import surfaces. |
| 5-module split (one per Layer) | REJECTED — Layer 0+1 always co-required; Layer 4 is consumer code, not macdoc-owned. |

**Note**: This ADR records the *intent*. Physical module reorganization is a follow-up Spectra change — this one only adds the `EditAlgebra/` subdirectory inside `OOXMLSwift`.

### ADR-005: Edit operation surface naming + canonical example set

**Decision**: `OOXMLEdit` case names use the schema element they target: `insertParagraph(at:)`, `setBold(at:)`, `insertHyperlink(at:href:)`. `WordEdit` cases use Word UI verb: `WordEdit.applyBold(range:)`, `WordEdit.insertLink(range:url:)`.

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| `OOXMLEdit.modify<W:p>(at:)` (XML-literal naming) | REJECTED — exposes namespace prefix as case name; breaks Swift naming conventions and creates ergonomics friction |
| `OOXMLEdit.operation(.insertParagraph, at:)` (nested enum) | REJECTED — loses pattern-match exhaustiveness and adds boilerplate per case |
| **`OOXMLEdit.insertParagraph(at:)` (flat schema-element naming)** | **CHOSEN** — matches schema vocabulary directly, Swift-idiomatic, pattern-match exhaustive |
| `WordEdit.bold(range:)` (Word-verb-only naming, no `apply` prefix) | REJECTED — collides with property accessor convention (`run.bold = true`); apply* prefix disambiguates Edit-vs-state mutation |

**Rationale**: Schema-element naming for OOXMLEdit lets implementers grep ECMA-376 spec text; verb-prefix for WordEdit signals intent (this is a mutation, not a property read).

**Apply-phase canonical example set** (3–5 operations for property-test validation):

1. `OOXMLEdit.insertParagraph(at: bodyChildIndex, content:)` — body-level mutation, covers ADR-001 contract for sectPr / comments preservation
2. `OOXMLEdit.setBold(at: runPath, value: Bool)` — run-level mutation, covers ADR-006 Word UI ground truth (Cmd-B)
3. `OOXMLEdit.insertHyperlink(at: runPath, href: URL)` — composite mutation requiring relationship part update, exercises canonical-identity for `_rels/document.xml.rels`
4. (To be selected during apply) — Table-cell mutation
5. (To be selected during apply) — Comment / Bookmark mutation

`WordEdit` counterparts: `applyBold`, `applyLink`, `applyInsertParagraph` (when range crosses semantic boundaries, lower() returns multiple OOXMLEdit cases).

### ADR-006: Word UI behavior as ground truth

**Decision**: When `WordEdit` semantics are ambiguous, the resolution is "what does Microsoft Word UI do under the equivalent user action?" Documented by:

1. Recording the user action (Cmd-B, Cmd-K, Insert→Hyperlink)
2. Inspecting the resulting OOXML diff via Word's "Save As → Word XML" (or extracting `.docx` ZIP after save)
3. The diff *is* the `lower()` output for that `WordEdit` case

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| OOXML schema (ECMA-376) as ground truth | REJECTED — schema describes valid XML shapes but not semantic intent; Word's interpretation of ambiguous schemas is what users observe |
| Pandoc / LibreOffice as ground truth | REJECTED — neither is a normative implementation; both make their own interpretive choices that may differ from Word |
| **Microsoft Word as ground truth** | **CHOSEN** — Word is the canonical author tool; ~99% of `.docx` files in the wild are produced or consumed by it; matching its behavior maximizes interop |
| Best-effort consensus across implementations | REJECTED — explosion of edge cases; lack of clear arbiter when implementations disagree |

**Rationale**: Avoids decisions-by-committee about "the right way" to express a Word edit in OOXML — defer to Microsoft's own implementation as oracle. Aligns with reality (we're not redefining OOXML). **Trust-boundary caveat**: this ADR does NOT mandate accepting Word's failure modes (e.g., Word silently dropping unrecognized namespaces is NOT a contract macdoc inherits). The "ground truth" applies to *intentional* semantics, not implementation bugs / fallbacks. Phase 2 implementation MUST add adversarial-input validation (path traversal in `r:id`, XXE in customXml, zip-slip in extracted parts) — Word's best-effort handling is not the spec.

### ADR-007: Conformance suite extension from NTPU thesis fixture

**Decision**: The existing `RealWorldDocxRoundTripSmokeTests` (NTPU thesis fixture, 5 preservation classes) is the foundation. This change adds:

- Property-based fully-faithful-functor tests under `EditAlgebraTests/FullyFaithfulFunctorTests.swift`
- Per-`OOXMLEdit` case CD-commute test (auto-generated from the CD's two paths per ADR-002)
- (Future, per ADR-007 follow-up) Corpus expansion to thesis + Zotero customXml + people.xml + commentsExtended fixtures
- (Future) Fuzz testing for `OOXMLEdit` argument-space corner cases

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| New synthetic minimal fixture (hand-crafted small `.docx`) | REJECTED — synthetic fixtures miss real-world OOXML quirks (vendor extensions, w14/w15 RSIDs, customXml) that motivate the canonical-identity contract |
| OOXML conformance test suite (ECMA-376 reference docs) | REJECTED — ECMA reference docs test schema validity, not edit-isomorphism; orthogonal goal |
| **NTPU thesis fixture + property-based tests** | **CHOSEN** — real-world fixture already used in RealWorldDocxRoundTripSmokeTests; 5 preservation classes already validated; property tests assert canonical-identity on randomized Edit inputs |
| Corpus expansion (multiple thesis + customXml + people.xml fixtures) | DEFERRED — Phase 2 follow-up; current change validates contract on one rich fixture before expanding |

**Scope of this change**: Property tests for 3–5 operations on the NTPU thesis fixture; corpus / fuzz expansion deferred to follow-up Spectra change.

### ADR-008: Migration path for word-builder-swift 0.9.0 → lens model (DEFERRED)

**Decision**: `word-builder-swift` 0.9.0 (write-only struct serialization) will migrate to a lens-model architecture in a dedicated follow-up Spectra change. The migration is BREAKING (callers must adapt from `Document(sections: [Section(paragraphs: [...])])` builder calls to lens-rooted edits).

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| Immediate breaking change in word-builder-swift 1.0.0 (no coexistence period) | REJECTED — too disruptive for existing #71 callers (che-word-mcp + macdoc CLI); migration window valuable |
| **Coexistence + deprecation cycle (LensDocument alongside Document)** | **CHOSEN** — gradual migration, downstream callers can opt-in per call-site |
| Keep struct-serialization permanently as alternative API | REJECTED — two parallel APIs create maintenance debt + violate single-source-of-truth principle for Edit semantics |
| Fork word-builder-swift into wb-lens (new package) | REJECTED — splits the ecosystem; existing #71 contributors / consumers split across forks |

**Documented path** (for the follow-up):

1. Add a `LensDocument` type alongside existing `Document` (coexistence period, ~3 months)
2. Migrate `Packer.toFile()` callers in `che-word-mcp` and `macdoc convert` to optionally use `LensDocument`
3. Deprecate the struct-serialization `Document` API
4. Remove deprecated paths in word-builder-swift 1.0.0

**This change does not implement any of the above**. Migration is its own Spectra change citing this foundation. Follow-up tracking issue: PsychQuant/macdoc#101.

### ADR-009: Downstream issue rerouting

**Decision**: `#92` (dxedit declarative CLI), `#88` (R-wordbuilder generator), `#90` (che-pptx-mcp) are **front-ends** for the architecture defined here, not parallel design efforts.

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| Continue all four threads (this foundation + #92 + #88 + #90) as independent parallel proposals | REJECTED — already proved problematic; PR #94 / #95 / #96 / #97 / #98 each surfaced spec gaps that boil down to "no shared Edit-type framing" |
| Cancel #92 / #88 / #90 and absorb them into this foundation's spec | REJECTED — over-bundling; each downstream has independent value as a front-end (different audience, different language ergonomics) |
| **Reroute via ADR-009: this foundation locks contract, downstreams become Layer 3 / 4 / specialized-to-PPTX front-ends** | **CHOSEN** — preserves each downstream's autonomy while ensuring they share the Edit-type contract |
| Foundation-first + downstream-later sequencing with explicit handoff issues | ADOPTED AS COMPLEMENT — see follow-up issues #102 / #103 / #104 / che-word-mcp#162 |

**Rationale**: Reframing as Layer 3 / 4 front-ends keeps each downstream's value proposition intact (dxedit is still a declarative CLI; R-wordbuilder still generates Swift from R) while making their contract surface (what they generate / consume) align with the foundation's Edit type.

| Issue | Layer | Status |
|---|---|---|
| #92 dxedit | Layer 3 (DSL) | YAML manifest compiles to `WordEdit` script; needs Layers 1–2 to land first; PR #94 blocked pending revision to align |
| #88 R-wordbuilder | Layer 4 (caller) | R generates `.swift` that uses `WordEdit`; PR #96 blocked pending revision to align (HIGH security findings on code injection should be reframed around safe `WordEdit` API surface) |
| #90 che-pptx-mcp | Layer 1–3 applied to PPTX | OOXMLEdit reusable; Word/Pptx specialization at Layer 1+; PR #95 blocked pending revision to align |

**Operational implication**: When these PRs are revised by Codex, the revisions SHALL reference `ooxml-edit-algebra` capability spec and frame their proposals as front-ends to this foundation. Re-framing is per-PR follow-up work, NOT scope of this change.

### Relationship to active changes

**`word-aligned-state-sync`** (active Spectra change in `openspec/changes/word-aligned-state-sync/`):

The active `word-aligned-state-sync` Decision 3 ("ID-based operations, never positional indices") is a **refinement** of this foundation's Edit-type contract, NOT a parallel design. After this change archives, `word-aligned-state-sync` should:

1. Cross-reference `ooxml-edit-algebra` capability spec in its design.md
2. Reframe Decision 3 as "Edit IDs are positional in OOXMLEdit lower-layer (`at: bodyChildIndex`), but expose stable IDs in WordEdit upper-layer for caller convenience"
3. Convert any positional-API spec Requirements (currently active) to Edit-type Requirements

This is documented coordination, not blocking. `word-aligned-state-sync` continues on its own apply schedule.

## Implementation Contract

**Behavior**:

- Callers can construct `OOXMLEdit` values, compose them via `∘`, and apply them to a `Document` to produce a new `Document` whose serialization satisfies canonical-identity (ADR-001).
- Callers can construct `WordEdit` values, call `.lower()` to obtain `[OOXMLEdit]`, and the resulting OOXMLEdit composition is functionally equivalent (same final Document) to applying the WordEdit directly. This is the fully-faithful-functor property.
- Property tests in `FullyFaithfulFunctorTests.swift` exercise this for 3–5 representative `OOXMLEdit` cases on the NTPU thesis fixture.

**Interface / data shape**:

- `Edit` protocol: declares `apply(to: Document) throws -> Document` + `lower() -> [OOXMLEdit]` (identity for OOXMLEdit cases)
- `OOXMLEdit` enum: cases for the 3–5 selected operations (insertParagraph, setBold, insertHyperlink, plus 2 selected during apply), each with relevant path / value associated values
- `WordEdit` enum: cases for the corresponding Word-UI verbs (applyBold, applyLink, applyInsertParagraph), each implementing `lower()` to return its `[OOXMLEdit]` translation
- `Document.apply(_ edit: any Edit) throws -> Document`: returns new Document with edit applied. Internally uses existing `Document.applyOverlay()` / `markDirty()` machinery — Edit is the public API wrapper.

**Failure modes**:

- `Edit.apply` throws `EditError.pathNotFound(path:)` when the target path doesn't exist in Document
- `Edit.apply` throws `EditError.preserveViolation(part:)` when the operation would cause a non-c14n-equal change to an unmodified subtree (defensive check; should not fire in well-formed Edits but guards against logic bugs)
- `WordEdit.lower()` is total — every WordEdit case has a defined OOXMLEdit translation. No partial functions.

**Acceptance criteria**:

1. `Edit.swift`, `OOXMLEdit.swift`, `WordEdit.swift` compile under `swift build` with no warnings
2. `FullyFaithfulFunctorTests` pass under `swift test --filter EditAlgebraTests` against the NTPU thesis fixture
3. Property test for each of the 3–5 operations passes 100 randomized inputs (default `swift-testing` `@Test(arguments:)` count)
4. CD diagram for each implemented `OOXMLEdit` case is included in this change's `design.md` (this section) or `tasks.md` (if format easier there) as ASCII ladder
5. `spectra validate ooxml-edit-isomorphism-foundation` passes
6. `Document.apply(_ edit:)` API is added without breaking existing `Document.applyOverlay()` / `markDirty()` API (existing callers continue compiling)

**Scope boundaries**:

- **In scope**: Edit type elevation, OOXMLEdit 3–5 cases, WordEdit corresponding cases, lower() implementations, property tests, CD diagrams, capability spec `ooxml-edit-algebra`, 9 ADRs in this design.md, coordination cross-reference in `word-aligned-state-sync` design.md.
- **Out of scope**: word-builder-swift lens migration, che-word-mcp boundary refactor, downstream PR (#94/#95/#96/#97/#98) revisions, automated CD validation tooling, full OOXMLEdit surface, module split implementation, corpus / fuzz test expansion beyond NTPU thesis fixture.

## Risks / Trade-offs

| Risk | Mitigation |
|---|---|
| **CD discipline onboarding cost** — new contributors will struggle to draw CDs for non-trivial Edits | ADR-002 includes 3+ worked examples (`applyBold`, `applyLink`, `applyInsertParagraph` boundary case); README in `EditAlgebra/` directory provides template |
| **Edit type performance regression** — naive allocation of Edit values per mutation could slow down large-document batch edits | Benchmark before/after on NTPU thesis fixture during apply; if regression >10%, address via inline-storage `inout` Edit handling before merge |
| **Naturality property is hard to enforce** — `WordEdit(a).lower() ∘ WordEdit(b).lower() == (WordEdit(a) ∘ WordEdit(b)).lower()` could silently break under range-crossing edge cases | Property test asserts naturality explicitly for each WordEdit pair; CI flags on violation |
| **`word-builder-swift` lens migration delayed indefinitely** — without forcing function, follow-up Spectra change may never happen | ADR-008's documented migration path is the forcing function; add a calendar reminder in the closing summary to revisit in 3 months |
| **#46 follow-up issues never opened** — without explicit task, the downstream rerouting (#92/#88/#90 re-frames) loops indefinitely | tasks.md includes explicit "Open follow-up issues for downstream re-framing" task |
| **Property tests over-rely on NTPU thesis fixture** — single fixture has known coverage gaps (no Zotero customXml, no people.xml in main fixture) | ADR-007 follow-up explicitly opens corpus expansion as separate Spectra change |
| **`word-aligned-state-sync` coordination conflict** — both changes describe the Edit-type contract; ordering matters | This change archives FIRST (decision-pinning has no implementation lock-in); `word-aligned-state-sync` refines after, with cross-reference |
| **Property test framework choice not pinned** — swift-testing vs XCTest property-based extensions | Use `swift-testing`'s `@Test(arguments:)` with `Array<String>.random` for property inputs; documented in tasks.md |

## Migration Plan

**This change has no user-facing migration**. The Edit type addition is additive — existing `Document.applyOverlay()` / `markDirty()` callers continue working unchanged.

**Downstream Spectra changes that DO require migration** (out of this change's scope, but documented for context):

1. **`word-builder-swift` lens migration** (per ADR-008) — separate Spectra change opening within 3 months of this foundation archive
2. **`che-word-mcp` boundary refactor** (per ADR-009) — separate Spectra change after #1 lands
3. **`#94/#95/#96/#97/#98` revisions** (per ADR-009) — Codex revisions per blocked PR, each citing this foundation

No tool / CI / config migration in this change's apply phase.
