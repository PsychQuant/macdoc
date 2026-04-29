## 1. Test Fixtures and Scaffolding

- [x] 1.1 [P] Create `packages/ooxml-swift/Tests/OOXMLSwiftTests/TableAdvancedTests.swift` scaffold with helpers for building tables with conditional formatting / nested tables / header rows + asserting writer output contains expected `<w:tblStylePr>` / `<w:tblHeader>` / nested `<w:tbl>` markup
- [x] 1.2 [P] Create `packages/ooxml-swift/Tests/OOXMLSwiftTests/HyperlinkTypedTests.swift` scaffold with helpers for building docs with each of the 3 hyperlink types (URL via rId / bookmark via w:anchor / email via mailto rId) + asserting tooltip / history attributes + Hyperlink character style auto-creation
- [x] 1.3 [P] Create `packages/ooxml-swift/Tests/OOXMLSwiftTests/HeaderMultiTypeTests.swift` scaffold with helper to build doc with 3 header parts (default / first / even) + clone semantics test + evenAndOddHeaders settings flag
- [x] 1.4 [P] Create `mcp/che-word-mcp/Tests/CheWordMCPTests/TablesHyperlinksHeadersToolsTests.swift` scaffold with MCP tool invocation helpers + result-text JSON-substring assertions (mirrors `StylesNumberingSectionsToolsTests` shape)

## 2. ooxml-swift Table Model Extensions

- [x] 2.1 Table struct gains conditionalFormatting / tableLayout / tableIndent / headerRow per row + Cell struct gains nestedTables — extend `packages/ooxml-swift/Sources/OOXMLSwift/Models/Table.swift` with these fields; add `TableConditionalStyle`, `TableConditionalStyleProperties`, `TableLayoutType`, `CellWidthType`, `RowHeightRule`, `TableCellDiagonalBorders` types
- [x] 2.2 [P] DocxReader recursive parseTable for nested tables — extend `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift` to detect `<w:tbl>` inside `<w:tc>` and recurse via parseTable, depth-limited to 5 (throw `WordError.invalidDocx` on exceeding); populate `Cell.nestedTables`
- [x] 2.3 [P] DocxReader populates new Table fields — parse `<w:tblStylePr>` / `<w:tblLayout>` / `<w:tblHeader>` / `<w:tblInd>` / cell width type / row height hRule / diagonal borders
- [x] 2.4 DocxWriter emits new Table fields — extend `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxWriter.swift` (and Table.toXML) to serialize tblStylePr block / tblLayout / tblHeader / tblInd / typed cell widths / hRule / diagonal borders / nested tables

## 3. ooxml-swift Hyperlink + Header Extensions

- [x] 3.1 [P] Hyperlink struct gains tooltip / history fields — extend `packages/ooxml-swift/Sources/OOXMLSwift/Models/Hyperlink.swift`; reader populates from `w:tooltip` / `w:history` attrs; writer emits when present
- [x] 3.2 [P] Header / Footer structs gain referenceType field — add `referenceType: HeaderFooterReferenceType` (default `.default`) to `packages/ooxml-swift/Sources/OOXMLSwift/Models/Header.swift` and `Footer.swift`; reader populates from `<w:headerReference w:type>` / `<w:footerReference w:type>` (cross-reference rId to part) and writer emits in sectPr
- [x] 3.3 Document.evenAndOddHeaders field + settings.xml round-trip — extend `Document.swift` with `evenAndOddHeaders: Bool` field; reader populates from `word/settings.xml`; writer adds the part to dirty-track if present and emits `<w:evenAndOddHeaders/>`

## 4. ooxml-swift WordDocument Mutations

- [x] 4.1 [P] Table mutations: setTableConditionalStyle / setTableLayout / setHeaderRow / setTableIndent — implement the `WordDocument exposes table conditional formatting and layout mutations` requirement; each marks word/document.xml dirty; out-of-bounds throws WordError.invalidIndex
- [x] 4.2 WordDocument.insertNestedTable — implement the `WordDocument supports nested table insertion` requirement; depth-counted via parent traversal at call site; throws `WordError.nestedTooDeep` (new case) when depth would exceed 5
- [x] 4.3 [P] WordDocument.setHyperlinkTooltip + new WordError.hyperlinkNotFound — implement the `WordDocument exposes hyperlink type-aware insertion and tooltip mutation` requirement
- [x] 4.4 WordDocument header methods: addHeaderOfType / setEvenAndOddHeaders / cloneHeaderForSection — implement the `WordDocument exposes typed header parts and clone semantics` requirement; cloneHeaderForSection allocates a new file name (header[N].xml where N is max+1) and deep-copies paragraph content
- [x] 4.5 New WordError cases: nestedTooDeep / hyperlinkNotFound — add to `packages/ooxml-swift/Sources/OOXMLSwift/Errors/WordError.swift`

## 5. ooxml-swift v0.17.0 Release

