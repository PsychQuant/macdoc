# che-word-mcp-insertion-tools Specification — script-variant-anchor-matching delta

## ADDED Requirements

### Requirement: Insertion text anchors expose math-script-insensitive matching as an opt-in match option

The che-word-mcp insertion tools that accept text anchors SHALL expose a `match_options` object with a boolean `math_script_insensitive` field. Omitted `match_options` and omitted `math_script_insensitive` SHALL behave as `false`.

The option SHALL apply only to text-anchor resolution for `after_text` and `before_text`. It SHALL NOT change paragraph-index anchors, table-cell anchors, image/table anchors, inserted content, or success response wording.

The initial scoped tools are:

| Tool | Scoped anchors |
|---|---|
| `insert_paragraph` | `after_text`, `before_text` |
| `insert_equation` display mode | `after_text`, `before_text` |
| `insert_image_from_path` | `after_text`, `before_text` |
| `insert_caption` | `after_text`, `before_text` |

#### Scenario: Schema exposes match_options on insertion tools

- **WHEN** `tools/list` is requested
- **THEN** each scoped insertion tool schema includes `match_options.math_script_insensitive`
- **AND** the schema describes the default as exact matching

#### Scenario: Omitted match_options keeps exact matching

- **GIVEN** a document paragraph whose flattened text contains `"H0"`
- **WHEN** `insert_paragraph({ doc_id, text: "note", after_text: "H₀" })` is called without `match_options`
- **THEN** the tool follows the existing exact matching behavior and reports text not found

#### Scenario: Enabled option matches Unicode subscript anchor to ASCII flattened text

- **GIVEN** a document paragraph whose flattened text contains `"H0"`
- **WHEN** `insert_paragraph({ doc_id, text: "note", after_text: "H₀", match_options: { math_script_insensitive: true } })` is called
- **THEN** the tool inserts after the matched paragraph

#### Scenario: Enabled option matches ASCII anchor to Unicode subscript text

- **GIVEN** a document paragraph whose flattened text contains `"H₀"`
- **WHEN** `insert_caption({ doc_id, label: "Equation", caption_text: "Null hypothesis", after_text: "H0", match_options: { math_script_insensitive: true } })` is called
- **THEN** the caption is inserted after the matched paragraph

#### Scenario: Option does not affect non-text anchors

- **WHEN** `insert_image_from_path({ doc_id, path, index: 0, match_options: { math_script_insensitive: true } })` is called
- **THEN** the `index` anchor behavior is unchanged

---

### Requirement: MCP match_options MUST thread through the shared OOXML anchor lookup option

che-word-mcp SHALL parse `match_options.math_script_insensitive` into the shared OOXMLSwift anchor lookup option rather than implementing per-tool Unicode replacement in the MCP layer.

Direct Mode and Session Mode SHALL use the same parser and matching semantics.

#### Scenario: Direct Mode and Session Mode agree

- **GIVEN** the same document content and the same `after_text: "H₀"` request with `match_options.math_script_insensitive: true`
- **WHEN** the insertion is run once with `source_path` Direct Mode and once with `doc_id` Session Mode
- **THEN** both modes resolve the same target paragraph

#### Scenario: Invalid match_options type is rejected by existing schema validation

- **WHEN** a caller passes `match_options` as a non-object value
- **THEN** the request is rejected consistently with existing MCP schema/type validation behavior
- **AND** the server does not silently reinterpret the invalid value as enabled matching
