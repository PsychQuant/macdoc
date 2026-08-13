## ADDED Requirements

### Requirement: Compiled Markdown OMath route coverage

The compiled E2E suite SHALL exercise `macdoc convert` through the production command parser for default literal mode, opt-in inline OMath, opt-in display OMath, invalid math values, incompatible routes, and formula failures. Binary-output assertions SHALL inspect `word/document.xml`, not only destination existence.

#### Scenario: Default CLI mode remains literal

- **WHEN** the compiled binary runs `macdoc convert --to docx <math.md> --output <out.docx>` for source `Before $x^2$ after`
- **THEN** exit code is 0
- **AND** `word/document.xml` contains literal `$x^2$` and no `<m:oMath`

#### Scenario: OMath CLI mode emits inline and display carriers

- **WHEN** the compiled binary runs `macdoc convert --to docx <math.md> --math omath --output <out.docx>` for a fixture containing one inline and one display formula
- **THEN** exit code is 0 and stdout is empty
- **AND** `word/document.xml` contains one inline `<m:oMath>` plus one `<m:oMathPara>` with a nested `<m:oMath>`
- **AND** the standard Office Math namespace is bound

#### Scenario: Invalid math value is rejected

- **WHEN** the compiled binary runs with `--math unknown`
- **THEN** exit code is non-zero and stdout is empty
- **AND** stderr identifies the invalid `--math` value
- **AND** the destination is not created

#### Scenario: OMath mode is rejected on an incompatible route

- **WHEN** the compiled binary runs `macdoc convert --to html <fixture.md> --math omath`
- **THEN** exit code is non-zero and stdout contains no converted document
- **AND** stderr states that OMath mode is available only for Markdown-to-DOCX

#### Scenario: Formula failure preserves existing CLI destination

- **GIVEN** an existing output file containing sentinel bytes `KEEP`
- **WHEN** the compiled binary converts Markdown containing `$\\overbrace{x}$` with `--math omath` to that output path
- **THEN** exit code is non-zero and stdout is empty
- **AND** the output file remains byte-identical to `KEEP`

#### Scenario: Literal flag is accepted explicitly

- **WHEN** the compiled binary runs a Markdown-to-DOCX conversion with `--math literal`
- **THEN** exit code is 0 and delimiters remain literal Word text
