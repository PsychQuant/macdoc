# ooxml-edit-algebra Specification

## Purpose

TBD - created by archiving change 'ooxml-edit-isomorphism-foundation'. Update Purpose after archive.

## Requirements

### Requirement: Canonical-Identity Round-Trip Contract

The `ooxml-swift` library SHALL guarantee that for any input `.docx` file `x` and any sequence of `Edit` operations `[e_1, e_2, ..., e_n]` applied via `Document.apply(_:)`, the resulting serialized output preserves the canonical-identity invariant: after XML canonicalization (c14n) of both input and output, every subtree NOT targeted by any `e_i` MUST be bytewise-equal in the c14n form.

The library SHALL NOT silently drop, reorder, or normalize XML content outside the targeted subtrees. This includes vendor extensions, comments, watermarks, custom styles, `customXml` parts (Zotero / Mendeley / EndNote), `people.xml`, `commentsExtended.xml`, embedded fonts, theme references, and any unrecognized OOXML namespace.

#### Scenario: Unmodified sectPr preserved through round-trip

- **WHEN** a `.docx` containing a `<w:sectPr>` element with multiple custom `<w:headerReference>` and `<w:footerReference>` children is parsed, no Edit operations are applied targeting `sectPr`, and the document is serialized
- **THEN** the c14n form of `sectPr` in the output is bytewise-equal to the c14n form in the input

##### Example: sectPr with header / footer references

- **GIVEN** input `.docx` whose `document.xml` contains `<w:sectPr><w:headerReference r:id="rId6" w:type="default"/><w:footerReference r:id="rId7" w:type="default"/><w:pgSz w:w="11906" w:h="16838"/></w:sectPr>`
- **WHEN** `Document.apply(_ : OOXMLEdit.insertParagraph(at: 0, content: ...))` is called and result serialized
- **THEN** c14n(output sectPr) equals c14n(input sectPr) byte-for-byte

#### Scenario: Vendor extensions preserved (Zotero customXml)

- **WHEN** a `.docx` with Zotero `customXml/item1.xml` is parsed and any `Edit` is applied that does NOT target the Zotero customXml part
- **THEN** the serialized output's `customXml/item1.xml` is c14n-equal to the input's

#### Scenario: Targeted subtree NOT bytewise-equal (intended modification)

- **WHEN** `OOXMLEdit.setBold(at: runPath, value: true)` is applied to a Run whose `rPr` does not contain `<w:b/>`
- **THEN** the output Run's `rPr` includes `<w:b/>` (NOT bytewise-equal to input — this is the intended modification)
- **AND** all sibling Runs NOT at `runPath` remain c14n-equal to their input forms


<!-- @trace
source: ooxml-edit-isomorphism-foundation
updated: 2026-07-06
code:
  - mcp/che-word-mcp
  - .github/prompts/spectra-drift.prompt.md
  - Package.resolved
  - .github/skills/spectra-drift/SKILL.md
-->

---
### Requirement: Edit Type Algebra

The `ooxml-swift` library SHALL provide an `Edit` protocol that declares:

1. `apply(to:) throws -> Document` — applies the Edit to a Document, returning a new Document
2. `lower() -> [OOXMLEdit]` — returns the syntactic-layer translation (identity for OOXMLEdit cases)

The library SHALL provide two concrete `Edit` conformances:

1. `OOXMLEdit` — syntactic-layer Edit, addressing OOXML elements by path
2. `WordEdit` — semantic-layer Edit, addressing Word-UI verbs

Edit values SHALL be composable: for any two Edits `a, b`, the composition `a ∘ b` is well-defined and its effect on a Document is equivalent to applying `a` then `b`. Composition SHALL be associative: `(a ∘ b) ∘ c == a ∘ (b ∘ c)`.

#### Scenario: OOXMLEdit composition is associative

- **WHEN** three OOXMLEdit values `e1`, `e2`, `e3` are composed in different parenthesizations
- **THEN** `(e1 ∘ e2) ∘ e3` and `e1 ∘ (e2 ∘ e3)` applied to the same Document produce bytewise-equal c14n output

##### Example: associativity on insertParagraph + setBold + insertHyperlink

