## ADDED Requirements

### Requirement: Script export rides the CLI's code path

che-word-mcp SHALL provide an `export_script` tool that converts a docx to a full-fidelity `.mdocx.swift` rebuild script by calling the same ooxml-swift transcoder entry points the macdoc CLI uses (ReverseExtractor, ScriptExporter) — the MCP layer SHALL NOT reimplement any transcode logic. The tool SHALL accept optional slot designations (array of {name, para_id}); strict-mode designation failures SHALL surface as MCP tool errors carrying the underlying transcode error description. The script SHALL be written to the caller-supplied output path; the response carries a summary (DSL-channel parts, form-gap emptiness, slot count), never the script text inline.

#### Scenario: Export is byte-identical to the CLI

- **GIVEN** a real Word docx and identical inputs (same source, same slot designations)
- **WHEN** `export_script` runs and the macdoc CLI word-reverse runs on the same source
- **THEN** the two produced `.mdocx.swift` files are byte-identical

#### Scenario: Strict slot failure surfaces as a tool error

- **WHEN** `export_script` is called with a slot naming a paragraph id that does not exist in the document
- **THEN** the tool returns an MCP error whose message contains the transcoder's slot-designation failure reason, and no script file is written

### Requirement: Coverage report matches the CLI numbers

che-word-mcp SHALL provide a `get_script_coverage` tool returning the dual-track coverage of a docx: one row per XML part (part path, channel `dsl` or `raw`, byte count, DSL ratio in [0,1]) plus the aggregate ratio, computed by the same coverage APIs as the CLI coverage report.

#### Scenario: JPA template coverage parity

- **GIVEN** the real JPA template (env-gated fixture)
- **WHEN** `get_script_coverage` runs on it
- **THEN** word/document.xml reports channel `dsl` with ratio 1.0 and the aggregate matches the CLI-reported aggregate for the same file

### Requirement: Script execution rebuilds with verifiable byte equality

che-word-mcp SHALL provide an `execute_script` tool that parses a `.mdocx.swift` script (ScriptImporter), replays it onto an empty authoring document, and writes the rebuilt docx to the caller-supplied output path. When the caller passes a reference docx path, the tool SHALL verify Stage-B byte equality of the rebuilt XML part set against the reference and return the verdict; on a false verdict the response SHALL name the broken parts. Script parse failures SHALL surface as MCP tool errors with the transcoder's location-bearing reason.

#### Scenario: Rebuild verifies byte-equal against the reference

- **GIVEN** a script exported from a reference docx with no content substitution
- **WHEN** `execute_script` runs with verification against that reference
- **THEN** the rebuilt docx is written and the response reports verified true with no broken parts

#### Scenario: Slot substitution through the MCP surface

- **GIVEN** a slotted script whose call-site argument was replaced with new text
- **WHEN** `execute_script` runs
- **THEN** the rebuilt docx carries the new text at the designated position and every non-slot XML part remains byte-equal to the reference

### Requirement: Two-layer parity guard

The test suite SHALL guard MCP/CLI parity at two layers. Layer 1 (ungated, CI-runnable): an in-process test SHALL run export → execute through the MCP handler functions on a synthetic authoring-built docx and assert Stage-B byte equality of the rebuilt part set. Layer 2 (gated): when both the real-template fixture gate and a macdoc CLI binary are available, a test SHALL run the same source through the MCP handlers and the CLI and assert the exported scripts and rebuilt part sets are byte-identical; without either gate it SHALL skip loudly naming the missing gate.

#### Scenario: Ungated parity always runs

- **WHEN** the suite runs with no environment gates set
- **THEN** the Layer-1 parity test executes (not skipped) and passes only if the rebuilt part set is byte-equal to its reference

#### Scenario: Gated cross-check skips loudly

- **WHEN** the Layer-2 test runs without the macdoc binary path configured
- **THEN** it reports a skip naming the missing gate rather than passing or failing silently
