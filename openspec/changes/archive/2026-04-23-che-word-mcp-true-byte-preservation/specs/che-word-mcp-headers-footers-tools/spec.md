## ADDED Requirements

### Requirement: list_watermarks reads each typed header's distinct fileName

The `che-word-mcp` server's `list_watermarks(doc_id)` MCP tool SHALL iterate `doc.headers` and for each header read the file at `archiveTempDir.appendingPathComponent("word/\(header.fileName)")`. Because `Header.fileName` now respects `originalFileName` (per docx-container-parsing requirements), each header in a multi-instance same-type set (e.g., 6 NTPU default headers) reads from its actual archive file (`header1.xml`, `header2.xml`, ..., `header6.xml`) rather than collapsing all reads to `"header1.xml"`.

#### Scenario: list_watermarks on NTPU thesis returns 6 entries

- **WHEN** `list_watermarks(doc_id: "ntpu")` is called on a document with 6 default headers each containing a `<v:shape id="PowerPlusWaterMarkObject..."` watermark VML shape
- **THEN** the result has length 6
- **AND** each entry has `header_id` matching one of the 6 distinct rIds (rId8/rId13/rId10/rId12/rId7/rId6 or similar)
- **AND** each entry has `type == "text"` and `text` extracted from the corresponding `<v:textpath string="...">` element

### Requirement: list_headers.has_watermark reflects per-header VML detection

The `che-word-mcp` server's `list_headers(doc_id)` MCP tool SHALL set `has_watermark` to `true` for each header whose actual XML file (read via `Header.fileName`) contains either `PowerPlusWaterMarkObject` substring OR `o:spt="136"` sentinel. With the multi-instance fileName fix, a document with 6 watermark-bearing headers SHALL return `has_watermark: true` for all 6 entries (not collapsed to a single entry's value).

#### Scenario: NTPU thesis 6 headers all report has_watermark true

- **WHEN** `list_headers(doc_id: "ntpu")` is called on a document where all 6 default headers contain VML watermark
- **THEN** the 6 returned entries all have `has_watermark == true`
- **AND** the 6 entries have distinct `header_id` values

### Requirement: list_footers.has_page_number detects three-segment fldChar PAGE field pattern

The `che-word-mcp` server's `list_footers(doc_id)` MCP tool's `has_page_number` field SHALL evaluate to `true` when the footer XML contains ANY of the following patterns (case-insensitive, whitespace-tolerant):

1. `<w:fldSimple\s+w:instr="\s*PAGE[\s"]` — single-element PAGE field with optional formatting switches
2. `<w:fldSimple\s+w:instr="[^"]*PAGE[^"]*"` — single-element PAGE field with `\* MERGEFORMAT` or other modifiers
3. Three-segment field pattern: `<w:fldChar w:fldCharType="begin"/>` followed within the same paragraph by `<w:instrText[^>]*>\s*PAGE\b` followed by `<w:fldChar w:fldCharType="end"/>`
4. `NUMPAGES` token in any of the above patterns (treated equivalently to PAGE for the page-number boolean)

#### Scenario: footer3.xml three-segment PAGE field detected

- **WHEN** `list_footers(doc_id: "ntpu")` is called on a document where footer3.xml contains `<w:fldChar w:fldCharType="begin"/>...<w:instrText>PAGE</w:instrText>...<w:fldChar w:fldCharType="end"/>`
- **THEN** the entry for footer3.xml has `has_page_number == true`

#### Scenario: footer with single-element PAGE and MERGEFORMAT switch detected

- **WHEN** a footer contains `<w:fldSimple w:instr=" PAGE \* MERGEFORMAT ">`
- **THEN** the entry's `has_page_number == true`

### Requirement: get_header / get_footer / delete_header / delete_footer address each header/footer by distinct fileName

The `che-word-mcp` server's `get_header`, `get_footer`, `delete_header`, `delete_footer` MCP tools SHALL look up the target by `header_id` (or `footer_id`) — each rId maps to a distinct typed `Header` (or `Footer`) instance with its own `originalFileName`. Reads, deletes, and updates SHALL operate on the file matching `Header.fileName` (or `Footer.fileName`), not the legacy `"header1.xml"` collapse.

#### Scenario: get_header on rId10 returns header3.xml content

- **WHEN** `get_header(doc_id: "ntpu", header_id: "rId10")` is called and the typed Header instance for rId10 has `fileName == "header3.xml"`
- **THEN** the returned `xml` field contains the actual content of `archiveTempDir/word/header3.xml`, NOT `header1.xml`

#### Scenario: delete_header on one of multiple default headers removes only the target file

- **WHEN** `delete_header(doc_id: "ntpu", header_id: "rId10")` is called (where rId10 maps to `header3.xml`)
- **THEN** `archiveTempDir/word/header3.xml` is deleted
- **AND** `archiveTempDir/word/header1.xml`, `header2.xml`, `header4-6.xml` are NOT touched
- **AND** the typed model's `doc.headers` no longer contains the entry with `id == "rId10"`
- **AND** `doc.modifiedParts.contains("word/header3.xml") == true` (signals overlay-mode regenerate-on-save will skip the deleted file but Content_Types overlay will drop the entry)