- **GIVEN** Document `d` with a single empty paragraph
- **WHEN** `e1 = OOXMLEdit.insertParagraph(at: 0, content: "hello")`, `e2 = OOXMLEdit.setBold(at: ⟨first run⟩, value: true)`, `e3 = OOXMLEdit.insertHyperlink(at: ⟨first run⟩, href: "https://example.com")`
- **THEN** `((e1 ∘ e2) ∘ e3).apply(to: d)` and `(e1 ∘ (e2 ∘ e3)).apply(to: d)` produce documents whose c14n serializations are byte-equal

#### Scenario: WordEdit.lower() returns OOXMLEdit translation

- **WHEN** a `WordEdit.applyBold(range:)` value is created with a range that does NOT cross paragraph boundaries
- **THEN** `.lower()` returns a single-element `[OOXMLEdit.setBold(at: runPath, value: true)]` whose runPath corresponds to the range's containing Run

##### Example: applyBold within single paragraph

- **GIVEN** a Document with paragraph `[Run("Hello world")]`, and a range covering characters 0..5 ("Hello")
- **WHEN** `WordEdit.applyBold(range: 0..<5).lower()` is called
- **THEN** result is `[OOXMLEdit.splitRun(at: ⟨para 0, run 0⟩, splitOffset: 5), OOXMLEdit.setBold(at: ⟨para 0, run 0⟩, value: true)]`
- **AND** applying this OOXMLEdit list produces a Document whose first Run "Hello" has `<w:b/>` set and second Run " world" does not


<!-- @trace
source: ooxml-edit-isomorphism-foundation
updated: 2026-07-06
code:
  - mcp/che-word-mcp
  - .github/prompts/spectra-drift.prompt.md
  - Package.resolved
  - .github/skills/spectra-drift/SKILL.md
-->

---
### Requirement: Fully Faithful Functor Property (Naturality of lower)

The translation from `WordEdit` to `OOXMLEdit` via `lower()` SHALL preserve composition: for any two composable WordEdit values `a, b`, the following invariant MUST hold:

```
(a ∘ b).lower() == a.lower() ∘ b.lower()
```

where the right-hand `∘` denotes OOXMLEdit list concatenation (composition in the OOXMLEdit algebra).

This property is the fully-faithful-functor invariant that makes the two-layer algebra coherent. The `ooxml-swift` test suite SHALL include property-based tests asserting this invariant for every implemented `WordEdit` case.

#### Scenario: Naturality holds for applyBold + applyLink composition

- **WHEN** `a = WordEdit.applyBold(range: r1)` and `b = WordEdit.applyLink(range: r2, url: u)` are composed
- **THEN** `(a ∘ b).lower()` produces the same OOXMLEdit list (allowing reordering of independent operations) as `a.lower() ∘ b.lower()`
- **AND** applying both lists to the same Document yields c14n-equal outputs

#### Scenario: Range-crossing applyBold lowers to multiple OOXMLEdit cases

- **WHEN** `WordEdit.applyBold(range:)` is called with a range crossing a paragraph boundary
- **THEN** `.lower()` returns a list with one `OOXMLEdit.setBold` per affected paragraph, in document order


<!-- @trace
source: ooxml-edit-isomorphism-foundation
updated: 2026-07-06
code:
  - mcp/che-word-mcp
  - .github/prompts/spectra-drift.prompt.md
  - Package.resolved
  - .github/skills/spectra-drift/SKILL.md
-->

---
### Requirement: CD Review Discipline for Edit Cases

Every PR introducing a new `OOXMLEdit` or `WordEdit` enum case SHALL include a commutative diagram (ASCII ladder, IETF-RFC style) demonstrating the case's commute property. The diagram SHALL show:

1. The Word UI action that the Edit case corresponds to (for WordEdit) or the OOXML schema change (for OOXMLEdit)
2. The `τ` translation between Word UI semantics and Swift representation
3. The commutativity claim: applying the Edit on the Word side commutes with applying the corresponding Edit on the Swift side under `τ`

The PR reviewer SHALL reject PRs that introduce new Edit cases without the CD diagram. Reviewers SHALL verify that the CD diagram's commute claim is justified (either by inspection or by attached property test).

