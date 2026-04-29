## ADDED Requirements

### Requirement: get_endnote MCP tool returns endnote text and runs by ID

The `che-word-mcp` server SHALL provide a `get_endnote(doc_id: String, endnote_id: Int)` MCP tool returning `{ id: Int, text: String, runs: [{ text: String, bold: Bool?, italic: Bool?, color: String? }] }`. The `text` field is the concatenated visible text of all `<w:t>` elements in the endnote. The `runs` array preserves run-level formatting structure for callers needing to inspect individual runs. Unknown `endnote_id` SHALL return an error naming the missing ID.

#### Scenario: Get existing endnote by ID

- **WHEN** `get_endnote(doc_id: "x", endnote_id: 3)` is called and `endnotes.xml` contains an `<w:endnote w:id="3">` with text `"This is an endnote."`
- **THEN** the result's `id == 3` and `text == "This is an endnote."`
- **AND** the result's `runs` array contains at least one entry whose `text` covers `"This is an endnote."`

#### Scenario: Get unknown endnote ID returns error

- **WHEN** `get_endnote(doc_id: "x", endnote_id: 999)` is called and no endnote with that ID exists
- **THEN** the tool returns an error whose message names `999`

### Requirement: update_endnote MCP tool replaces endnote text in place preserving ID

The `che-word-mcp` server SHALL provide an `update_endnote(doc_id: String, endnote_id: Int, text: String)` MCP tool that replaces the entire content of the named endnote with a single paragraph containing the supplied text. The endnote ID SHALL remain unchanged so cross-references in `document.xml` (`<w:endnoteReference w:id="...">`) continue to resolve. The tool SHALL return `{ id: Int }` confirming the unchanged ID. Unknown `endnote_id` SHALL return an error.

#### Scenario: Update endnote preserves ID

- **WHEN** `update_endnote(doc_id: "x", endnote_id: 3, text: "Replaced.")` is called
- **AND** the document is then saved and reread
- **THEN** `get_endnote(doc_id: "x", endnote_id: 3)` returns `text == "Replaced."`
- **AND** every `<w:endnoteReference w:id="3">` in `document.xml` still resolves to a valid endnote

### Requirement: get_footnote MCP tool returns footnote text and runs by ID

The `che-word-mcp` server SHALL provide a `get_footnote(doc_id: String, footnote_id: Int)` MCP tool with the same shape and semantics as `get_endnote` but reading from `footnotes.xml`. Unknown `footnote_id` SHALL return an error.

#### Scenario: Get existing footnote by ID

- **WHEN** `get_footnote(doc_id: "x", footnote_id: 5)` is called and `footnotes.xml` contains an `<w:footnote w:id="5">` with text `"See chapter 3."`
- **THEN** the result's `id == 5` and `text == "See chapter 3."`

### Requirement: update_footnote MCP tool replaces footnote text in place preserving ID

The `che-word-mcp` server SHALL provide an `update_footnote(doc_id: String, footnote_id: Int, text: String)` MCP tool with the same in-place-replacement semantics as `update_endnote`. The footnote ID SHALL remain unchanged. Unknown `footnote_id` SHALL return an error.

#### Scenario: Update footnote preserves cross-references

- **WHEN** `update_footnote(doc_id: "x", footnote_id: 5, text: "Updated note.")` is called
- **AND** the document is then saved and reread
- **THEN** `get_footnote(doc_id: "x", footnote_id: 5)` returns `text == "Updated note."`
- **AND** every `<w:footnoteReference w:id="5">` in `document.xml` still resolves correctly
