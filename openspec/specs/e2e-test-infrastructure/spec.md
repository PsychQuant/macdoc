# e2e-test-infrastructure Specification

## Purpose

Test harness for running macdoc CLI as a subprocess — fixture management, Process wrapper, output assertion helpers.

## Requirements

### Requirement: Test target in Package.swift

The root Package.swift SHALL include a test target `MacDocCLITests` with access to test fixtures and the compiled binary path.

#### Scenario: Test target builds

- **WHEN** `swift test` is run in the macdoc root directory
- **THEN** the `MacDocCLITests` target compiles and test discovery finds all E2E tests


<!-- @trace
source: add-e2e-tests
updated: 2026-03-21
code:
  - Package.swift
-->

---
### Requirement: CLI process runner

The test harness SHALL provide a helper function that runs the `macdoc` binary as a subprocess, captures stdout, stderr, and exit code, and returns them as a structured result.

#### Scenario: Successful command execution

- **WHEN** the helper runs `macdoc convert --to md <valid.docx>`
- **THEN** it returns exit code 0, stdout containing the markdown output, and empty stderr

#### Scenario: Failed command execution

- **WHEN** the helper runs `macdoc convert --to md <nonexistent.docx>`
- **THEN** it returns a non-zero exit code and stderr containing an error message


<!-- @trace
source: add-e2e-tests
updated: 2026-03-21
code:
  - Tests/MacDocCLITests/CLITestHelper.swift
-->

---
### Requirement: Programmatic fixture generation

The test harness SHALL generate minimal valid test fixtures programmatically at test setup time. Fixtures SHALL NOT be committed as binary files in the repository.

#### Scenario: DOCX fixture creation

- **WHEN** the test suite starts
- **THEN** a minimal valid .docx file is created in a temporary directory using OOXMLSwift DocxWriter

#### Scenario: Text-based fixture creation

- **WHEN** the test suite starts
- **THEN** minimal .md, .html, .srt, .bib, and .tex files are written to a temporary directory

#### Scenario: Fixture cleanup

- **WHEN** the test suite completes
- **THEN** all temporary fixture files and output files are removed


<!-- @trace
source: add-e2e-tests
updated: 2026-03-21
code:
  - Tests/MacDocCLITests/FixtureManager.swift
-->

---
### Requirement: Output assertion helpers

The test harness SHALL provide assertion helpers for verifying CLI output: `assertContains(output, substring)`, `assertExitSuccess(result)`, `assertExitFailure(result)`, `assertFileExists(path)`.

#### Scenario: Substring assertion

- **WHEN** a test asserts that stdout contains "# Heading"
- **THEN** the assertion passes if the substring is present and fails with a descriptive message if not

<!-- @trace
source: add-e2e-tests
updated: 2026-03-21
code:
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Tests/MacDocCLITests/ConvertRouteTests.swift
-->