## ADDED Requirements

### Requirement: set_line_numbers_for_section enables line numbering on a section

The MCP tool `set_line_numbers_for_section` SHALL accept `doc_id` + `section_index` + `count_by` (int — number every Nth line) + optional `start: int` + optional `restart: string` (one of `continuous` / `newSection` / `newPage`).

The tool SHALL emit `<w:lnNumType w:countBy="..." w:start="..." w:restart="..."/>` in the target section's sectPr.

The tool SHALL return error `out_of_bounds` when section_index is invalid.

#### Scenario: Number every line, restart per page

- **WHEN** the tool is invoked with `section_index: 0, count_by: 1, start: 1, restart: "newPage"`
- **THEN** the section's sectPr contains `<w:lnNumType w:countBy="1" w:start="1" w:restart="newPage"/>`

### Requirement: set_section_vertical_alignment sets vertical alignment

The MCP tool `set_section_vertical_alignment` SHALL accept `doc_id` + `section_index` + `alignment` (one of `top` / `center` / `bottom` / `both`) and emit `<w:vAlign w:val="alignment"/>`.

#### Scenario: Center vertical alignment for cover page

- **WHEN** the tool is invoked with `section_index: 0, alignment: "center"`
- **THEN** sectPr contains `<w:vAlign w:val="center"/>`

### Requirement: set_page_number_format sets page number style and start

The MCP tool `set_page_number_format` SHALL accept `doc_id` + `section_index` + optional `start: int` + `format` (one of `decimal` / `lowerRoman` / `upperRoman` / `lowerLetter` / `upperLetter`).

The tool SHALL emit `<w:pgNumType w:start="..." w:fmt="..."/>` (start attribute omitted when not provided).

#### Scenario: Roman numerals for preface section

- **WHEN** the tool is invoked with `section_index: 0, start: 1, format: "lowerRoman"`
- **THEN** sectPr contains `<w:pgNumType w:start="1" w:fmt="lowerRoman"/>`

### Requirement: set_section_break_type changes the section break

The MCP tool `set_section_break_type` SHALL accept `doc_id` + `section_index` + `type` (one of `nextPage` / `continuous` / `evenPage` / `oddPage`) and emit `<w:type w:val="type"/>`.

#### Scenario: Section starts on odd page

- **WHEN** the tool is invoked with `section_index: 1, type: "oddPage"`
- **THEN** section 1's sectPr contains `<w:type w:val="oddPage"/>`

### Requirement: set_title_page_distinct toggles per-section first-page header

The MCP tool `set_title_page_distinct` SHALL accept `doc_id` + `section_index` + `enabled: bool` and emit or remove `<w:titlePg/>` in the target sectPr.

#### Scenario: Enable distinct title page

- **WHEN** the tool is invoked with `section_index: 0, enabled: true`
- **THEN** sectPr contains `<w:titlePg/>`

#### Scenario: Disable distinct title page removes element

- **GIVEN** a section already containing `<w:titlePg/>`
- **WHEN** the tool is invoked with `section_index: 0, enabled: false`
- **THEN** sectPr no longer contains `<w:titlePg/>`

### Requirement: set_section_header_footer_references assigns header / footer parts

The MCP tool `set_section_header_footer_references` SHALL accept `doc_id` + `section_index` + `references: { header_default?: string, header_first?: string, header_even?: string, footer_default?: string, footer_first?: string, footer_even?: string }`.

For each provided key, the tool SHALL emit a corresponding `<w:headerReference w:type="..." r:id="..."/>` or `<w:footerReference w:type="..." r:id="..."/>` in the target sectPr, replacing any existing reference of the same type.

The string value is the relationship id pointing to the header/footer XML part. The tool SHALL return error `relationship_not_found` if any provided rId does not resolve to an existing header/footer part.

#### Scenario: Bind first-page header to existing rId

- **GIVEN** rId7 points to header2.xml as a "first" type header
- **WHEN** the tool is invoked with `section_index: 0, references: {header_first: "rId7"}`
- **THEN** sectPr contains `<w:headerReference w:type="first" r:id="rId7"/>`

### Requirement: get_all_sections returns every section's properties summary

The MCP tool `get_all_sections` SHALL accept `doc_id` (or `source_path`) and return an array with one entry per section in document order.

Each entry SHALL include: `section_index`, `paragraph_range: { start, end }`, `page_size`, `page_orientation`, `page_margins`, `columns`, `line_numbers` (if any), `vertical_alignment` (if any), `page_number_format` (if any), `section_break_type`, `title_page_distinct: bool`, `header_references: { default?, first?, even? }`, `footer_references: { default?, first?, even? }`.

#### Scenario: Document with two sections

- **GIVEN** a document with section 0 (Roman numeral preface, sections 1-5) and section 1 (decimal body, sections 6-end)
- **WHEN** the tool is invoked
- **THEN** the response is an array of two entries, each carrying its own page_number_format and paragraph_range

