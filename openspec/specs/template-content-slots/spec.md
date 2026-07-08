# template-content-slots Specification

## Purpose

TBD - created by archiving change 'format-alignment-engine'. Update Purpose after archive.

## Requirements

### Requirement: Strict template mode via named content slots

A rebuild script SHALL be parameterizable with named content slots: the reverse pipeline, given slot designations (paragraph ids or style-based selectors), SHALL emit a script whose designated content positions accept caller-provided values while every non-slot byte of the rebuild remains as extracted. Executing a slotted script with new content SHALL produce a docx whose formatting (all five layers) matches the reference and whose slot positions carry the new content.

#### Scenario: title and body slots

- **GIVEN** a reference whose first paragraph is designated slot `title` and body paragraphs slot `body`
- **WHEN** the slotted script executes with title "新計畫紀錄" and body text
- **THEN** the output docx carries the new text in those positions with the reference's fonts, spacing, alignment, and section layout intact


<!-- @trace
source: format-alignment-engine
updated: 2026-07-08
code:
  - mcp/che-word-mcp
-->

---
### Requirement: Slot designation is explicit in strict mode

Strict mode SHALL NOT infer slots. Slot designation comes from explicit user input (CLI flags or a slot manifest). Undesignated content is rebuilt verbatim. Inferred designation (structural-role deduction) is out of scope for this capability.

#### Scenario: no designation means full verbatim rebuild

- **WHEN** a script is produced without any slot designation
- **THEN** executing it reproduces the reference byte-equal (Stage B) with no substitution points

<!-- @trace
source: format-alignment-engine
updated: 2026-07-08
code:
  - mcp/che-word-mcp
-->