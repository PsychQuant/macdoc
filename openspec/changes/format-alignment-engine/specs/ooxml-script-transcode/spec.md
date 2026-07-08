## ADDED Requirements

### Requirement: All-parts raw channel

The rebuild script SHALL be able to carry every XML part of the source package verbatim: sibling parts (styles.xml, settings.xml, theme, fontTable, numbering, headers/footers, rels, [Content_Types].xml, …) ride the script through a raw part channel that preserves their bytes exactly. Executing the script SHALL emit each carried part byte-equal. The raw channel is the byte-equality floor of the dual-track contract (`format-alignment-pipeline`); parts later upgraded to typed DSL leave the raw channel only when byte equality is preserved.

#### Scenario: sibling part round-trips verbatim

- **GIVEN** a source docx whose styles.xml contains 16 styles with docDefaults and latentStyles
- **WHEN** the script produced by word reverse executes
- **THEN** the rebuilt styles.xml is byte-equal to the source

### Requirement: DSL-form coverage measurement

The transcoder SHALL measure and report DSL-form coverage: for each XML part, the byte count rebuilt through typed DSL projection versus the raw channel, and the aggregate percentage across all parts. The measurement SHALL be exposed programmatically (for tests and baselines) and via `macdoc word reverse --coverage` output.

#### Scenario: baseline report

- **WHEN** word reverse runs with coverage reporting on a paragraphs-only extraction
- **THEN** the report lists per-part DSL/raw byte splits and the aggregate percentage, and records which content classes remain on the raw channel

### Requirement: Reverse extraction covers the five format layers

Reverse engineering SHALL extract, in DSL form where byte equality permits: run-level formatting (fonts including eastAsia, size, underline, color, vertical alignment), paragraph-level formatting (spacing, indentation, alignment, numbering reference), section-level properties (page size, margins, orientation, columns, headers/footers references), and table structure — in addition to the already-shipped text + styleId extraction. Structural-role inference is explicitly out of scope (strict mode only).

#### Scenario: CJK run formatting survives the DSL channel

- **GIVEN** a source run with eastAsia font ＭＳ ゴシック and size 21 half-points
- **WHEN** run-level extraction is upgraded to the DSL channel and the script re-executes
- **THEN** the rebuilt run's rPr is byte-equal to the source

#### Scenario: two-column section round-trips

- **GIVEN** a source with a second section carrying `w:cols num="2"`
- **WHEN** section extraction lands and the script re-executes
- **THEN** the rebuilt sectPr is byte-equal and the visual-diff harness confirms the two-column layout
