## ADDED Requirements

### Requirement: WordDocument exposes table conditional formatting and layout mutations

The `WordDocument` model SHALL expose:

- `setTableConditionalStyle(tableIndex: Int, type: TableConditionalStyleType, properties: TableConditionalStyleProperties) throws` — emit one `<w:tblStylePr w:type="$type">` block in the table's `<w:tblPr>`. Replaces existing block of same type.
- `setTableLayout(tableIndex: Int, type: TableLayoutType) throws` — emit `<w:tblLayout w:type="$type"/>`.
- `setHeaderRow(tableIndex: Int, rowIndex: Int) throws` — emit `<w:tblHeader/>` in the row's `<w:trPr>`.
- `setTableIndent(tableIndex: Int, value: Int) throws` — emit `<w:tblInd w:w="$value" w:type="dxa"/>`.

`TableConditionalStyleType` enum: `firstRow` / `lastRow` / `firstCol` / `lastCol` / `bandedRows` / `bandedCols` / `neCell` / `nwCell` / `seCell` / `swCell`.

`TableLayoutType` enum: `fixed` / `autofit`.

`TableConditionalStyleProperties` struct: optional `bold`, `italic`, `color`, `backgroundColor`, `fontSize`.

All methods SHALL throw `WordError.invalidIndex(index)` when `tableIndex` or `rowIndex` is out of bounds.

All methods SHALL mark `word/document.xml` dirty.

#### Scenario: First-row bold

- **GIVEN** a document with one table
- **WHEN** `setTableConditionalStyle(tableIndex: 0, type: .firstRow, properties: TableConditionalStyleProperties(bold: true))` is called
- **THEN** the table's `<w:tblPr>` contains `<w:tblStylePr w:type="firstRow"><w:rPr><w:b/></w:rPr></w:tblStylePr>`

### Requirement: WordDocument supports nested table insertion

The `WordDocument` model SHALL expose `insertNestedTable(parentTableIndex: Int, rowIndex: Int, colIndex: Int, rows: Int, cols: Int) throws -> Void`.

The method SHALL throw `WordError.nestedTooDeep` when nesting would exceed depth 5 (counting from outermost table at depth 0).

The method SHALL throw `WordError.invalidIndex(index)` when any index is out of bounds.

The method SHALL mark `word/document.xml` dirty.

#### Scenario: 2-level nested table

- **GIVEN** a document with one top-level 3x3 table
- **WHEN** `insertNestedTable(parentTableIndex: 0, rowIndex: 1, colIndex: 1, rows: 2, cols: 2)` is called
- **THEN** the parent table's cell (1, 1) contains a 2x2 table in its `nestedTables` field

### Requirement: WordDocument exposes hyperlink type-aware insertion and tooltip mutation

The `WordDocument` model SHALL expose `setHyperlinkTooltip(hyperlinkId: Int, tooltip: String?) throws` — sets or clears the tooltip on an existing hyperlink identified by id.

`setHyperlinkTooltip` throws `WordError.hyperlinkNotFound(id)` when the id does not match.

The `Hyperlink` struct SHALL gain `tooltip: String?` and `history: Bool` (default `true`) fields. Reader populates from existing `w:tooltip` / `w:history` attributes; writer emits when present.

The `HyperlinkType` enum already covers `url` / `bookmark` / `email`. Writer SHALL emit `r:id` for url/email types and `w:anchor` for bookmark type.

#### Scenario: Set tooltip on existing hyperlink

- **GIVEN** a document with hyperlink id=5
- **WHEN** `setHyperlinkTooltip(hyperlinkId: 5, tooltip: "Click to visit")` is called
- **THEN** the hyperlink's XML contains `w:tooltip="Click to visit"`

### Requirement: WordDocument exposes typed header parts and clone semantics

The `WordDocument` model SHALL expose:

- `addHeaderOfType(text: String, type: HeaderFooterReferenceType) throws -> Int` — creates a new `header[N].xml` part of the given type and registers `<w:headerReference w:type="$type" r:id="$rId"/>` in the active section's sectPr; returns the assigned rId numeric portion.
- `setEvenAndOddHeaders(_ enabled: Bool)` — emit/remove `<w:evenAndOddHeaders/>` in `word/settings.xml`; mark settings.xml dirty.
- `cloneHeaderForSection(sourceFileName: String, targetSectionIndex: Int, type: HeaderFooterReferenceType) throws -> String` — copies the source header's content to a new header part, returns the new file name.

`HeaderFooterReferenceType` enum (already exists in v0.16.0 as `HeaderFooterReferences` field keys): `default` / `first` / `even`.

All methods SHALL mark relevant XML parts dirty (the new header part, plus document.xml when sectPr changes, plus settings.xml when applicable).

#### Scenario: Clone header for new section

- **GIVEN** a document with header2.xml referenced by section 0
- **WHEN** `cloneHeaderForSection(sourceFileName: "header2.xml", targetSectionIndex: 0, type: .default)` is called
- **THEN** a new file (e.g., `header3.xml`) is created with the same content as header2.xml
- **AND** `word/document.xml` and the new header file are marked dirty

