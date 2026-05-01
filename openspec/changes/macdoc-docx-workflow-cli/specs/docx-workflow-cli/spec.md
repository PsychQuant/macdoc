## ADDED Requirements

### Requirement: Integrated docx command namespace

The system SHALL expose a `docx` subcommand under the existing `macdoc` executable. The namespace SHALL include `build`, `patch`, `apply`, `plan`, `verify`, and `diff` subcommands. The system SHALL NOT require a separate `dxedit` executable for Phase 1 workflows.

#### Scenario: List docx subcommands

- **WHEN** the user runs `macdoc docx --help`
- **THEN** the help output lists `build`, `patch`, `apply`, `plan`, `verify`, and `diff`

#### Scenario: No separate executable requirement

- **WHEN** a Phase 1 workflow is documented or tested
- **THEN** the command starts with `macdoc docx` and does not require `dxedit`

### Requirement: Importable workflow library boundary

The system SHALL keep manifest decoding, path resolution, operation planning, execution, verification, and structural diffing in an importable Swift library target named `DocxWorkflowLib`. The `MacDocCLI` target SHALL only parse command-line arguments, call `DocxWorkflowLib`, print results, and map thrown errors to non-zero exits.

#### Scenario: Library APIs are testable without CLI process execution

- **WHEN** `DocxWorkflowLibTests` import `DocxWorkflowLib`
- **THEN** tests instantiate manifest, planner, executor, verifier, and differ types without launching the `macdoc` executable

#### Scenario: CLI delegates workflow execution

- **WHEN** a CLI smoke test invokes `macdoc docx apply input.docx manifest.json --output output.docx`
- **THEN** the CLI routes parsed arguments into `DocxWorkflowLib` and does not duplicate manifest execution logic in the CLI target

### Requirement: JSON Codable manifest contract

The system SHALL accept JSON manifests decoded through Swift Codable types. A manifest SHALL include `schemaVersion` and `workflow`. `workflow` SHALL be one of `build`, `patch`, or `apply`. A manifest SHALL contain ordered `steps`; verification checks SHALL be represented as an ordered `checks` array when verification is requested. CLI arguments SHALL override `input`, `template`, and `output` path fields from the manifest during path resolution.

#### Scenario: Valid apply manifest decodes

- **WHEN** the user provides a JSON manifest with `schemaVersion: 1`, `workflow: "apply"`, one `replaceText` step, and one `containsText` check
- **THEN** the system decodes the manifest into `DocxManifest` and preserves the step and check order

##### Example: apply manifest

```json
{
  "schemaVersion": 1,
  "workflow": "apply",
  "input": "input.docx",
  "output": "output.docx",
  "steps": [
    { "op": "replaceText", "find": "{{advisor}}", "with": "Dr. Chen", "scope": "body" }
  ],
  "checks": [
    { "type": "containsText", "text": "Dr. Chen" },
    { "type": "notContainsText", "text": "{{advisor}}" }
  ]
}
```

#### Scenario: Invalid manifest fails before document write

- **WHEN** the manifest is not valid JSON, omits `schemaVersion`, omits `workflow`, uses an unknown workflow, or contains an unknown step operation
- **THEN** the system returns a typed validation error and does not create or overwrite an output `.docx` file

#### Scenario: CLI path overrides are reflected in the plan

- **WHEN** the manifest declares `output: "manifest-output.docx"` and the user passes `--output cli-output.docx`
- **THEN** the effective operation plan records `cli-output.docx` as the output path

### Requirement: Build workflow creates new documents

The `build` workflow SHALL start from an empty document model and write a new `.docx` file from declarative manifest content. The workflow SHALL support sections containing paragraphs and tables in Phase 1. Paragraph content SHALL support plain text runs and basic run properties that map to the existing Word builder model.

#### Scenario: Build a document from manifest content

- **WHEN** the user runs `macdoc docx build build.json --output built.docx` and `build.json` contains one section with one paragraph containing `Hello from macdoc`
- **THEN** the system writes `built.docx`
- **AND** OOXML readback of `built.docx` contains `Hello from macdoc`

#### Scenario: Build rejects source document arguments

- **WHEN** the user runs `macdoc docx build build.json --input existing.docx --output built.docx`
- **THEN** the system returns a validation error because `build` does not mutate a source document

### Requirement: Patch workflow fills template placeholders

The `patch` workflow SHALL read a template `.docx`, resolve explicit placeholders, apply manifest-provided replacements, and write a separate output `.docx` file by default. Supported placeholder anchors SHALL include literal text tokens in the form `{{name}}`. A placeholder that matches zero locations SHALL fail. A placeholder that matches more than one location SHALL fail unless the manifest explicitly declares replacement of all matches for that placeholder.

#### Scenario: Patch a single placeholder

- **WHEN** the user runs `macdoc docx patch template.docx patch.json --output patched.docx` and `template.docx` contains `Advisor: {{advisor}}`
- **THEN** the system writes `patched.docx`
- **AND** OOXML readback contains `Advisor: Dr. Chen`
- **AND** OOXML readback does not contain `{{advisor}}`

#### Scenario: Duplicate placeholder fails without all-matches opt-in

- **WHEN** the template contains two `{{advisor}}` placeholders and the manifest replacement does not declare all-matches replacement
- **THEN** the system returns an anchor ambiguity error and does not write the output document

