## ADDED Requirements

### Requirement: list_numbering_definitions enumerates abstractNum and num pairs

The MCP tool `list_numbering_definitions` SHALL return every `<w:abstractNum>` definition and every `<w:num>` instance present in the target document's `numbering.xml`.

The tool SHALL accept either `doc_id` (session mode) or `source_path` (direct mode).

Each entry SHALL include: `num_id`, `abstract_num_id`, `levels` (array of level descriptors with `ilvl`, `num_format`, `lvl_text`, `start`).

#### Scenario: Document with two num definitions

- **GIVEN** a document with abstractNum 0 (decimal 9-level) referenced by num 1, and abstractNum 1 (bullet 9-level) referenced by num 2
- **WHEN** the tool is invoked
- **THEN** the response contains two num entries, each with their levels array populated

### Requirement: get_numbering_definition fetches one num by id

The MCP tool `get_numbering_definition` SHALL accept `doc_id` + `num_id` and return the same shape as one entry from `list_numbering_definitions`.

If `num_id` does not exist, the tool SHALL return error `not_found` with the queried num_id echoed.

#### Scenario: Lookup by num_id

- **WHEN** the tool is invoked with `num_id: 5` against a document containing num 5
- **THEN** the response includes the abstract_num_id, levels, and any lvlOverrides for num 5

### Requirement: create_numbering_definition adds a new abstractNum and num

The MCP tool `create_numbering_definition` SHALL accept `doc_id` + `levels: [LevelDef]` and create a new `<w:abstractNum>` paired with a new `<w:num>` in numbering.xml.

`LevelDef` includes: `ilvl: int`, `num_format: string` (one of `decimal` / `bullet` / `lowerLetter` / `upperLetter` / `lowerRoman` / `upperRoman` / `ordinal` / `cardinalText` / `decimalZero`), `lvl_text: string` (e.g., `"%1."` or `"%1.%2"`), `start: int` (default 1).

The tool SHALL return the new `num_id`.

The tool SHALL return error `invalid_levels` when `levels` is empty or contains more than 9 entries.

#### Scenario: Create 3-level decimal numbering

- **WHEN** the tool is invoked with `levels: [{ilvl: 0, num_format: "decimal", lvl_text: "%1.", start: 1}, {ilvl: 1, num_format: "decimal", lvl_text: "%1.%2.", start: 1}, {ilvl: 2, num_format: "decimal", lvl_text: "%1.%2.%3.", start: 1}]`
- **THEN** the response includes the new num_id
- **AND** numbering.xml contains the new abstractNum with 3 levels and a paired num referencing it

### Requirement: override_numbering_level sets level start value

The MCP tool `override_numbering_level` SHALL accept `doc_id` + `num_id` + `ilvl` + `start_value` and add `<w:lvlOverride w:ilvl="ilvl"><w:startOverride w:val="start_value"/></w:lvlOverride>` to the target num.

The tool SHALL return error `not_found` when num_id does not exist.

#### Scenario: Override level 0 to start at 5

- **WHEN** the tool is invoked with `num_id: 1, ilvl: 0, start_value: 5`
- **THEN** num 1's XML contains `<w:lvlOverride w:ilvl="0"><w:startOverride w:val="5"/></w:lvlOverride>`

### Requirement: assign_numbering_to_paragraph attaches numId to paragraph

The MCP tool `assign_numbering_to_paragraph` SHALL accept `doc_id` + `paragraph_index` + `num_id` + `level` and add `<w:pPr><w:numPr><w:numId w:val="num_id"/><w:ilvl w:val="level"/></w:numPr></w:pPr>` to the target paragraph.

The tool SHALL return error `not_found` when num_id does not exist or `out_of_bounds` when paragraph_index is invalid.

#### Scenario: Assign num 5 level 0 to paragraph 3

- **GIVEN** a document with at least 4 paragraphs and num 5 defined
- **WHEN** the tool is invoked with `paragraph_index: 3, num_id: 5, level: 0`
- **THEN** paragraph 3 carries `<w:numPr><w:numId w:val="5"/><w:ilvl w:val="0"/></w:numPr>`

### Requirement: continue_list and start_new_list manage list continuity

The MCP tool `continue_list` SHALL accept `doc_id` + `paragraph_index` + `previous_list_num_id` and assign the same num_id to the target paragraph as the named previous list, continuing its numbering.

The MCP tool `start_new_list` SHALL accept `doc_id` + `paragraph_index` + `abstract_num_id` and create a new `<w:num>` referencing the abstract_num_id, then assign that new num_id to the target paragraph.

Both tools SHALL surface `not_found` errors when the referenced num_id or abstract_num_id does not exist.

#### Scenario: Continue numbering from earlier list

- **GIVEN** paragraph 5 has num_id 1 level 0 (current list value 3)
- **WHEN** `continue_list(paragraph_index: 10, previous_list_num_id: 1)` is called
- **THEN** paragraph 10's numPr is num_id 1 level 0
- **AND** opening in Word, paragraph 10 numbers as item 4 (continues from 3)

### Requirement: gc_orphan_numbering removes unreferenced num definitions

The MCP tool `gc_orphan_numbering` SHALL accept `doc_id`, scan every paragraph for numId references (including inside tables and block-level SDTs), and delete any `<w:num>` whose num_id is not referenced.

The tool SHALL return an array of deleted num_ids in num_id order.

The tool SHALL NOT delete `<w:abstractNum>` definitions even if no `<w:num>` references them — abstractNums are templates and may be referenced by future inserts.

#### Scenario: GC sweeps two orphans

- **GIVEN** a document with num_ids `[1, 2, 3]` where only num 1 is referenced
- **WHEN** the tool is invoked
- **THEN** the response is `[2, 3]`
- **AND** subsequent `list_numbering_definitions` returns only num 1

