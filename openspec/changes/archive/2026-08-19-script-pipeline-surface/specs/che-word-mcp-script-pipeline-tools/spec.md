## MODIFIED Requirements

### Requirement: Script execution rebuilds with verifiable byte equality

che-word-mcp SHALL provide an `execute_script` tool that rebuilds a docx from a `.mdocx.swift` script by calling the shared transcode execution entry point defined in `ooxml-script-transcode`. The tool SHALL NOT reimplement the orchestration — parsing, replay, package writing, and part comparison all belong to that shared entry point, which is the same code the `macdoc word render` CLI command calls.

When the caller passes a reference docx path, the tool SHALL verify Stage-B byte equality of the rebuilt XML part set against the reference and return the verdict; on a false verdict the response SHALL name the broken parts. When the caller passes no reference, the response SHALL omit the verdict fields rather than report an empty broken-parts list. Script parse failures SHALL surface as MCP tool errors with the transcoder's location-bearing reason.

The MCP tool name `execute_script` and the CLI command name `macdoc word render` designate the same operation on two faces. The names differ because the MCP tool name is an established part of a published tool schema; the CLI name is the one already fixed by `mdocx-grammar`.

#### Scenario: Rebuild verifies byte-equal against the reference

- **GIVEN** a script exported from a reference docx with no content substitution
- **WHEN** `execute_script` runs with verification against that reference
- **THEN** the rebuilt docx is written and the response reports verified true with no broken parts

#### Scenario: Slot substitution through the MCP surface

- **GIVEN** a slotted script whose call-site argument was replaced with new text
- **WHEN** `execute_script` runs
- **THEN** the rebuilt docx carries the new text at the designated position and every non-slot XML part remains byte-equal to the reference

#### Scenario: Response shape is unchanged by the move to the shared entry point

- **GIVEN** any inputs accepted by `execute_script` before the orchestration was promoted to the shared transcode module
- **WHEN** `execute_script` runs on those inputs
- **THEN** the response carries the same fields and values as before the promotion
- **AND** the verdict fields remain absent when no reference is supplied

#### Scenario: CLI and MCP faces agree on the same script

- **GIVEN** one rebuild script and one reference document
- **WHEN** `execute_script` runs and `macdoc word render` runs on the same script with the same reference
- **THEN** both report the same verification verdict and the same set of differing parts