### Requirement: Apply workflow mutates existing documents through ordered steps

The `apply` workflow SHALL read an existing `.docx`, execute ordered manifest steps, and write a separate output `.docx` file by default. Phase 1 SHALL support `replaceText`, `insertParagraphAfterText`, and `insertImageAfterText` operations when their anchors resolve exactly according to the step options. The workflow SHALL preserve unchanged parts through the underlying OOXML writer rather than rebuilding the document from scratch.

#### Scenario: Apply ordered replacement and insertion

- **WHEN** the user runs `macdoc docx apply input.docx apply.json --output edited.docx` and the manifest first replaces `{{status}}` with `Approved` and then inserts a paragraph after `Approved`
- **THEN** OOXML readback of `edited.docx` shows `Approved` before the inserted paragraph text

#### Scenario: Apply fails on missing anchor

- **WHEN** an `insertParagraphAfterText` step targets an anchor text that does not exist in the source document
- **THEN** the system returns an anchor resolution error and does not write the output document

### Requirement: Plan reports deterministic operations without writing output

The `plan` command SHALL decode the manifest, resolve effective input/template/output paths, resolve anchors when a source or template document is involved, and print the ordered operations that execution would run. The `plan` command SHALL NOT write an output `.docx` file.

#### Scenario: Plan an apply workflow

- **WHEN** the user runs `macdoc docx plan apply.json --input input.docx --output edited.docx`
- **THEN** stdout contains the workflow, effective input path, effective output path, ordered step identifiers, resolved anchor counts, and planned operation count
- **AND** `edited.docx` is not created

#### Scenario: Plan fails on invalid manifest

- **WHEN** the user runs `macdoc docx plan invalid.json`
- **THEN** the command exits non-zero and prints the manifest validation error

### Requirement: Verify enforces manifest checks by OOXML readback

The `verify` command SHALL read the output `.docx` and enforce manifest-declared checks. Phase 1 checks SHALL include `containsText`, `notContainsText`, `replacementCount`, and `readbackSucceeds`. Verification SHALL exit zero only when every check passes.

#### Scenario: Verify successful edit

- **WHEN** the user runs `macdoc docx verify edited.docx --manifest apply.json` and `edited.docx` contains every required text, lacks every forbidden text, matches the expected replacement count, and can be read back
- **THEN** the command exits zero and prints a passed check summary

#### Scenario: Verify reports failed checks

- **WHEN** the manifest requires `containsText: "Approved"` and the output document does not contain `Approved`
- **THEN** the command exits non-zero and prints the failing check identifier

### Requirement: Diff reports Word-aware document changes

The `diff` command SHALL compare two `.docx` files using OOXML readback summaries rather than raw zip bytes. Phase 1 output SHALL include paragraph text additions and removals, table count changes, image relationship count changes, and field or equation count changes when the reader exposes those counts.

#### Scenario: Diff text changes

- **WHEN** the user runs `macdoc docx diff before.docx after.docx` and `after.docx` replaces `Pending` with `Approved`
- **THEN** stdout reports removal of `Pending` and addition of `Approved`

#### Scenario: Diff ignores archive byte ordering noise

- **WHEN** two `.docx` files have the same readback text and structure summary but different zip entry ordering
- **THEN** `macdoc docx diff` reports no semantic changes

### Requirement: Safe output write behaviour

The system SHALL write to a separate output path by default. The system SHALL fail before writing when manifest validation, path resolution, planning, anchor resolution, or source readback fails. The system SHALL only overwrite an existing output file when the user passes an explicit overwrite option.

#### Scenario: Existing output requires overwrite option

- **WHEN** `edited.docx` already exists and the user runs `macdoc docx apply input.docx apply.json --output edited.docx` without the overwrite option
- **THEN** the command exits non-zero and leaves `edited.docx` unchanged

#### Scenario: Planning failure leaves output absent

- **WHEN** execution fails because a manifest anchor is missing
- **THEN** the requested output path does not exist after the command exits

##### Example: missing anchor during apply

- **GIVEN** `input.docx` contains `Status: Pending`
- **AND** `apply.json` inserts a paragraph after anchor text `Status: Approved`
- **WHEN** the user runs `macdoc docx apply input.docx apply.json --output edited.docx`
- **THEN** the command exits non-zero
- **AND** `edited.docx` does not exist

### Requirement: Synthetic fixture policy for docx workflow tests

The system SHALL test docx workflow behaviour using synthetic fixtures created in tests or committed minimal fixtures that contain no private thesis, manuscript, advisor-review, client, or personal document content.

#### Scenario: Tests build fixtures programmatically

- **WHEN** a unit test needs a source `.docx` with a placeholder, a paragraph, a table, or an image relationship
- **THEN** the test creates the fixture programmatically or uses a minimal committed fixture with synthetic text

#### Scenario: Private fixtures are rejected

- **WHEN** a proposed test fixture contains private thesis, manuscript, advisor-review, client, or personal content
- **THEN** the fixture is out of scope for the docx workflow test suite

##### Example: rejected private fixture

- **GIVEN** a proposed fixture file is named `advisor-review-real-manuscript.docx`
- **AND** its paragraphs contain a real student name, advisor comments, or manuscript content
- **WHEN** the fixture is proposed for DocxWorkflowLibTests
- **THEN** the fixture is rejected from the repository test suite
