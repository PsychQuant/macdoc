## ADDED Requirements

### Requirement: The workflow states what a failed run leaves behind

The swiftify workflow SHALL state that a run whose verification fails publishes nothing: a document already at the output path is left as it was, and no document appears where none existed. The workflow SHALL NOT present verification as a check performed on an already-published document.

The workflow SHALL state that rendering onto a path that already holds a file requires an explicit overwrite request on both faces, naming the command-line flag and the MCP parameter that carry it. Because the workflow's own template-filling sequence renders repeatedly to the same output path, the workflow SHALL show that request in the sequence rather than leaving the operator to discover the refusal.

#### Scenario: Operator re-renders after editing a slot value

- **GIVEN** an operator following the template-filling sequence who has already rendered once to a given output path
- **WHEN** the operator edits a slot value and renders again to that same path
- **THEN** the workflow has told the operator that this run requires an explicit overwrite request
- **AND** the workflow does not present the second run as succeeding without one

#### Scenario: Operator reads what a failed verification costs

- **WHEN** the operator consults the workflow about verifying against a reference
- **THEN** the workflow states that a failing verification leaves the output path unchanged
- **AND** the workflow does not describe the rebuilt document as written before verification is reported

#### Scenario: Operator distinguishes a failed verification from an unverified run

- **WHEN** the operator runs execution through the MCP face without naming a reference
- **THEN** the workflow states that the response omits the verdict fields, and that their absence is not a pass
- **AND** the workflow states that a failing verification arrives as a tool error rather than as a response field to inspect
