## ADDED Requirements

### Requirement: insert_caption accepts Chinese and English labels

The `che-word-mcp` server's `insert_caption` MCP tool SHALL accept `label` values from the set `{"Figure", "Table", "Equation", "圖", "表", "公式"}`. The `label` value MUST be used verbatim as both the leading text of the caption paragraph and the `SEQ <identifier>` identifier. Values outside this set MUST return an error containing the allowed list.

#### Scenario: Chinese label "圖"

- **WHEN** `insert_caption({ doc_id, paragraph_index: 0, label: "圖", caption_text: "前後期報酬率分布" })` is called
- **THEN** the inserted paragraph leading text starts with `圖 ` and the written field's instrText contains ` SEQ 圖 `

#### Scenario: Invalid label rejected

- **WHEN** `insert_caption({ label: "Foto" })` is called
- **THEN** the tool returns an error message that enumerates the six allowed labels

### Requirement: insert_caption produces real SEQ field XML

The `che-word-mcp` server's `insert_caption` MCP tool SHALL emit a caption paragraph whose numbering is a real OOXML `<w:fldChar>` field (not literal characters). The emitted runs MUST be: (1) label text run, (2) optional `StyleRefField` runs when `include_chapter_number == true`, (3) literal `-` run when chapter number is included, (4) `SequenceField` runs, (5) caption text run. Opening the written .docx in Word and pressing F9 SHALL cause the caption number to auto-update.

#### Scenario: Caption with chapter number produces both STYLEREF and SEQ

- **WHEN** `insert_caption({ label: "圖", caption_text: "x", include_chapter_number: true })` is called
- **THEN** the inserted paragraph contains a `<w:fldChar w:fldCharType="begin"/>` followed by ` STYLEREF 1 \s `, a literal `-` run, another `<w:fldChar w:fldCharType="begin"/>` followed by ` SEQ 圖 \* ARABIC \s 1 `

#### Scenario: No literal field-code characters appear in caption text

- **WHEN** `insert_caption({ label: "Figure", caption_text: "y" })` is written to a .docx file
- **THEN** the resulting `document.xml` contains zero literal occurrences of the substring `{ SEQ Figure \* ARABIC }` or `{ STYLEREF 1 \s }`

### Requirement: insert_caption accepts three anchor types

The `che-word-mcp` server's `insert_caption` MCP tool SHALL accept exactly one of `paragraph_index: Int`, `after_image_id: String`, or `after_table_index: Int` as the anchor. Providing zero or more than one anchor MUST return an error. `after_image_id` MUST be the relationship id returned by a prior `insert_image` call. `after_table_index` MUST be the zero-based index of a table in the document's body. The inserted caption paragraph MUST be placed immediately after the anchor location.

#### Scenario: after_image_id anchor

- **WHEN** `insert_image` returns `rId22` for an inserted image and `insert_caption({ after_image_id: "rId22", label: "圖", caption_text: "..." })` is called
- **THEN** the caption paragraph is inserted as the next sibling paragraph of the image-bearing paragraph

#### Scenario: Multiple anchors rejected

- **WHEN** `insert_caption({ paragraph_index: 5, after_image_id: "rId22", label: "Figure" })` is called
- **THEN** the tool returns an error stating exactly one anchor MUST be provided

### Requirement: insert_equation components produces valid OMML

The `che-word-mcp` server's `insert_equation` MCP tool SHALL accept a `components:` argument shaped as a JSON tree with a `type` discriminator selecting the corresponding `MathComponent` Swift type. Supported discriminators: `run`, `fraction`, `radical`, `subSuperScript`, `nary`, `delimiter`, `function`, `limit`, `matrix`. The tool SHALL traverse the tree, construct the matching `MathComponent` values, and insert a paragraph containing the OMML output wrapped in `<m:oMathPara><m:oMath>...</m:oMath></m:oMathPara>`.

#### Scenario: Insert fraction via components

- **WHEN** `insert_equation({ components: { type: "fraction", numerator: [{ type: "run", text: "a" }], denominator: [{ type: "run", text: "b" }] } })` is called
- **THEN** the inserted paragraph contains `<m:f>` with `<m:num><m:r><m:t>a</m:t></m:r></m:num>` and `<m:den><m:r><m:t>b</m:t></m:r></m:den>`

### Requirement: insert_equation latex fallback supports documented subset

The `che-word-mcp` server's `insert_equation` MCP tool SHALL accept a `latex:` argument as a fallback when `components:` is not provided. The tool MUST support exactly this pseudo-LaTeX subset: `\frac{a}{b}`, `a^{b}`, `a_{b}`, `\sqrt{a}`, Greek letters listed in the tool description, and a fixed operator list (at minimum `\sum`, `\int`, `\prod`, `\cdot`, `\times`, `\pm`). Syntax outside this subset MUST cause the tool to return an error message naming the first unrecognized token and referring the caller to the `components:` argument for full control.

#### Scenario: LaTeX within subset succeeds

- **WHEN** `insert_equation({ latex: "\\frac{a}{b}" })` is called
- **THEN** the inserted paragraph contains `<m:f>` with numerator `a` and denominator `b`