CD diagrams in this codebase SHALL use the ASCII format shown in `design.md` §Decisions/ADR-002. They are normative documentation for the Edit case, not optional commentary.

#### Scenario: PR introducing OOXMLEdit case without CD diagram is rejected

- **WHEN** a PR adds a new `OOXMLEdit.insertTable` enum case but the PR description / files do NOT include a CD diagram for the case
- **THEN** the PR reviewer SHALL request changes citing this Requirement
- **AND** the PR SHALL NOT be merged until a CD diagram is attached

#### Scenario: PR with CD diagram passes review

- **WHEN** a PR adds `OOXMLEdit.insertTable` and includes an ASCII ladder CD diagram showing the Word UI "Insert → Table" action commutes with the schema-level `<w:tbl>` insertion under `τ`
- **THEN** the PR meets this Requirement's documentation criteria


<!-- @trace
source: ooxml-edit-isomorphism-foundation
updated: 2026-07-06
code:
  - mcp/che-word-mcp
  - .github/prompts/spectra-drift.prompt.md
  - Package.resolved
  - .github/skills/spectra-drift/SKILL.md
-->

---
### Requirement: Edit Apply Surface on Document

The `Document` type SHALL expose `Document.apply(_ edit: any Edit) throws -> Document`, which applies the Edit and returns a new Document instance. This method SHALL:

1. Delegate internally to the existing `Document.applyOverlay()` / `markDirty()` machinery shipped in v0.13.0+ (NO replacement of the existing overlay-save infrastructure)
2. Return a new Document instance (immutable apply — input Document is unchanged)
3. Throw `EditError.pathNotFound(path:)` if the Edit's target path does not exist in the input Document
4. Throw `EditError.preserveViolation(part:)` if the Edit would cause a non-c14n-equal change to a subtree NOT in the Edit's target path

The existing `Document.applyOverlay()` and `Document.markDirty()` APIs SHALL continue to function unchanged for backward compatibility.

#### Scenario: apply returns new Document instance

- **WHEN** `let d2 = try d1.apply(OOXMLEdit.setBold(at: runPath, value: true))`
- **THEN** `d2` is a new Document with the edit applied, `d1` is unchanged

#### Scenario: apply throws on path not found

- **WHEN** `OOXMLEdit.setBold(at: runPath, value: true)` is applied to a Document where `runPath` does not resolve
- **THEN** `apply` throws `EditError.pathNotFound(path: runPath)`

#### Scenario: apply throws on preserve violation (defensive)

- **WHEN** a buggy Edit implementation attempts to modify an unmodified subtree
- **THEN** `apply`'s internal canonical-identity check throws `EditError.preserveViolation(part: ⟨affected part⟩)` before serialization completes


<!-- @trace
source: ooxml-edit-isomorphism-foundation
updated: 2026-07-06
code:
  - mcp/che-word-mcp
  - .github/prompts/spectra-drift.prompt.md
  - Package.resolved
  - .github/skills/spectra-drift/SKILL.md
-->

---
### Requirement: Word UI Behavior as Ground Truth for WordEdit Semantics

For each `WordEdit` case, the case's semantics SHALL be specified by reference to the corresponding Microsoft Word UI action. Ambiguities in OOXML output for that action SHALL be resolved by inspecting Word's own behavior (e.g., saving the document after the user action and inspecting the resulting OOXML diff).

WordEdit cases SHALL NOT define semantics that diverge from Word's UI implementation. If Word's implementation has multiple modes (e.g., Cmd-B with vs. without selection), each mode SHALL be a separate WordEdit case or a parameter on the case.

The `design.md` ADR-006 records the "Word UI as ground truth" methodology and worked examples.

#### Scenario: applyBold semantics match Cmd-B

- **WHEN** `WordEdit.applyBold(range: r)` is applied to a Document
- **AND** Microsoft Word is opened on the same input Document, the same range `r` is selected, and Cmd-B is pressed and saved
- **THEN** the OOXML diff between Word's saved file and the input is c14n-equivalent to the diff between `WordEdit.applyBold(range: r).apply(...)` and the input

#### Scenario: applyBold semantics for empty range

