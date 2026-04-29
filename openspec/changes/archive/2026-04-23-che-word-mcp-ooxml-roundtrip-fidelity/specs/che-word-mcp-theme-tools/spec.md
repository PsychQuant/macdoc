## ADDED Requirements

### Requirement: get_theme MCP tool returns parsed theme structure

The `che-word-mcp` server SHALL provide a `get_theme(doc_id: String)` MCP tool that reads `word/theme/theme1.xml` from the open document and returns a JSON object with shape `{ fonts: { major: { latin, ea, cs, scriptVariants: [{script, typeface}] }, minor: same shape }, colors: { accent1, accent2, accent3, accent4, accent5, accent6, hyperlink, followedHyperlink }, formatScheme: { rawXML } }`. Each font slot value is the typeface string (e.g. `"DFKai-SB"`); each color slot value is a 6-character hex string (e.g. `"5B9BD5"`). When `theme1.xml` is absent from the source document, the tool SHALL return `{ error: "no theme part" }`.

#### Scenario: Get theme from NTPU thesis returns DFKai-SB minor East Asian font

- **WHEN** `get_theme(doc_id: "thesis")` is called on a document whose `theme1.xml` declares `minorFont` with `<a:ea typeface="DFKai-SB"/>`
- **THEN** the result's `fonts.minor.ea` equals `"DFKai-SB"`

#### Scenario: Get theme from document without theme1.xml returns error

- **WHEN** `get_theme(doc_id: "noTheme")` is called on a document whose source ZIP has no `word/theme/theme1.xml`
- **THEN** the result is `{ error: "no theme part" }`

### Requirement: update_theme_fonts MCP tool partially updates major and minor font slots

The `che-word-mcp` server SHALL provide an `update_theme_fonts(doc_id: String, major: { latin?, ea?, cs?, scriptVariants? }?, minor: same shape?)` MCP tool that mutates `word/theme/theme1.xml`'s major/minor font slots. Only the slots passed in the arguments SHALL be modified — unspecified slots SHALL remain at their current values. The tool SHALL preserve the rest of the theme (colors, formatScheme) unchanged. The mutated theme SHALL persist after `save_document` via the overlay mode (defined in `ooxml-roundtrip-fidelity`).

#### Scenario: Partial update modifies only minor East Asian font

- **WHEN** `update_theme_fonts(doc_id: "thesis", minor: { ea: "華康中楷體" })` is called
- **AND** the document is then saved and reread
- **THEN** the reread theme's `fonts.minor.ea` equals `"華康中楷體"`
- **AND** the reread theme's `fonts.minor.latin` and `fonts.major.*` equal their pre-update values
- **AND** the reread theme's `colors.*` equal their pre-update values

#### Scenario: Update with empty arguments is a no-op

- **WHEN** `update_theme_fonts(doc_id: "x")` is called with no font slots specified
- **THEN** the tool returns success
- **AND** the theme's `fonts.*` values are unchanged

### Requirement: update_theme_color MCP tool replaces a single color slot

The `che-word-mcp` server SHALL provide an `update_theme_color(doc_id: String, slot: String, hex: String)` MCP tool where `slot` is one of `"accent1"`, `"accent2"`, `"accent3"`, `"accent4"`, `"accent5"`, `"accent6"`, `"hyperlink"`, `"followedHyperlink"`, `"dk1"`, `"lt1"`, `"dk2"`, `"lt2"` and `hex` is a 6-character uppercase hex string. The tool SHALL replace the color value for the named slot in `theme1.xml`'s `<a:clrScheme>` element. Invalid `slot` values SHALL return an error naming the allowed slot set. Hex values not matching `^[0-9A-Fa-f]{6}$` SHALL return an error.

#### Scenario: Update accent1 color slot

- **WHEN** `update_theme_color(doc_id: "x", slot: "accent1", hex: "5B9BD5")` is called
- **AND** the document is then saved and reread
- **THEN** the reread theme's `colors.accent1` equals `"5B9BD5"`

#### Scenario: Invalid slot returns error with allowed list

- **WHEN** `update_theme_color(doc_id: "x", slot: "unknown", hex: "FF0000")` is called
- **THEN** the tool returns an error whose message contains `accent1` and `accent2` (and at least one other allowed slot name)

### Requirement: set_theme MCP tool replaces theme1.xml verbatim

The `che-word-mcp` server SHALL provide a `set_theme(doc_id: String, full_xml: String)` MCP tool that replaces `word/theme/theme1.xml` with the supplied XML string verbatim (after validating it is well-formed XML and contains a top-level `<a:theme>` element). The tool serves as a low-level escape hatch when callers need to apply a complete custom theme. Invalid XML or missing `<a:theme>` root SHALL return an error naming the issue.

#### Scenario: Set theme with valid theme XML

- **WHEN** `set_theme(doc_id: "x", full_xml: <valid theme XML containing <a:theme> root>)` is called
- **AND** the document is then saved and reread
- **THEN** `get_theme(doc_id: "x")` returns values parsed from the supplied XML

#### Scenario: Set theme with malformed XML returns error

- **WHEN** `set_theme(doc_id: "x", full_xml: "<a:theme><unclosed>")` is called
- **THEN** the tool returns an error whose message contains `XML` and indicates the parse problem
