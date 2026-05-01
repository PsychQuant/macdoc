# ooxml-library-design-principles Specification

## Purpose

Defines the design principles that govern `ooxml-swift` mutator APIs. These principles require operations to prefer informative refusal over incorrect approximation, to avoid implicit destructive changes, and to match what a human Word user would consider semantically correct rather than merely producing structurally valid OOXML.

## Requirements

### Requirement: Correctness primacy — refusal over incorrect approximation

When the `ooxml-swift` library cannot perform an operation correctly, it MUST refuse the operation rather than perform an incorrect approximation. The bar for "correct" is human-like correctness — what a human Word user would consider semantically equivalent to the requested intent — NOT just structurally valid OOXML output. Any operation whose output, while structurally legal per the OOXML schema, would surprise a human Word user familiar with the source document SHALL be rejected at design time.

#### Scenario: Refusal preferred over structurally valid but semantically incorrect output

- **WHEN** an operation could produce structurally valid OOXML that would not match human user intent (e.g., text mutation that fragments a logical sentence, output that contains visible artifacts no human would create)
- **THEN** the operation SHALL refuse with an informative result type
- **AND** the operation SHALL NOT produce the structurally-valid-but-semantically-incorrect output

##### Example: Refuse cross-OMML text mutation
- **GIVEN** paragraph contains `<w:r><w:t>see </w:t></w:r><m:oMath>δ</m:oMath><w:r><w:t> here</w:t></w:r>`
- **WHEN** caller requests replacement of "see  here" (substring spanning across the OMML element) with "alt text"
- **THEN** the library SHALL refuse with informative result indicating OMML boundary intersection
- **AND** the library SHALL NOT emit `<w:r><w:t>alt</w:t></w:r><m:oMath>δ</m:oMath><w:r><w:t> text</w:t></w:r>` (structurally valid but produces visible artifact "altδ text" no human would create)

#### Scenario: Approximation rejected at design time

- **WHEN** a proposed mutator design would, in any code path, produce output that is structurally valid OOXML but semantically incorrect under human-user expectations
- **THEN** the design SHALL be rejected and an alternative design (refusal, escape hatch with explicit caller opt-in, or scope reduction) SHALL be selected
- **AND** the rejection rationale SHALL be recorded in the change's `design.md` Decisions section


<!-- @trace
source: flatten-replace-omml-bilateral-coverage
updated: 2026-05-01
-->

---
### Requirement: Human-like operations — no surprising state, no silent destruction

`ooxml-swift` library operations MUST correspond to actions a human Word user would consciously perform. Operations that would produce intermediate document state no human user would create, OR that perform destructive changes (data loss, structure deletion, semantic alteration) without explicit caller opt-in, SHALL be rejected at design time. Destructive operations MAY be implemented when the caller explicitly opts in via a parameter that names the destructive intent.

#### Scenario: Implicit destruction rejected

- **WHEN** an operation would silently delete a typed structural element (e.g., equation, image, table, content control) as a side effect of an unrelated text mutation
- **THEN** the operation SHALL refuse to perform the destruction without explicit caller opt-in
- **AND** the operation result SHALL signal the destruction would have occurred

#### Scenario: Explicit-destructive operations permitted via opt-in parameter

- **WHEN** a caller explicitly opts in to a destructive operation via a named parameter (e.g., a future `omml_handling: "drop"` parameter)
- **THEN** the library MAY perform the destruction
- **AND** the parameter name SHALL describe the destructive intent (NOT a generic boolean like `force`)
- **AND** the parameter MUST default to the non-destructive (refuse) behavior when omitted

##### Example: Default refusal vs explicit opt-in
- **GIVEN** a hypothetical `replace_text(find:, with:, omml_handling:)` API
- **WHEN** caller invokes `replace_text(find: "eq δ here", with: "ref X")` without `omml_handling`
- **THEN** the library SHALL refuse if the match crosses OMML (default behavior)
- **WHEN** caller invokes `replace_text(find: "eq δ here", with: "ref X", omml_handling: "drop")`
- **THEN** the library MAY perform the replacement and delete the OMML element (explicit opt-in)
- **AND** the result SHALL signal the destruction occurred (count + deleted-element info)

#### Scenario: Surprising intermediate state rejected

- **WHEN** an operation would produce a document state where the visible content (per `flattenedDisplayText` or equivalent reading API) does NOT match what a human user editing the source document in Microsoft Word would create through any sequence of conscious editing actions
- **THEN** the operation SHALL refuse to produce that state
- **AND** an alternative result (refusal, partial completion with informative result, or rejection at design time) SHALL be returned


<!-- @trace
source: flatten-replace-omml-bilateral-coverage
updated: 2026-05-01
-->

---
### Requirement: Principles govern all current and future ooxml-swift mutators

The two principles (Correctness primacy, Human-like operations) SHALL apply to every mutator API in `ooxml-swift` — including but not limited to: text replacement, element insertion, element deletion, formatting changes, structural modifications (table cell merges, content control wrapping, etc.), and any future mutator. New mutator changes SHALL document principle conformance in the change's `design.md` Decisions section. Existing mutators that violate the principles SHALL be flagged as bugs and tracked for fix.

#### Scenario: New mutator change documents principle conformance

- **WHEN** a Spectra change introducing a new mutator API or modifying an existing one is created
- **THEN** the change's `design.md` SHALL include a Decisions entry that explicitly evaluates the proposed design against both principles
- **AND** the entry SHALL state for each principle whether conformance holds, and if not, what alternative was selected

#### Scenario: Principle violation in existing mutator becomes a tracked bug

- **WHEN** an existing `ooxml-swift` mutator API is found to produce structurally valid but semantically incorrect output, OR to perform implicit destruction without caller opt-in
- **THEN** the violation SHALL be filed as a bug issue in the `ooxml-swift` repository
- **AND** the issue SHALL reference the violated principle by name (Correctness primacy or Human-like operations)
- **AND** the fix SHALL be tracked through the standard IDD or Spectra workflow

#### Scenario: Principle conflict requires explicit resolution in design.md

- **WHEN** a proposed design satisfies one principle but appears to conflict with the other (e.g., correctness requires producing surprising state, or human-like operations require structurally invalid output)
- **THEN** the change's `design.md` Decisions section SHALL document the conflict explicitly
- **AND** SHALL select a resolution (typically: scope reduction, refuse-as-default with explicit opt-in, or deferring the operation to a future change)
- **AND** SHALL NOT silently violate either principle

<!-- @trace
source: flatten-replace-omml-bilateral-coverage
updated: 2026-05-01
-->