- [x] 5.1 Run full ooxml-swift test suite (target: 510+ pass) + push commits + tag v0.17.0 + create GitHub release with description matching proposal Why section
- [x] 5.2 Bump `mcp/che-word-mcp/Package.swift` ooxml-swift dep from 0.16.0 to 0.17.0; run `swift package update`; verify build green

## 6. che-word-mcp Table Tools

- [x] 6.1 [P] Tool set_table_conditional_style — implement the `set_table_conditional_style applies tblStylePr by type` requirement; accepts type enum + properties object
- [x] 6.2 [P] Tool insert_nested_table — implement the `insert_nested_table places a table inside a cell` requirement; surfaces nested_too_deep error when depth would exceed 5
- [x] 6.3 [P] Tools set_table_layout + set_header_row + set_table_indent — implement the `set_table_layout switches between fixed and autofit`, `set_header_row marks a row to repeat on page break`, and `set_table_indent applies table-level left indent` requirements
- [x] 6.4 Extend merge_cells with mode argument — implement the `merge_cells supports explicit gridSpan vs vMerge mode` requirement; default mode preserves v3.10.x behavior
- [x] 6.5 [P] Extend set_table_style with diagonal_borders + extend set_cell_width / set_row_height with type / hRule — implement the `set_table_style supports diagonal cell borders` and `set_cell_width and set_row_height accept type / hRule` requirements

## 7. che-word-mcp Hyperlink Tools

- [x] 7.1 [P] Tools insert_url_hyperlink + insert_bookmark_hyperlink + insert_email_hyperlink with auto-create Hyperlink character style — implement the `insert_url_hyperlink inserts an external URL link`, `insert_bookmark_hyperlink inserts an internal anchor link`, and `insert_email_hyperlink inserts a mailto link` requirements; helper checks if `Hyperlink` style exists and creates it (color #0563C1, single underline, type character) when absent
- [x] 7.2 [P] Extend list_hyperlinks with type / tooltip / history fields per entry — implement the `list_hyperlinks surfaces type and tooltip per entry` requirement
- [x] 7.3 Mark insert_hyperlink as deprecated soft-alias for insert_url_hyperlink — annotate description with deprecation notice (removal in v4.0.0); existing callers continue to work unchanged

## 8. che-word-mcp Header Tools

- [x] 8.1 Extend add_header and add_footer with type argument — implement the `add_header and add_footer accept type argument` requirement; calling twice with same type replaces rather than duplicates
- [x] 8.2 [P] Tool enable_even_odd_headers — implement the `enable_even_odd_headers toggles the document-level flag` requirement
- [x] 8.3 [P] Tools link_section_header_to_previous + unlink_section_header_from_previous — implement the `link_section_header_to_previous shares the prior section's header XML part` and `unlink_section_header_from_previous clones the source XML part` requirements
- [x] 8.4 [P] Tool get_section_header_map — implement the `get_section_header_map returns header part assignment per section` requirement; returns array of section-to-part mappings
- [x] 8.5 Extend insert_watermark with text-vs-image discrimination + retain insert_image_watermark as alias — implement the `insert_watermark discriminates text vs image variant` requirement; mutually_exclusive error when both provided

## 9. End-to-end Tests + che-word-mcp v3.11.0 Release

- [x] 9.1 [P] Financial report E2E test in `mcp/che-word-mcp/Tests/CheWordMCPTests/MeetingMinutesE2ETests.swift` — build doc with 5x4 table; apply firstRow bold + bandedRows alternating shading + lastRow border; insert a 2x2 nested table in cell (2,2); set table layout fixed; save and re-read; verify all 4 features survive round-trip
- [x] 9.2 [P] Academic paper E2E test (same file) — insert 3 hyperlinks (URL to citation, bookmark to "Section 3", email to corresponding-author); list_hyperlinks returns all 3 with correct type field; verify Hyperlink character style was auto-created in styles.xml
- [x] 9.3 [P] Corporate proposal E2E test (same file) — add header type "first" (cover page) + header type "default" (body) + enable_even_odd_headers + add header type "even"; verify get_section_header_map returns 3 distinct header file names; verify insert_watermark with text="DRAFT" lands as v:textpath
- [x] 9.4 Update `mcp/che-word-mcp/CHANGELOG.md` with v3.11.0 entry + bump `mcp/che-word-mcp/mcpb/manifest.json` to 3.11.0 + bump psychquant-claude-plugins plugin.json analog
- [x] 9.5 Build release binary `swift build -c release` + copy to `~/bin/CheWordMCP` and `mcp/che-word-mcp/mcpb/server/CheWordMCP` + repackage `mcpb/che-word-mcp.mcpb`
- [x] 9.6 Tag v3.11.0 + push + create GitHub release with description matching CHANGELOG + upload mcpb + binary assets
- [x] 9.7 Run `/plugin-tools:plugin-update che-word-mcp` to sync marketplace.json in psychquant-claude-plugins; verify `claude plugin list` shows v3.11.0
- [x] 9.8 Close issues #49 #50 #51 via `/issue-driven-dev:idd-close` — Closing Summary references this SDD's archive path
