## ADDED Requirements

### Requirement: The workflow routes filled forms to normalization by paragraph kind

The swiftify workflow SHALL document an optional form-normalization step after render. It SHALL tell the operator to obtain paragraph kinds (from `macdoc word form classify` or from the notes printed by `macdoc word reverse --slot`) and SHALL map each kind to the `macdoc word form apply` option that handles it: `table-field` to `--field` (with `--field-size`), `checkbox-line` to `--checkbox-font`, `list-checkbox` to `--tick-list`, and `body` to `--insert-after` when more paragraphs are needed. It SHALL state that instruction paragraphs are removed only by naming them with `--remove`, that `--truncate-from` drops unrelated trailing content, that normalization runs on the rendered output so the script's byte-equal verification is unaffected, and that the MCP face does not offer these operations.

#### Scenario: Operator fills a table-dense official form

- **WHEN** the operator follows the workflow to fill a form whose fields sit in table cells
- **THEN** the workflow names the classify step, the render step, and a `macdoc word form apply` invocation with `--field` for the filled cells
- **AND** the workflow states that `--verify-against` applies to the script before normalization, not to the normalized output

#### Scenario: Operator looks for the hint-line kind

- **WHEN** the operator wants to drop instruction lines such as notes to the applicant
- **THEN** the workflow states that these lines have no kind of their own and are removed with `--remove <paraId>`
