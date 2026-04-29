## ADDED Requirements

### Requirement: set_table_conditional_style applies tblStylePr by type

The MCP tool `set_table_conditional_style` SHALL accept `doc_id` + `table_index` + `type` (one of `firstRow` / `lastRow` / `firstCol` / `lastCol` / `bandedRows` / `bandedCols` / `neCell` / `nwCell` / `seCell` / `swCell`) + `properties` (object with `bold`, `italic`, `color`, `background_color`, `font_size`).

The tool SHALL emit one `<w:tblStylePr w:type="$type">` block inside the table's `<w:tblPr>` containing `<w:rPr>` and `<w:tcPr>` properties as appropriate for the supplied properties.

The tool SHALL replace any existing `<w:tblStylePr>` block of the same type rather than duplicating.

The tool SHALL return error `out_of_bounds` when `table_index` is invalid.

#### Scenario: First row bold

- **WHEN** the tool is invoked with `table_index: 0, type: "firstRow", properties: {bold: true}`
- **THEN** the table's `<w:tblPr>` contains `<w:tblStylePr w:type="firstRow"><w:rPr><w:b/></w:rPr></w:tblStylePr>`

### Requirement: insert_nested_table places a table inside a cell

The MCP tool `insert_nested_table` SHALL accept `doc_id` + `parent_table_index` + `row_index` + `col_index` + `rows` + `cols` and create a new table inside the target cell.

The tool SHALL throw `out_of_bounds` when `parent_table_index` / `row_index` / `col_index` is invalid.

The tool SHALL throw `nested_too_deep` when nesting would exceed depth 5.

#### Scenario: 2-level nesting

- **GIVEN** a document with one top-level 3x3 table
- **WHEN** the tool is invoked with `parent_table_index: 0, row_index: 1, col_index: 1, rows: 2, cols: 2`
- **THEN** cell (1, 1) of the parent table contains a 2x2 table

### Requirement: set_table_layout switches between fixed and autofit

The MCP tool `set_table_layout` SHALL accept `doc_id` + `table_index` + `type` (one of `fixed` / `autofit`) and emit `<w:tblLayout w:type="$type"/>` in the table's `<w:tblPr>`.

#### Scenario: Fix layout

- **WHEN** the tool is invoked with `table_index: 0, type: "fixed"`
- **THEN** the table's `<w:tblPr>` contains `<w:tblLayout w:type="fixed"/>`

### Requirement: set_header_row marks a row to repeat on page break

The MCP tool `set_header_row` SHALL accept `doc_id` + `table_index` + `row_index` and emit `<w:tblHeader/>` in the row's `<w:trPr>`.

When `row_index` is omitted, the tool SHALL default to row 0.

#### Scenario: Repeat header on page break

- **WHEN** the tool is invoked with `table_index: 0, row_index: 0`
- **THEN** the row's `<w:trPr>` contains `<w:tblHeader/>`

### Requirement: set_table_indent applies table-level left indent

The MCP tool `set_table_indent` SHALL accept `doc_id` + `table_index` + `value` (twips) and emit `<w:tblInd w:w="$value" w:type="dxa"/>` in `<w:tblPr>`.

#### Scenario: Indent table by 720 twips

- **WHEN** the tool is invoked with `table_index: 0, value: 720`
- **THEN** the table's `<w:tblPr>` contains `<w:tblInd w:w="720" w:type="dxa"/>`

### Requirement: merge_cells supports explicit gridSpan vs vMerge mode

The MCP tool `merge_cells` SHALL accept an optional `mode: "gridSpan" | "vMerge"` argument (default `"gridSpan"` for backwards compatibility).

When `mode == "vMerge"`, the tool SHALL emit `<w:vMerge w:val="restart"/>` on the start cell and `<w:vMerge/>` on continuation cells.

When `mode == "gridSpan"`, the tool SHALL emit `<w:gridSpan w:val="$count"/>` on the start cell.

#### Scenario: Vertical merge

- **WHEN** the tool is invoked with `table_index: 0, start_row: 0, end_row: 2, col: 1, mode: "vMerge"`
- **THEN** cell (0, 1) has `<w:vMerge w:val="restart"/>`
- **AND** cells (1, 1) and (2, 1) have `<w:vMerge/>`

### Requirement: set_table_style supports diagonal cell borders

The MCP tool `set_table_style` SHALL accept an optional `diagonal_borders: { tl2br: bool, tr2bl: bool }` argument that emits `<w:tcBorders><w:tl2br>` and/or `<w:tcBorders><w:tr2bl>` per cell.

#### Scenario: Top-left to bottom-right diagonal

- **WHEN** the tool is invoked with `table_index: 0, diagonal_borders: { tl2br: true, tr2bl: false }`
- **THEN** every cell's `<w:tcBorders>` contains `<w:tl2br w:val="single" w:sz="4"/>`

### Requirement: set_cell_width and set_row_height accept type / hRule

The MCP tool `set_cell_width` SHALL accept an optional `type: "dxa" | "pct" | "auto"` argument (default `"dxa"`).

The MCP tool `set_row_height` SHALL accept an optional `h_rule: "exact" | "atLeast"` argument (default `"atLeast"`).

#### Scenario: Percentage cell width

- **WHEN** `set_cell_width` is invoked with `value: 5000, type: "pct"`
- **THEN** the cell's `<w:tcPr>` contains `<w:tcW w:w="5000" w:type="pct"/>` (50.00% in 1/50ths of a percent)

