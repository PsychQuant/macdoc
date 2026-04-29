## ADDED Requirements

### Requirement: list_headers MCP tool enumerates all header parts in document order

The `che-word-mcp` server SHALL provide a `list_headers(doc_id: String)` MCP tool returning an array of header descriptors. Each descriptor SHALL contain `{ header_id: String, type: String, section_id: Int, has_watermark: Bool }` where `header_id` is the relationship Id (e.g. `"rId4"`), `type` is one of `"default"`, `"first"`, `"even"`, and `section_id` is the 0-indexed position of the section containing the `<w:headerReference>`. `has_watermark` is true when the header part contains a `<w:r>` whose descendants include a VML `PowerPlusWaterMarkObject` shape or a `<v:shape>` with `o:spt="136"` (Word watermark sentinel).

#### Scenario: List headers on NTPU thesis returns 6 entries

- **WHEN** `list_headers(doc_id: "thesis")` is called on a document with 6 header files (`header1.xml` through `header6.xml`)
- **THEN** the result has length 6
- **AND** each descriptor's `header_id` matches a `<Relationship>` Id in `_rels/document.xml.rels` with `Type` ending in `header`

#### Scenario: has_watermark is true when header contains PowerPlusWaterMarkObject

- **WHEN** `list_headers` runs on a document whose `header1.xml` contains a VML shape with `<v:shape id="PowerPlusWaterMarkObject1">`
- **THEN** the descriptor for that header has `has_watermark == true`

### Requirement: get_header MCP tool returns text content and full XML for a header part

The `che-word-mcp` server SHALL provide a `get_header(doc_id: String, header_id: String)` MCP tool returning `{ text: String, xml: String, watermark: { type: String, params: Object } | null }`. The `text` field SHALL contain the visible text content of all `<w:t>` runs in the header part concatenated. The `xml` field SHALL contain the complete `<w:hdr>` XML body verbatim. The `watermark` field SHALL be a structured representation when a watermark VML shape is present, otherwise `null`. Unknown `header_id` SHALL return an error.

#### Scenario: Get header returns full XML for caller inspection

- **WHEN** `get_header(doc_id: "thesis", header_id: "rId4")` is called
- **THEN** the result's `xml` field starts with `<w:hdr` and ends with `</w:hdr>`

#### Scenario: Get watermark detail from header containing PowerPlusWaterMarkObject

- **WHEN** `get_header(doc_id: "thesis", header_id: "rId4")` is called and `header4.xml` contains a watermark with text `"機密"`
- **THEN** the result's `watermark.type` equals `"text"`
- **AND** the result's `watermark.params.text` equals `"機密"`

#### Scenario: Unknown header_id returns error

- **WHEN** `get_header(doc_id: "x", header_id: "rId999")` is called and no header with that rId exists
- **THEN** the tool returns an error whose message names `rId999`

### Requirement: delete_header MCP tool removes header part and all references

The `che-word-mcp` server SHALL provide a `delete_header(doc_id: String, header_id: String)` MCP tool that: (1) removes the typed header from `WordDocument.headers`, (2) deletes the corresponding `header*.xml` file from `archiveTempDir`, (3) removes the `<Relationship>` entry from `_rels/document.xml.rels`, (4) removes the `<Override>` entry from `[Content_Types].xml`, (5) removes any `<w:headerReference r:id="<header_id>">` elements from section properties in `document.xml`. Unknown `header_id` SHALL return an error and SHALL NOT modify state.

#### Scenario: Delete header removes all references

- **WHEN** `delete_header(doc_id: "thesis", header_id: "rId4")` is called and the document is then saved and reread
- **THEN** `list_headers` no longer includes a descriptor with `header_id == "rId4"`
- **AND** the saved `.docx` ZIP does NOT contain the prior header4.xml entry
- **AND** the saved `.docx`'s `_rels/document.xml.rels` does NOT contain a Relationship with Id `"rId4"`
- **AND** the saved `.docx`'s `[Content_Types].xml` does NOT contain an Override for the deleted PartName

#### Scenario: Delete unknown header_id returns error and does not modify state

- **WHEN** `delete_header(doc_id: "thesis", header_id: "rId999")` is called and no such header exists
- **THEN** the tool returns an error whose message names `rId999`
- **AND** the document state is unchanged