#### Scenario: Unsupported LaTeX macro rejected with clear error

- **WHEN** `insert_equation({ latex: "\\overbrace{abc}" })` is called
- **THEN** the tool returns an error whose message contains both the token `\overbrace` and a reference to the `components:` argument

### Requirement: insert_image_from_path computes missing dimension from aspect

The `che-word-mcp` server's `insert_image_from_path` MCP tool SHALL accept the combination of (a) both `width` and `height`, (b) only `width`, (c) only `height`, or (d) neither. When exactly one dimension is provided, the missing dimension MUST be computed as `provided * nativeRatio` where `nativeRatio` comes from `ImageDimensions.detect(path:)`. When neither is provided, both dimensions MUST default to the native pixel dimensions.

#### Scenario: Width-only with auto height

- **WHEN** `insert_image_from_path({ path: "img.png", width: 400 })` is called on an image whose native dimensions are 800×600
- **THEN** the inserted image declares `width=400` and `height=300`

#### Scenario: Neither dimension provided

- **WHEN** `insert_image_from_path({ path: "img.png" })` is called on an image whose native dimensions are 800×600
- **THEN** the inserted image declares `width=800` and `height=600`

### Requirement: insert_image_from_path supports table-cell insertion

The `che-word-mcp` server's `insert_image_from_path` MCP tool SHALL accept an `into_table_cell: { table_index: Int, row: Int, col: Int }` argument that resolves to the `InsertLocation.intoTableCell` case. The `paragraph_index` argument MUST NOT be combined with `into_table_cell`; providing both MUST return an error.

#### Scenario: Insert into a specific table cell

- **WHEN** `insert_image_from_path({ path: "img.png", into_table_cell: { table_index: 0, row: 2, col: 1 } })` is called on a document whose first table has at least 3 rows and 2 columns
- **THEN** the image paragraph is added inside table[0].rows[2].cells[1] and no body-level paragraph is inserted

### Requirement: replace_text defaults scope to body

The `che-word-mcp` server's `replace_text` MCP tool SHALL accept a `scope: "body" | "all"` argument defaulting to `"body"`. The value `"body"` MUST map to `ReplaceOptions.scope = .bodyAndTables` (preserving the behavior shipped in ooxml-swift v0.5.5+). The value `"all"` MUST map to `ReplaceOptions.scope = .all`.

#### Scenario: Default scope only hits body and tables

- **WHEN** a document has "Draft" in body, header, and footer and `replace_text({ find: "Draft", with: "Final" })` is called without a `scope` argument
- **THEN** only the body and table-cell occurrences are replaced and the returned count equals the body+table count

#### Scenario: Scope all covers header and footer

- **WHEN** the same document and `replace_text({ find: "Draft", with: "Final", scope: "all" })` is called
- **THEN** body, tables, headers, footers, footnotes, and endnotes are all traversed and the returned count reflects every occurrence

### Requirement: replace_text matches across run boundaries

The `che-word-mcp` server's `replace_text` MCP tool SHALL succeed when the `find` string spans multiple runs within the same paragraph. The tool MUST NOT fall back to per-run `contains()` matching. If the match cannot be represented within a single paragraph (e.g. the user's `find` string spans a paragraph break), the tool MUST return a clear error rather than partially matching.

#### Scenario: Match spans three runs

- **WHEN** a paragraph has runs `["均值方程式：", "", "r_t = "]` and `replace_text({ find: "均值方程式：r_t", with: "Mean: r_t" })` is called
- **THEN** the returned count equals 1 and the paragraph text reads `Mean: r_t = `

### Requirement: replace_text supports regex option

The `che-word-mcp` server's `replace_text` MCP tool SHALL accept a `regex: Bool` argument defaulting to `false`. When `regex == true`, the `find` string MUST be treated as an `NSRegularExpression` (ICU flavor) pattern and the `with` string MUST support `$1`, `$2`, etc. capture-group backreferences.

#### Scenario: Regex with capture group

- **WHEN** a document contains "Chapter 4" and `replace_text({ find: "Chapter (\\d+)", with: "Ch. $1", regex: true })` is called
- **THEN** the result contains `Ch. 4` and the returned count equals 1

#### Scenario: Invalid regex returns error

- **WHEN** `replace_text({ find: "[unclosed", with: "x", regex: true })` is called
- **THEN** the tool returns an error identifying the invalid regex pattern

### Requirement: MCP tool schemas document BREAKING changes

The `che-word-mcp` server's tool schemas for `insert_caption`, `insert_equation`, `insert_image_from_path`, and `replace_text` SHALL each include a description string naming the breaking change relative to the prior release. The CHANGELOG entry for the release SHALL list each tool's BREAKING API change with migration instructions.

#### Scenario: CHANGELOG names each BREAKING tool

- **WHEN** a reader opens the CHANGELOG entry for the release that closes #6/#7/#8/#9
- **THEN** the entry lists `insert_caption`, `insert_equation`, `insert_image_from_path`, `replace_text` each marked **BREAKING** with a one-line migration note
