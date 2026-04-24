## ADDED Requirements

### Requirement: list_content_controls enumerates SDTs in a document

The MCP tool `list_content_controls` SHALL return every Structured Document Tag present in the target document, including metadata (id, tag, alias, type, lockType, currentText, paragraphIndex, parentSdtId).

The tool SHALL accept either `doc_id` (session mode) or `source_path` (direct mode).

The tool SHALL support an optional `nested: bool` argument. When `nested=false` (default), the tool returns a flat list where nested SDTs include a `parentSdtId` field pointing to their enclosing SDT (null for top-level). When `nested=true`, the tool returns a tree where each SDT includes a `children` array.

#### Scenario: Flat listing of a document with nested SDTs

- **WHEN** the tool is invoked on a document containing a Group SDT that wraps two PlainText SDTs
- **THEN** the response contains three SDT entries; the Group has `parentSdtId=null` and the two PlainText entries have `parentSdtId` equal to the Group's id

#### Scenario: Empty document returns empty list

- **WHEN** the tool is invoked on a document with no SDT elements
- **THEN** the response is an empty array

### Requirement: get_content_control fetches a single SDT by id, tag, or alias

The MCP tool `get_content_control` SHALL locate and return a single SDT matching the supplied identifier. Exactly one of `id` (integer), `tag` (string), or `alias` (string) MUST be provided.

The tool SHALL return the same fields as `list_content_controls` entries, plus the full content XML of the SDT's `<w:sdtContent>` region.

If no SDT matches, the tool SHALL return an error `not_found` with the query parameters echoed.

If multiple SDTs share the queried tag or alias, the tool SHALL return an error `multiple_matches` listing all matching ids.

#### Scenario: Lookup by tag succeeds with unique match

- **WHEN** a document contains one SDT with tag="client_name"
- **AND** the tool is invoked with `tag: "client_name"`
- **THEN** the response contains the matching SDT's full metadata and content XML

#### Scenario: Lookup by tag fails with multiple matches

- **WHEN** a document contains two SDTs both with tag="item"
- **AND** the tool is invoked with `tag: "item"`
- **THEN** the response is `multiple_matches` error listing both SDT ids

### Requirement: update_content_control_text modifies plain-text SDT content

The MCP tool `update_content_control_text` SHALL replace the text content of a plain-text, rich-text, or date SDT identified by id. The tool accepts `doc_id`, `id`, and `text` arguments.

The tool SHALL preserve the SDT's `<w:sdtPr>` properties (tag, alias, lockType, placeholder, type) without modification. Only `<w:sdtContent>` text runs SHALL be rewritten.

If the target SDT is a type that cannot hold plain text (picture, dropDownList, comboBox, checkbox, group, repeatingSection), the tool SHALL return an error `unsupported_type`.

#### Scenario: Update succeeds on plain-text SDT

- **GIVEN** a document containing SDT id=100000 with tag="client_name", current text="TBD"
- **WHEN** the tool is invoked with `id: 100000, text: "Acme Corp"`
- **THEN** the document on disk contains SDT id=100000 with current text "Acme Corp"
- **AND** the `<w:sdtPr>` of that SDT is byte-identical to the pre-update state

#### Scenario: Update fails on picture SDT

- **GIVEN** a document containing SDT id=100001 of type "picture"
- **WHEN** the tool is invoked with `id: 100001, text: "hello"`
- **THEN** the tool returns error code `unsupported_type` with message naming "picture"

### Requirement: replace_content_control_content replaces rich-text SDT content

The MCP tool `replace_content_control_content` SHALL replace the full XML content of a rich-text or group SDT identified by id. The tool accepts `doc_id`, `id`, and `content_xml` arguments.

The supplied `content_xml` MUST be a well-formed fragment containing only runs, paragraphs, or tables. The tool SHALL reject input containing `<w:sdt>`, `<w:body>`, `<w:sectPr>`, XML declaration, or any element outside a whitelist.

If the rejected element is detected, the tool SHALL return an error `disallowed_element` naming the element.

#### Scenario: Replace succeeds with paragraph fragment

- **GIVEN** a rich-text SDT id=100000 with placeholder content
- **WHEN** the tool is invoked with `id: 100000, content_xml: "<w:p><w:r><w:t>Hello</w:t></w:r></w:p>"`
- **THEN** the SDT's `<w:sdtContent>` now contains the supplied paragraph
- **AND** the SDT's `<w:sdtPr>` is unchanged

#### Scenario: Replace rejects nested SDT

- **WHEN** the tool is invoked with `content_xml` that contains `<w:sdt>`
- **THEN** the tool returns error code `disallowed_element` naming `w:sdt`

### Requirement: delete_content_control removes SDT with optional content preservation

The MCP tool `delete_content_control` SHALL remove an SDT identified by id. The tool accepts `doc_id`, `id`, and optional `keep_content: bool` (default `true`).

