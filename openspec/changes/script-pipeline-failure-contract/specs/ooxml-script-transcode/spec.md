## MODIFIED Requirements

### Requirement: Script execution orchestration is a shared transcode entry point

The transcode module SHALL expose a public entry point that executes a `.mdocx.swift` rebuild script: parsing the script, replaying its operation log onto an empty authoring document, and placing the rebuilt package at a caller-supplied output path. When the caller supplies a reference document path, the entry point SHALL compare the rebuilt XML part set against that reference and report a verdict together with the paths of any parts that differ. When the caller supplies no reference, the returned verdict SHALL be absent rather than reported as a passing result.

The entry point SHALL refuse to overwrite an existing file at the output path unless the caller explicitly permits overwriting. The refusal SHALL happen before the replay is performed. This gate SHALL live in the entry point itself, and a consumer of the entry point SHALL NOT carry an equivalent gate of its own.

The entry point SHALL write the rebuilt package to a temporary location inside the same directory as the output path, and SHALL place that package at the output path only when verification passes or when no verification was requested. When verification fails, the entry point SHALL leave the output path exactly as it found it and SHALL remove the temporary package.

The result SHALL name a written path only when a document was placed at the output path. When nothing was placed, the written path SHALL be absent rather than naming a path that was not written.

Every consumer of script execution — command-line and MCP alike — SHALL call this entry point rather than reimplement the orchestration.

#### Scenario: Execution without a reference reports no verdict

- **WHEN** the entry point runs with no reference document supplied
- **THEN** the rebuilt document is placed at the output path
- **AND** the result names that output path as written
- **AND** the result carries no verification verdict
- **AND** the result MUST NOT report an empty set of differing parts as evidence of byte equality

#### Scenario: Execution with a matching reference reports byte equality

- **GIVEN** a script exported from a reference document with no content substitution
- **WHEN** the entry point runs with that reference supplied
- **THEN** the result reports a passing verdict and names no differing parts
- **AND** the result names the output path as written

#### Scenario: Execution with a diverging reference names the differing parts

- **GIVEN** a script whose replay produces at least one part that differs from the reference
- **WHEN** the entry point runs with that reference supplied
- **THEN** the result reports a failing verdict
- **AND** the result names each differing part by its part path
- **AND** the result names no written path

#### Scenario: Failed verification leaves an existing output file unmodified

- **GIVEN** a file already present at the output path, and a caller permitting overwrite
- **AND** a script whose replay diverges from the supplied reference
- **WHEN** the entry point runs
- **THEN** the file at the output path is byte-identical to what it was before the run

##### Example: existing output survives a failed verification

- **GIVEN** the output path holds a document whose bytes hash to H before the run
- **AND** the script rebuilds a document that differs from the reference in `word/document.xml`
- **WHEN** the entry point runs with overwrite permitted and that reference supplied
- **THEN** the verdict fails and names `word/document.xml`
- **AND** the bytes at the output path still hash to H

#### Scenario: Failed verification creates no file where none existed

- **GIVEN** no file present at the output path
- **AND** a script whose replay diverges from the supplied reference
- **WHEN** the entry point runs
- **THEN** the verdict fails
- **AND** no file exists at the output path afterwards
- **AND** no temporary package is left in the output directory

#### Scenario: Existing output is refused before the replay

- **GIVEN** a file already present at the output path
- **WHEN** the entry point runs without the caller permitting overwrite
- **THEN** the run fails and names the output path
- **AND** the file at the output path is unmodified
- **AND** the script is not replayed

#### Scenario: Unparseable script surfaces the transcoder reason

- **WHEN** the entry point is given a script that does not parse
- **THEN** the failure carries the transcoder's location-bearing reason rather than a generic parse failure
- **AND** nothing is written to the output path

### Requirement: The reference document is read before any output is written

When a reference document is supplied, the script execution entry point SHALL read the reference document's parts into memory before writing anything to the output path.

This ordering is required because the caller MAY supply the same path as both output and reference. Reading the reference after writing the output would compare the rebuilt document against itself, reporting byte equality unconditionally and defeating verification.

Because that path already holds a file, supplying one path as both output and reference SHALL require the caller to permit overwriting, on the same terms as any other pre-existing output.

#### Scenario: Output path and reference path are the same file

- **GIVEN** a caller that supplies one path as both the output and the reference, and permits overwriting
- **WHEN** the entry point runs
- **THEN** the verdict reflects a comparison against the file's contents as they were before the write
- **AND** the verdict MUST NOT be a passing result produced by comparing the rebuilt output against itself

#### Scenario: Same output and reference path without overwrite permission is refused

- **GIVEN** a caller that supplies one path as both the output and the reference
- **WHEN** the entry point runs without the caller permitting overwriting
- **THEN** the run fails and names that path
- **AND** the file at that path is unmodified
