## ADDED Requirements

### Requirement: list_captions MCP tool enumerates captions in document order

The `che-word-mcp` server SHALL provide a `list_captions(doc_id)` MCP tool returning an array of caption descriptors. Each descriptor SHALL contain `{ index: Int, label: String, sequence_number: Int, caption_text: String, paragraph_index: Int }` where `index` is the caption's position in the returned array (0-based, in document order by paragraph_index), `label` is the SEQ identifier (e.g., `"Figure"`, `"圖"`), `sequence_number` is the cached numeric value as an integer, `caption_text` is the human-readable text following the SEQ field. The tool SHALL scan only paragraphs whose `pStyle == "Caption"`.

#### Scenario: Listing a document with 3 figure captions

- **WHEN** a document has 3 caption paragraphs with SEQ fields `SequenceField(identifier: "Figure")` and cached results `"1"`, `"2"`, `"3"` plus caption text `"First"`, `"Second"`, `"Third"`, and `list_captions(doc_id: "d1")` is called
- **THEN** the result is an array of 3 entries: `[{index: 0, label: "Figure", sequence_number: 1, caption_text: "First", ...}, {index: 1, label: "Figure", sequence_number: 2, caption_text: "Second", ...}, ...]`

### Requirement: get_caption returns full caption detail

The `che-word-mcp` server SHALL provide a `get_caption(doc_id, index)` MCP tool returning `{ label, sequence_number, chapter_number?, caption_text, paragraph_index, field_instr_text }`. The `chapter_number` field SHALL be populated when the caption contains a STYLEREF field preceding the SEQ field; otherwise nil/absent. The `field_instr_text` SHALL contain the raw SEQ field instruction string for caller diagnostics.

#### Scenario: get_caption includes chapter number when STYLEREF is present

- **WHEN** a caption was inserted with `include_chapter_number: true` (emitting STYLEREF 1 + SEQ) and has cached `STYLEREF` result `"4"` + cached SEQ result `"2"`
- **THEN** `get_caption(doc_id, index: 0)` returns `chapter_number: 4`, `sequence_number: 2`

### Requirement: update_caption modifies caption text or label without breaking SEQ field

The `che-word-mcp` server SHALL provide an `update_caption(doc_id, index, new_caption_text: String?, new_label: String?)` MCP tool. When `new_caption_text` is provided, the tool SHALL replace the text after the SEQ field while preserving the SEQ field itself (field XML unchanged). When `new_label` is provided, the tool SHALL replace the leading label text AND the SEQ identifier, preserving the field structure but changing the `SEQ <identifier>` value. The tool SHALL return an error when both arguments are nil. The tool SHALL NOT attempt to re-number; callers use `update_all_fields` for that.

#### Scenario: Change caption text preserves SEQ structure

- **WHEN** a caption reads `"圖 1 old text"` and `update_caption(doc_id, index: 0, new_caption_text: "new text")` is called
- **THEN** the caption now reads `"圖 1 new text"` and the SEQ field XML (begin/separate/end structure) is unchanged

#### Scenario: Change caption label rewrites SEQ identifier

- **WHEN** a caption with `label == "Figure"` is updated via `update_caption(doc_id, index: 0, new_label: "Table")`
- **THEN** the caption's SEQ field instruction is now `" SEQ Table \\* ARABIC "` and the leading label text changes from `"Figure "` to `"Table "`

#### Scenario: Neither argument provided errors

- **WHEN** `update_caption(doc_id, index: 0)` is called with both `new_caption_text` and `new_label` absent
- **THEN** the tool returns an error naming the two parameters and requiring at least one

### Requirement: delete_caption removes caption paragraph

The `che-word-mcp` server SHALL provide a `delete_caption(doc_id, index)` MCP tool that removes the caption paragraph from the document body. Subsequent `list_captions` calls SHALL return one fewer entry.

#### Scenario: Delete re-indexes subsequent captions