When `keep_content=true`, the SDT's `<w:sdtContent>` children are unwrapped and inserted at the SDT's former position as inline content.

When `keep_content=false`, the SDT and all its content are removed.

If the SDT id is not found, the tool SHALL return error `not_found`.

#### Scenario: Delete with keep_content=true unwraps content

- **GIVEN** a paragraph containing inline text "Before" then SDT id=100000 containing "middle" then inline text "After"
- **WHEN** the tool is invoked with `id: 100000, keep_content: true`
- **THEN** the paragraph contains text "Before middle After" with no SDT wrapper

#### Scenario: Delete with keep_content=false removes content

- **GIVEN** the same setup
- **WHEN** the tool is invoked with `id: 100000, keep_content: false`
- **THEN** the paragraph contains text "Before After"

### Requirement: insert_content_control accepts advanced SDT types and extended args

The MCP tool `insert_content_control` SHALL accept the following `type` values: `richText`, `text`, `picture`, `date`, `dropDownList`, `comboBox`, `checkbox`, `bibliography`, `citation`, `group`, `repeatingSectionItem`. The type `repeatingSection` SHALL be rejected with an error directing the caller to `insert_repeating_section`.

The tool SHALL accept the following optional arguments:

- `list_items: [{value: string, display_text: string}]` — REQUIRED when type is `dropDownList` or `comboBox`, forbidden otherwise
- `date_format: string` — permitted only when type is `date`; default `"yyyy/M/d"` when omitted
- `lock_type: "unlocked" | "sdtLocked" | "contentLocked" | "sdtContentLocked"` — permitted for any type; default `"unlocked"`

All new arguments are optional (except `list_items` for dropdown/combo types); omitting them preserves v3.7.x behavior exactly.

#### Scenario: Insert dropdown with list items

- **WHEN** the tool is invoked with `type: "dropDownList", tag: "priority", list_items: [{value: "H", display_text: "High"}, {value: "L", display_text: "Low"}]`
- **THEN** the resulting SDT's `<w:sdtPr>` contains `<w:dropDownList>` with two `<w:listItem>` entries matching the input

#### Scenario: Insert dropdown without list_items returns error

- **WHEN** the tool is invoked with `type: "dropDownList"` and no `list_items`
- **THEN** the tool returns error `missing_required_arg` naming `list_items`

#### Scenario: Insert rejects repeatingSection type

- **WHEN** the tool is invoked with `type: "repeatingSection"`
- **THEN** the tool returns error directing the caller to `insert_repeating_section`

### Requirement: insert_repeating_section supports allow_insert_delete_sections arg

The MCP tool `insert_repeating_section` SHALL accept an optional `allow_insert_delete_sections: bool` argument, default `true`. The argument maps to the `<w:repeatingSection w:allowInsertDeleteSections>` OOXML attribute.

#### Scenario: Disable section insert/delete

- **WHEN** the tool is invoked with `allow_insert_delete_sections: false`
- **THEN** the resulting SDT's `<w:sdtPr>` contains `<w15:repeatingSection w15:allowInsertDeleteSections="0"/>`

### Requirement: list_repeating_section_items enumerates items of a repeating section SDT

The MCP tool `list_repeating_section_items` SHALL return all `<w15:repeatingSectionItem>` children of a repeating-section SDT identified by id. Each item entry includes its own SDT id, item-level tag (if present), and current text content.

#### Scenario: List items in populated section

- **GIVEN** a repeating section SDT id=100000 containing three items with content "A", "B", "C"
- **WHEN** the tool is invoked with `id: 100000`
- **THEN** the response is an array of three item entries with content fields "A", "B", "C" in order

### Requirement: update_repeating_section_item modifies a single item's content

The MCP tool `update_repeating_section_item` SHALL replace the text content of one item within a repeating-section SDT. It accepts `doc_id`, `parent_id` (the repeating section's SDT id), `item_index` (zero-based), and `text`.

Out-of-range `item_index` SHALL return error `out_of_bounds`.

#### Scenario: Update middle item

- **GIVEN** a repeating section id=100000 containing items ["A", "B", "C"]
- **WHEN** the tool is invoked with `parent_id: 100000, item_index: 1, text: "B-updated"`
- **THEN** the section's items are ["A", "B-updated", "C"]

### Requirement: list_custom_xml_parts returns empty stub

The MCP tool `list_custom_xml_parts` SHALL return an empty array for all inputs until Change B (`che-word-mcp-customxml-databinding`) implements real support.

The tool's schema SHALL declare the eventual return type: array of objects with `store_item_id`, `target_namespaces`, and `root_element` fields.

#### Scenario: Stub returns empty list on any document

- **WHEN** the tool is invoked on any valid document
- **THEN** the response is `[]`

