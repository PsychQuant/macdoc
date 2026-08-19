## ADDED Requirements

### Requirement: Script execution orchestration is a shared transcode entry point

The transcode module SHALL expose a public entry point that executes a `.mdocx.swift` rebuild script: parsing the script, replaying its operation log onto an empty authoring document, and writing the rebuilt package to a caller-supplied output path. When the caller supplies a reference document path, the entry point SHALL compare the rebuilt XML part set against that reference and report a verdict together with the paths of any parts that differ. When the caller supplies no reference, the returned verdict SHALL be absent rather than reported as a passing result.

Every consumer of script execution — command-line and MCP alike — SHALL call this entry point rather than reimplement the orchestration.

#### Scenario: Execution without a reference reports no verdict

- **WHEN** the entry point runs with no reference document supplied
- **THEN** the rebuilt document is written to the output path
- **AND** the result carries no verification verdict
- **AND** the result MUST NOT report an empty set of differing parts as evidence of byte equality

#### Scenario: Execution with a matching reference reports byte equality

- **GIVEN** a script exported from a reference document with no content substitution
- **WHEN** the entry point runs with that reference supplied
- **THEN** the result reports a passing verdict and names no differing parts

#### Scenario: Execution with a diverging reference names the differing parts

- **GIVEN** a script whose replay produces at least one part that differs from the reference
- **WHEN** the entry point runs with that reference supplied
- **THEN** the result reports a failing verdict
- **AND** the result names each differing part by its part path

#### Scenario: Unparseable script surfaces the transcoder reason

- **WHEN** the entry point is given a script that does not parse
- **THEN** the failure carries the transcoder's location-bearing reason rather than a generic parse failure

### Requirement: The reference document is read before any output is written

When a reference document is supplied, the script execution entry point SHALL read the reference document's parts into memory before writing anything to the output path.

This ordering is required because the caller MAY supply the same path as both output and reference. Reading the reference after writing the output would compare the rebuilt document against itself, reporting byte equality unconditionally and defeating verification.

#### Scenario: Output path and reference path are the same file

- **GIVEN** a caller that supplies one path as both the output and the reference
- **WHEN** the entry point runs
- **THEN** the verdict reflects a comparison against the file's contents as they were before the write
- **AND** the verdict MUST NOT be a passing result produced by comparing the rebuilt output against itself