- **WHEN** a document has 3 captions and `delete_caption(doc_id, index: 0)` is called
- **THEN** `list_captions(doc_id)` returns 2 entries with `index: 0` and `index: 1` (the former indices 1 and 2 now reindexed)

### Requirement: update_all_fields MCP tool recomputes SEQ counters across the document

The `che-word-mcp` server SHALL provide an `update_all_fields(doc_id)` MCP tool that calls `WordDocument.updateAllFields()` and returns a summary. The response SHALL include the per-identifier final counter values and the total count of fields updated.

#### Scenario: Update renumbers captions after insertion

- **WHEN** a document has SEQ-based figures numbered `1`, `2`, `3` and a new figure is inserted between figure 1 and figure 2 (with initial cached `"1"`), then `update_all_fields(doc_id)` is called
- **THEN** the response indicates `Figure: 4` final counter and the four figures' cached results are now `"1"`, `"2"`, `"3"`, `"4"` in document order

### Requirement: list_equations MCP tool enumerates m:oMath runs in document order

The `che-word-mcp` server SHALL provide a `list_equations(doc_id)` MCP tool returning an array of equation descriptors. Each descriptor SHALL contain `{ index: Int, paragraph_index: Int, display_mode: Bool, components: <MathComponent-JSON tree> }`. The `display_mode` field SHALL be true when the equation was wrapped in `<m:oMathPara>`. The `components` shape SHALL match the JSON format consumed by `insert_equation(components:)`.

#### Scenario: List a document with 2 inline equations and 1 display equation

- **WHEN** a document has 2 inline `<m:oMath>` runs and 1 `<m:oMathPara><m:oMath>` display block, and `list_equations(doc_id)` is called
- **THEN** the result has 3 entries with `display_mode: false, false, true` respectively and each entry has a valid `components` tree

### Requirement: get_equation returns the full MathComponent tree

The `che-word-mcp` server SHALL provide a `get_equation(doc_id, index)` MCP tool returning the full `components` tree for the target equation plus `paragraph_index` and `display_mode`.

#### Scenario: get_equation round-trips a fraction

- **WHEN** an equation was inserted via `insert_equation(components: {type: "fraction", numerator: [...], denominator: [...]})` and `get_equation(doc_id, index: 0)` is called
- **THEN** the response `components` tree is structurally equivalent to the inserted tree

### Requirement: update_equation replaces the target equation's components

The `che-word-mcp` server SHALL provide an `update_equation(doc_id, index, components)` MCP tool that replaces the target `<m:oMath>` run's rawXML with the OMML emitted from the new `components` tree. The `paragraph_index` and `display_mode` SHALL be preserved unless the caller explicitly passes `display_mode` as a separate argument.

#### Scenario: Update replaces fraction with subSuperScript

- **WHEN** an existing equation has a MathFraction component and `update_equation(doc_id, index: 0, components: {type: "subSuperScript", ...})` is called
- **THEN** subsequent `get_equation(doc_id, index: 0)` returns the new tree and the paragraph still contains exactly one equation at the same paragraph_index

### Requirement: delete_equation removes equation run or containing paragraph

The `che-word-mcp` server SHALL provide a `delete_equation(doc_id, index)` MCP tool. When the target equation is the sole content of its paragraph, the tool SHALL remove the paragraph. When the equation is one of multiple runs, the tool SHALL remove only the equation run, preserving other runs in the paragraph.

#### Scenario: Delete sole equation removes paragraph

- **WHEN** a document has a paragraph containing only a single display equation (no other runs) and `delete_equation(doc_id, index: 0)` is called
- **THEN** the paragraph is removed entirely from the document body

#### Scenario: Delete equation among other runs preserves paragraph

- **WHEN** a paragraph contains `"inline "` text + `<m:oMath>` equation + `" = 42"` text and `delete_equation(doc_id, index: 0)` is called
- **THEN** the paragraph now contains `"inline "` + `" = 42"` and is not removed
