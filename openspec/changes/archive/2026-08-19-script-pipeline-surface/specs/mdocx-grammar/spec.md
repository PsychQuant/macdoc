## ADDED Requirements

### Requirement: Render command rebuilds a document from a script

The `macdoc word render` command SHALL rebuild a `.docx` from an `.mdocx.swift` rebuild script by calling the shared transcode execution entry point. The command SHALL accept the script path as its argument and SHALL require a caller-supplied output path for the rebuilt document. The command SHALL accept a script named with either the dual-extension form or the bare `.mdocx` form, consistent with the dispatch behavior already required of `macdoc` CLI dispatch.

Byte-equal verification SHALL be opt-in: the command SHALL verify the rebuilt document against a reference document only when the caller names one, and SHALL NOT report any verification outcome when no reference is named.

Because `.docx` is a binary format, the rebuilt document SHALL be written to a file and SHALL NOT be written to standard output.

#### Scenario: Round trip from reverse to render is byte-equal

- **GIVEN** a script produced by running `macdoc word reverse` on a source document
- **WHEN** `macdoc word render` runs on that script with the source document named as the reference
- **THEN** the rebuilt document is written to the output path
- **AND** every XML part compares byte-equal to the source document
- **AND** the command exits with a success status

#### Scenario: Fully raw script still replays byte-equally

- **GIVEN** a source document whose coverage report shows a zero DSL ratio for every part
- **WHEN** that document is reversed to a script and the script is rendered with the source named as the reference
- **THEN** every XML part compares byte-equal to the source document

#### Scenario: Bare extension form is accepted

- **GIVEN** a rebuild script saved with the bare `.mdocx` filename form
- **WHEN** `macdoc word render` runs on that script
- **THEN** the script is dispatched as a Word-DSL script and the rebuilt document is written

#### Scenario: Rendering without a reference reports no verdict

- **WHEN** `macdoc word render` runs with no reference document named
- **THEN** the rebuilt document is written
- **AND** no verification outcome is reported
- **AND** the command exits with a success status

#### Scenario: Verification mismatch is reported and fails

- **GIVEN** a reference document that differs from what the script rebuilds
- **WHEN** `macdoc word render` runs with that reference named
- **THEN** the command names at least one differing part
- **AND** the command exits with a failure status

#### Scenario: Missing input is refused before any write

- **WHEN** `macdoc word render` is given a script path that does not exist, or a reference path that does not exist
- **THEN** the command reports the path that was not found
- **AND** no output document is written

#### Scenario: Existing output is protected

- **GIVEN** a file already present at the requested output path
- **WHEN** `macdoc word render` runs without an overwrite request
- **THEN** the command refuses and reports that the output file exists
- **AND** the existing file is left unmodified