- **WHEN** `WordEdit.applyBold(range:)` is called with an empty range (insertion point with no selection)
- **THEN** the WordEdit case SHALL document the corresponding Word behavior (toggle bold for next-typed character) explicitly OR throw a defined error
- **AND** the case SHALL NOT silently no-op without documentation


<!-- @trace
source: ooxml-edit-isomorphism-foundation
updated: 2026-07-06
code:
  - mcp/che-word-mcp
  - .github/prompts/spectra-drift.prompt.md
  - Package.resolved
  - .github/skills/spectra-drift/SKILL.md
-->

---
### Requirement: Property-Based Functor Tests on NTPU Thesis Fixture

The `ooxml-swift` test suite SHALL include property-based tests under `Tests/EditAlgebraTests/FullyFaithfulFunctorTests.swift` that exercise the fully-faithful-functor invariant for at least 3 implemented `OOXMLEdit` cases. The tests SHALL use the existing NTPU thesis fixture from `RealWorldDocxRoundTripSmokeTests` as the input Document.

Each property test SHALL:

1. Generate randomized arguments for the Edit case (within valid input domain)
2. Apply the Edit, then assert canonical-identity for unmodified subtrees
3. For `WordEdit` cases, additionally assert naturality of `lower()` (per `Fully Faithful Functor Property` Requirement)

The Apply phase of this Spectra change SHALL select 3–5 specific `OOXMLEdit` cases for property-test coverage. The choice SHALL be recorded in `tasks.md` and SHALL include at minimum: `insertParagraph`, `setBold`, `insertHyperlink`.

#### Scenario: Property test passes 100 randomized inputs for setBold

- **WHEN** the property test for `OOXMLEdit.setBold(at: runPath, value: Bool)` is executed
- **THEN** for 100 randomized `runPath` values within the NTPU thesis fixture's Run set, AND for both `value: true` and `value: false`, the canonical-identity invariant holds (unmodified subtrees c14n-equal to input)

#### Scenario: Property test detects regression in canonical-identity

- **WHEN** a regression is introduced where `OOXMLEdit.setBold` accidentally modifies a sibling Run's `rPr`
- **THEN** the property test SHALL fail with an assertion message identifying which c14n-comparison failed


<!-- @trace
source: ooxml-edit-isomorphism-foundation
updated: 2026-07-06
code:
  - mcp/che-word-mcp
  - .github/prompts/spectra-drift.prompt.md
  - Package.resolved
  - .github/skills/spectra-drift/SKILL.md
-->

---
### Requirement: Downstream Architectural Compliance Documentation

The `ooxml-edit-algebra` capability spec SHALL be referenced by all downstream Spectra changes that depend on the Edit-type contract. Specifically:

1. `word-aligned-state-sync` design.md SHALL include a "Relationship to ooxml-edit-isomorphism-foundation" section cross-referencing this capability
2. Future `word-builder-swift` lens-migration Spectra change SHALL cite ADR-008 of this design.md
3. Future `che-word-mcp` boundary-refactor Spectra change SHALL cite ADR-009 of this design.md
4. Revisions to blocked PRs #94, #95, #96, #97, #98 SHALL reframe their proposals as front-ends to this foundation

The downstream compliance is an ADVISORY scope of this Requirement — this Requirement SHALL NOT block this change's apply phase, but SHALL be documented as the expected operational coordination for the cluster.

#### Scenario: word-aligned-state-sync archives without cross-reference

- **WHEN** `word-aligned-state-sync` is being archived AND its design.md does NOT cross-reference this capability
- **THEN** the archival reviewer SHALL request the cross-reference addition before archive

#### Scenario: Future Spectra change cites ADR-008 for lens migration

- **WHEN** a future Spectra change proposing the `word-builder-swift` lens migration is opened
- **THEN** its proposal.md SHALL include text similar to "Per ADR-008 of `ooxml-edit-isomorphism-foundation`, this change implements the deferred lens-model migration"

<!-- @trace
source: ooxml-edit-isomorphism-foundation
updated: 2026-07-06
code:
  - mcp/che-word-mcp
  - .github/prompts/spectra-drift.prompt.md
  - Package.resolved
  - .github/skills/spectra-drift/SKILL.md
-->