## ADDED Requirements

### Requirement: Text-output route coverage

The E2E test suite SHALL test every conversion route that produces text output to stdout. Each test SHALL verify exit code 0 and that stdout contains expected content substrings.

#### Scenario: docx to md

- **WHEN** `macdoc convert --to md <fixture.docx>` is run
- **THEN** exit code is 0 and stdout contains the document text in markdown format

#### Scenario: docx to html

- **WHEN** `macdoc convert --to html <fixture.docx>` is run
- **THEN** exit code is 0 and stdout contains HTML markup

#### Scenario: html to md

- **WHEN** `macdoc convert --to md <fixture.html>` is run
- **THEN** exit code is 0 and stdout contains markdown text

#### Scenario: md to html

- **WHEN** `macdoc convert --to html <fixture.md>` is run
- **THEN** exit code is 0 and stdout contains HTML markup

#### Scenario: srt to html

- **WHEN** `macdoc convert --to html <fixture.srt>` is run
- **THEN** exit code is 0 and stdout contains HTML with speaker detection spans

#### Scenario: bib to html

- **WHEN** `macdoc convert --to html <fixture.bib>` is run
- **THEN** exit code is 0 and stdout contains APA-formatted HTML references

#### Scenario: bib to md

- **WHEN** `macdoc convert --to md <fixture.bib>` is run
- **THEN** exit code is 0 and stdout contains APA-formatted markdown references

#### Scenario: bib to json

- **WHEN** `macdoc convert --to json <fixture.bib>` is run
- **THEN** exit code is 0 and stdout contains valid JSON

#### Scenario: pdf to md

- **WHEN** `macdoc convert --to md <fixture.pdf>` is run
- **THEN** exit code is 0 (content verification is lenient due to PDFKit variability)

### Requirement: Binary-output route coverage

The E2E test suite SHALL test conversion routes that produce binary output (.docx) by verifying the output file exists and is non-empty.

#### Scenario: html to docx

- **WHEN** `macdoc convert --to docx <fixture.html> --output <temp.docx>` is run
- **THEN** exit code is 0 and the output file exists with size > 0

#### Scenario: md to docx

- **WHEN** `macdoc convert --to docx <fixture.md> --output <temp.docx>` is run
- **THEN** exit code is 0 and the output file exists with size > 0

#### Scenario: pdf to docx

- **WHEN** `macdoc convert --to docx <fixture.pdf> --output <temp.docx>` is run
- **THEN** exit code is 0 and the output file exists with size > 0

#### Scenario: tex to docx

- **WHEN** `macdoc convert --to docx <fixture.tex> --output <temp.docx>` is run
- **THEN** exit code is 0 and the output file exists with size > 0

### Requirement: Flag combination coverage

The E2E test suite SHALL test key flag combinations on applicable routes.

#### Scenario: --full flag on html output

- **WHEN** `macdoc convert --to html <fixture.md> --full` is run
- **THEN** stdout contains `<!DOCTYPE html>` and `<html`

#### Scenario: --css flag on srt to html

- **WHEN** `macdoc convert --to html <fixture.srt> --css dark` is run
- **THEN** stdout contains CSS rules for dark theme

#### Scenario: --frontmatter flag on docx to md

- **WHEN** `macdoc convert --to md <fixture.docx> --frontmatter` is run
- **THEN** stdout starts with `---` YAML frontmatter block

#### Scenario: --output flag writes to file

- **WHEN** `macdoc convert --to md <fixture.docx> --output <temp.md>` is run
- **THEN** the output file exists and contains the markdown content

### Requirement: Error handling coverage

The E2E test suite SHALL test error cases and verify non-zero exit codes with appropriate error messages.

#### Scenario: Missing input file

- **WHEN** `macdoc convert --to md /nonexistent/file.docx` is run
- **THEN** exit code is non-zero and stderr contains error text

#### Scenario: Unsupported format pair

- **WHEN** `macdoc convert --to pdf <fixture.md>` is run (unsupported route)
- **THEN** exit code is non-zero and stderr contains error text