### Requirement: list_watermarks MCP tool enumerates watermark VML shapes across all header parts

The `che-word-mcp` server SHALL provide a `list_watermarks(doc_id: String)` MCP tool returning an array of watermark descriptors. Each descriptor SHALL contain `{ header_id: String, type: String, text: String?, image_path: String?, color: String?, rotation: Double?, scale: Double? }`. `type` is one of `"text"` or `"image"`. For text watermarks, `text` and optional `color` (hex string) and `rotation` (degrees) are populated. For image watermarks, `image_path` references the embedded media path and `scale` (percent) is populated.

#### Scenario: List watermarks returns text and image variants distinctly

- **WHEN** `list_watermarks(doc_id: "doc")` is called and the document has one header with text watermark `"機密"` and another header with image watermark referencing `media/wmark.png`
- **THEN** the result has length 2
- **AND** one descriptor has `type == "text"` and `text == "機密"`
- **AND** one descriptor has `type == "image"` and `image_path == "word/media/wmark.png"`

### Requirement: get_watermark MCP tool returns full parameters for a header's watermark

The `che-word-mcp` server SHALL provide a `get_watermark(doc_id: String, header_id: String)` MCP tool returning the same descriptor shape as `list_watermarks` entries. Headers without a watermark SHALL return `null`. Unknown `header_id` SHALL return an error.

#### Scenario: Get watermark returns null for header without watermark

- **WHEN** `get_watermark(doc_id: "x", header_id: "rId4")` is called and `header4.xml` contains no watermark VML shape
- **THEN** the tool returns `null`

### Requirement: list_footers MCP tool enumerates all footer parts in document order

The `che-word-mcp` server SHALL provide a `list_footers(doc_id: String)` MCP tool returning an array of footer descriptors. Each descriptor SHALL contain `{ footer_id: String, type: String, section_id: Int, has_page_number: Bool }` where `type` is one of `"default"`, `"first"`, `"even"`, and `has_page_number` is true when the footer contains a `<w:fldSimple>` or `<w:instrText>` whose instruction starts with `PAGE` or `NUMPAGES`.

#### Scenario: List footers detects page number field

- **WHEN** `list_footers(doc_id: "thesis")` is called and `footer1.xml` contains `<w:fldSimple w:instr=" PAGE \\* MERGEFORMAT ">`
- **THEN** the descriptor for that footer has `has_page_number == true`

### Requirement: get_footer MCP tool returns text content, full XML, and field structure

The `che-word-mcp` server SHALL provide a `get_footer(doc_id: String, footer_id: String)` MCP tool returning `{ text: String, xml: String, fields: [{ type: String, instruction: String }] }`. The `fields` array SHALL include one entry per `<w:fldSimple>` or `<w:fldChar>`-bounded field span, with `type` set to the parsed field name (e.g. `"PAGE"`, `"NUMPAGES"`, `"REF"`, `"STYLEREF"`, or `"unknown"` when the field instruction does not match a recognized type). Unknown `footer_id` SHALL return an error.

#### Scenario: Get footer identifies PAGE field

- **WHEN** `get_footer(doc_id: "thesis", footer_id: "rId7")` is called and `footer7.xml` contains a `<w:fldSimple w:instr=" PAGE ">`
- **THEN** the result's `fields` array contains an entry with `type == "PAGE"`

### Requirement: delete_footer MCP tool removes footer part and all references

The `che-word-mcp` server SHALL provide a `delete_footer(doc_id: String, footer_id: String)` MCP tool with the same five-step removal semantics as `delete_header` (typed model entry + tempDir file + Relationship entry + Content_Types Override + section properties `<w:footerReference r:id="<footer_id>">` elements). Unknown `footer_id` SHALL return an error and SHALL NOT modify state.

#### Scenario: Delete footer removes all references

- **WHEN** `delete_footer(doc_id: "thesis", footer_id: "rId7")` is called and the document is then saved and reread
- **THEN** `list_footers` no longer includes a descriptor with `footer_id == "rId7"`
- **AND** the saved `.docx`'s `_rels/document.xml.rels` does NOT contain a Relationship with Id `"rId7"`
- **AND** no `<w:footerReference r:id="rId7">` element remains in any section's properties
