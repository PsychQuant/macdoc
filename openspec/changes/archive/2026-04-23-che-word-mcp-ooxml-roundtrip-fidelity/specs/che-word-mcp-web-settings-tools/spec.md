## ADDED Requirements

### Requirement: get_web_settings MCP tool returns parsed webSettings.xml

The `che-word-mcp` server SHALL provide a `get_web_settings(doc_id: String)` MCP tool returning a JSON object with shape `{ optimize_for_browser: Bool, rely_on_vml: Bool, allow_png: Bool, do_not_save_as_single_file: Bool, encoding: String?, do_not_organize_in_folder: Bool, do_not_relyOnCSS: Bool, do_not_save_as_web_page: Bool }` parsed from `word/webSettings.xml`. Boolean settings default to `false` when the corresponding element is absent. Documents without `webSettings.xml` SHALL return `{ error: "no webSettings part" }`.

#### Scenario: Get web settings returns relyOnVML true

- **WHEN** `get_web_settings(doc_id: "x")` is called and `webSettings.xml` contains `<w:relyOnVML w:val="true"/>`
- **THEN** the result's `rely_on_vml == true`

#### Scenario: Get web settings on document without webSettings part returns error

- **WHEN** `get_web_settings(doc_id: "x")` is called and the source ZIP has no `word/webSettings.xml`
- **THEN** the result is `{ error: "no webSettings part" }`

### Requirement: update_web_settings MCP tool partially updates webSettings.xml

The `che-word-mcp` server SHALL provide an `update_web_settings(doc_id: String, optimize_for_browser: Bool?, rely_on_vml: Bool?, allow_png: Bool?, do_not_save_as_single_file: Bool?, encoding: String?, do_not_organize_in_folder: Bool?, do_not_relyOnCSS: Bool?, do_not_save_as_web_page: Bool?)` MCP tool that updates only the named settings. Unspecified arguments SHALL leave the corresponding setting unchanged. When `webSettings.xml` does not yet exist in the source ZIP, the tool SHALL create it (and add `[Content_Types].xml` Override + relationship) populated with defaults plus the supplied overrides.

#### Scenario: Partial update modifies only relyOnVML

- **WHEN** `update_web_settings(doc_id: "x", rely_on_vml: false)` is called and the original `webSettings.xml` had `relyOnVML=true` and `allowPNG=true`
- **AND** the document is then saved and reread
- **THEN** `get_web_settings` returns `rely_on_vml == false` and `allow_png == true`

#### Scenario: Update on document without webSettings part creates it

- **WHEN** `update_web_settings(doc_id: "x", rely_on_vml: true)` is called and `webSettings.xml` does not exist
- **AND** the document is then saved and reread
- **THEN** the saved `.docx` contains `word/webSettings.xml`
- **AND** the saved `[Content_Types].xml` contains an `<Override>` for `/word/webSettings.xml`
- **AND** `get_web_settings` returns `rely_on_vml == true`
