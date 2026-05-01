## ADDED Requirements

### Requirement: Body-child mutation APIs expose body-child index semantics

`WordDocument` mutation APIs that target top-level document body positions SHALL expose parameter labels that include `bodyChildIndex` when the integer refers to `body.children`. Such APIs SHALL validate against the top-level body-child collection and SHALL NOT translate through a paragraph-only list.

#### Scenario: Body-child insert targets the table position

- **WHEN** a document body contains `[paragraph("A"), table, paragraph("B")]` and the caller inserts `paragraph("X")` at body child index `1`
- **THEN** the document body order SHALL become `[paragraph("A"), paragraph("X"), table, paragraph("B")]`

#### Scenario: Body-child update refuses non-paragraph targets

- **WHEN** a document body contains `[paragraph("A"), table, paragraph("B")]` and the caller updates a paragraph at body child index `1`
- **THEN** the operation SHALL throw an index or target-type error
- **AND** the operation SHALL NOT update `paragraph("B")`

### Requirement: Top-level paragraph mutation APIs expose paragraph-index semantics

`WordDocument` mutation APIs that intentionally target the nth top-level paragraph SHALL expose parameter labels that include `topLevelParagraphIndex` or `atParagraphIndex`. Such APIs SHALL translate only among top-level body paragraphs and SHALL NOT include table-cell paragraphs, header/footer paragraphs, footnote paragraphs, endnote paragraphs, or block-level content-control descendants.

#### Scenario: Top-level paragraph update skips tables but keeps index basis explicit

- **WHEN** a document body contains `[paragraph("A"), table, paragraph("B")]` and the caller updates top-level paragraph index `1` to `"C"`
- **THEN** the document body order SHALL become `[paragraph("A"), table, paragraph("C")]`

#### Scenario: Nested paragraph is not addressable by top-level paragraph index

- **WHEN** a document body contains `[paragraph("A"), table(cell paragraph "T"), paragraph("B")]`
- **THEN** top-level paragraph index `1` SHALL refer to `paragraph("B")`
- **AND** it SHALL NOT refer to the table-cell paragraph `"T"`

### Requirement: Ambiguous legacy index APIs preserve behavior during deprecation

Existing `WordDocument` APIs whose integer labels do not name the index basis SHALL NOT change runtime semantics in a minor release. They SHALL be marked deprecated with messages that name the replacement body-child or paragraph-index API.

#### Scenario: Deprecated paragraph-only update keeps existing behavior

- **WHEN** existing caller code invokes a deprecated paragraph-only API on `[paragraph("A"), table, paragraph("B")]` with index `1`
- **THEN** the minor-release runtime behavior SHALL keep targeting `paragraph("B")`
- **AND** recompilation SHALL emit a deprecation warning that names the explicit paragraph-index replacement

#### Scenario: Deprecated body-child insert names explicit replacement

- **WHEN** existing caller code invokes an ambiguous body-child insertion API with `at: 1`
- **THEN** recompilation SHALL emit a deprecation warning that names the explicit body-child replacement
- **AND** the minor-release runtime behavior SHALL keep inserting at body child index `1`

### Requirement: Recursive paragraph reads are not mutation indexes

Recursive paragraph read APIs such as `getParagraphs()` SHALL document that their returned order is a read-only content order and SHALL NOT be used as an index source for top-level body mutation APIs.

#### Scenario: Recursive read ordinal differs from body child index

- **WHEN** `getParagraphs()` returns `[paragraph("A"), table-cell paragraph("T"), paragraph("B")]` for a body containing `[paragraph("A"), table(cell paragraph "T"), paragraph("B")]`
- **THEN** recursive read ordinal `2` SHALL NOT be documented as the mutation index for `paragraph("B")`
- **AND** callers that need to mutate `paragraph("B")` SHALL use an explicit top-level paragraph-index API or an explicit body-child-index API
