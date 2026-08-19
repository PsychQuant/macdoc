## MODIFIED Requirements

### Requirement: Script execution rebuilds with verifiable byte equality

che-word-mcp SHALL provide an `execute_script` tool that rebuilds a docx from a `.mdocx.swift` script by calling the shared transcode execution entry point defined in `ooxml-script-transcode`. The tool SHALL NOT reimplement the orchestration — parsing, replay, package writing, part comparison, the overwrite gate, and the decision to publish or discard the rebuilt package all belong to that shared entry point, which is the same code the `macdoc word render` CLI command calls.

When the caller passes a reference docx path, the tool SHALL verify Stage-B byte equality of the rebuilt XML part set against the reference. A passing verdict SHALL be returned in a successful response. **A failing verdict SHALL be reported as a tool error, not as a successful response carrying a false verdict**, and the error SHALL name each differing part. When the caller passes no reference, the response SHALL omit the verdict fields rather than report an empty broken-parts list.

The tool SHALL accept a boolean overwrite parameter that defaults to refusing. When a file already exists at the output path and the caller has not set that parameter, the tool SHALL fail, name the existing path, and leave that file unmodified. The tool SHALL NOT carry its own overwrite check; the parameter SHALL be passed through to the shared entry point.

The response SHALL omit the written-path key when the shared entry point published nothing, in the same manner it already omits the verdict keys when no reference was supplied.

Script parse failures SHALL surface as MCP tool errors with the transcoder's location-bearing reason.

The MCP tool name `execute_script` and the CLI command name `macdoc word render` designate the same operation on two faces. The names differ because the MCP tool name is an established part of a published tool schema; the CLI name is the one already fixed by `mdocx-grammar`.

#### Scenario: Rebuild verifies byte-equal against the reference

- **GIVEN** a script exported from a reference docx with no content substitution
- **WHEN** `execute_script` runs with verification against that reference
- **THEN** the rebuilt docx is written and the response reports verified true with no broken parts

#### Scenario: Failed verification is reported as a tool error

- **GIVEN** a script whose rebuild differs from the supplied reference
- **WHEN** `execute_script` runs with verification against that reference
- **THEN** the call is reported as an error rather than as a success
- **AND** the error text names each differing part
- **AND** nothing is published at the output path

##### Example: a caller that only checks call success

- **GIVEN** a caller that treats any non-error response as a successful rebuild
- **AND** a script that rebuilds a document differing from the reference in `word/document.xml`
- **WHEN** `execute_script` runs with that reference
- **THEN** the caller observes an error, not a success
- **AND** the error text contains `word/document.xml`

#### Scenario: Existing output is refused without an explicit overwrite request

- **GIVEN** a file already present at the requested output path
- **WHEN** `execute_script` runs without the overwrite parameter set
- **THEN** the call is reported as an error naming the existing path
- **AND** that file is byte-identical to what it was before the call

#### Scenario: Slot substitution through the MCP surface

- **GIVEN** a slotted script whose call-site argument was replaced with new text
- **WHEN** `execute_script` runs
- **THEN** the rebuilt docx carries the new text at the designated position and every non-slot XML part remains byte-equal to the reference

#### Scenario: Absent fields continue to mean the operation did not happen

- **WHEN** `execute_script` runs with no reference supplied
- **THEN** the response omits the verdict fields
- **AND** a caller MUST NOT read their absence as a passing verification
- **AND** the response names the written path, because a document was published

#### Scenario: CLI and MCP faces agree on the same script

- **GIVEN** one rebuild script and one reference document
- **WHEN** `execute_script` runs and `macdoc word render` runs on the same script with the same reference
- **THEN** both report the same verification verdict and the same set of differing parts
- **AND** both signal failure when the verdict fails
- **AND** both refuse an existing output path when overwrite was not requested
