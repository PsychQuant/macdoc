# swiftify-workflow Specification

## Purpose

TBD - created by archiving change 'script-pipeline-surface'. Update Purpose after archive.

## Requirements

### Requirement: Coverage check precedes expectation of readable output

The swiftify workflow SHALL instruct the operator to obtain a dual-track coverage report for a document before drawing any conclusion about whether its exported script is human-readable. The workflow SHALL state that DSL upgrade is decided per XML part on an all-or-nothing basis, and that a document whose main part falls to the raw channel yields a script that replays byte-equally but MUST NOT be presented as readable or hand-editable source.

#### Scenario: Table-bearing document reports zero DSL coverage

- **GIVEN** a Word document containing at least one table
- **WHEN** the operator requests a coverage report for that document
- **THEN** the main document part reports the raw channel with a DSL ratio of zero
- **AND** the workflow directs the operator to treat the exported script as a byte-equal archive rather than readable source

#### Scenario: Operator asks whether a script can be edited by hand

- **WHEN** the operator has an exported script and has not obtained a coverage report
- **THEN** the workflow directs the operator to obtain the coverage report first
- **AND** the workflow SHALL NOT promise readable output on the basis of the document being small or simple


<!-- @trace
source: script-pipeline-surface
updated: 2026-08-19
code:
  - .agents/skills/spectra-analyze/SKILL.md
  - .agents/skills/spectra-commit/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-ask/SKILL.md
  - .agents/skills/spectra-debug/SKILL.md
  - .agents/skills/spectra-drift/SKILL.md
  - mcp/che-keynote-mcp/
  - .agents/skills/spectra-audit/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - .codex/hooks.json
  - .agents/skills/spectra-verify/SKILL.md
  - .agents/skills/spectra-archive/SKILL.md
  - .agents/skills/umbrella-open/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
-->

---
### Requirement: The workflow states its fidelity guarantee and its non-promise

The swiftify workflow SHALL state that its guarantee is byte-equal replay, verifiable against a reference document, and that readable Swift output is not guaranteed for any input. The workflow SHALL NOT describe readable output as the expected result with raw-channel output as an exception.

#### Scenario: Operator seeks a reproducible document mutation pipeline

- **WHEN** the operator wants a mutation that can be replayed and verified
- **THEN** the workflow presents export, optional slot substitution, render, and verification as the supported loop
- **AND** the workflow states that version-control diffing of a raw-channel script is not usable, because each part occupies a single escaped line


<!-- @trace
source: script-pipeline-surface
updated: 2026-08-19
code:
  - .agents/skills/spectra-analyze/SKILL.md
  - .agents/skills/spectra-commit/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-ask/SKILL.md
  - .agents/skills/spectra-debug/SKILL.md
  - .agents/skills/spectra-drift/SKILL.md
  - mcp/che-keynote-mcp/
  - .agents/skills/spectra-audit/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - .codex/hooks.json
  - .agents/skills/spectra-verify/SKILL.md
  - .agents/skills/spectra-archive/SKILL.md
  - .agents/skills/umbrella-open/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
-->

---
### Requirement: The workflow covers the complete round trip on both faces

The swiftify workflow SHALL document the loop from source document to rebuilt document, naming for each step both the command-line entry point and the MCP tool that perform it, so that an operator on either face can complete the loop.

#### Scenario: Operator completes a round trip from the command line

- **WHEN** the operator follows the workflow using command-line entry points only
- **THEN** the workflow names an export step, a coverage step, a render step, and a verification option
- **AND** each named step corresponds to a command that exists

#### Scenario: Operator completes a round trip through MCP tools

- **WHEN** the operator follows the workflow using MCP tools only
- **THEN** the workflow names the export, coverage, and execution tools
- **AND** the workflow states which operation carries a different name on each face

<!-- @trace
source: script-pipeline-surface
updated: 2026-08-19
code:
  - .agents/skills/spectra-analyze/SKILL.md
  - .agents/skills/spectra-commit/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-ask/SKILL.md
  - .agents/skills/spectra-debug/SKILL.md
  - .agents/skills/spectra-drift/SKILL.md
  - mcp/che-keynote-mcp/
  - .agents/skills/spectra-audit/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - .codex/hooks.json
  - .agents/skills/spectra-verify/SKILL.md
  - .agents/skills/spectra-archive/SKILL.md
  - .agents/skills/umbrella-open/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
-->