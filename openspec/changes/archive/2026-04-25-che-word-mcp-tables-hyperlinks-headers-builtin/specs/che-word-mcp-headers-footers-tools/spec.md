## ADDED Requirements

### Requirement: add_header and add_footer accept type argument

The MCP tools `add_header` and `add_footer` SHALL accept an optional `type: "default" | "first" | "even"` argument (default `"default"` for backwards compatibility).

The tool SHALL create a new `word/header[N].xml` (or `word/footer[N].xml`) part with the appropriate `w:headerReference w:type="$type"` registered in the active section's sectPr.

When called twice with the same type for the same section, the second call SHALL replace the existing part of that type rather than creating a duplicate.

#### Scenario: Add first-page header

- **WHEN** the tool is invoked with `type: "first", text: "Cover Page Header"`
- **THEN** a new `word/header[N].xml` is created
- **AND** sectPr contains `<w:headerReference w:type="first" r:id="$rId"/>`

### Requirement: enable_even_odd_headers toggles the document-level flag

The MCP tool `enable_even_odd_headers` SHALL accept `doc_id` + `enabled: bool` and emit / remove `<w:evenAndOddHeaders/>` in `word/settings.xml`.

When enabled, even-page headers (added via `add_header(type: "even")`) become visible.

#### Scenario: Enable even/odd headers

- **WHEN** the tool is invoked with `enabled: true`
- **THEN** `word/settings.xml` contains `<w:evenAndOddHeaders/>`

### Requirement: link_section_header_to_previous shares the prior section's header XML part

The MCP tool `link_section_header_to_previous` SHALL accept `doc_id` + `section_index` + `type` (one of `"default"` / `"first"` / `"even"`).

The tool SHALL find the immediately-prior section's header XML part of the matching type, and assign that part's rId to the target section's `<w:headerReference w:type="$type"/>`.

The tool SHALL return error `out_of_bounds` when `section_index < 1`.

The tool SHALL return error `not_found` when the prior section has no header of the matching type.

#### Scenario: Link section 1 header to section 0

- **GIVEN** section 0 has a default header (XML part header2.xml, rId7)
- **AND** section 1 has its own default header (header3.xml, rId8)
- **WHEN** the tool is invoked with `section_index: 1, type: "default"`
- **THEN** section 1's sectPr `<w:headerReference w:type="default"/>` now has `r:id="rId7"`
- **AND** header3.xml may be GCed if no other section references it

### Requirement: unlink_section_header_from_previous clones the source XML part

The MCP tool `unlink_section_header_from_previous` SHALL accept `doc_id` + `section_index` + `type`.

The tool SHALL read the currently-shared header XML part, create a new part with a copy of its content, assign a fresh rId, and update the target section's reference to point at the new part.

#### Scenario: Unlink creates independent header

- **GIVEN** section 1's default header rId points at header2.xml (shared with section 0)
- **WHEN** the tool is invoked with `section_index: 1, type: "default"`
- **THEN** a new header part (e.g., header4.xml) is created with content copied from header2.xml
- **AND** section 1's sectPr `<w:headerReference w:type="default"/>` now references rId of header4.xml

### Requirement: get_section_header_map returns header part assignment per section

The MCP tool `get_section_header_map` SHALL accept `doc_id` (or `source_path`) and return an array describing which header XML part is referenced by each section for each type.

Each entry SHALL include: `section_index`, `header_default` (file name or null), `header_first` (file name or null), `header_even` (file name or null), `footer_default`, `footer_first`, `footer_even`.

#### Scenario: 2-section document map

- **GIVEN** section 0 with default header header2.xml; section 1 with default + first headers (header3.xml + header4.xml)
- **WHEN** the tool is invoked
- **THEN** the response is `[{section_index: 0, header_default: "header2.xml", ...}, {section_index: 1, header_default: "header3.xml", header_first: "header4.xml", ...}]`

### Requirement: insert_watermark discriminates text vs image variant

The MCP tool `insert_watermark` SHALL accept either `text` (string for text watermark via `<v:textpath>`) or `image_path` (string for image watermark via anchored shape with `wrapNone behindDoc='1'`).

The tool SHALL return error `mutually_exclusive` when both `text` and `image_path` are provided.

The tool SHALL return error `missing_parameter` when neither is provided.

The existing `insert_image_watermark` tool is retained as a soft alias delegating to `insert_watermark(image_path: ...)` — its description SHALL note the unification.

#### Scenario: Text watermark

- **WHEN** the tool is invoked with `text: "DRAFT"`
- **THEN** the watermark uses `<v:textpath>` with the text content "DRAFT"

#### Scenario: Image watermark

- **WHEN** the tool is invoked with `image_path: "/tmp/logo.png"`
- **THEN** the watermark uses an anchored shape with the image as fill, `wrapNone behindDoc='1'`

