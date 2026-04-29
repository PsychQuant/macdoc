## Why

che-word-mcp v3.10.0 just shipped the Office.js Roadmap P0 foundation triplet (#46 Numbering / #47 Sections / #48 Styles). With styles inheritance + sectPr completeness in place, the next dependent triplet — **Tables / Hyperlinks / Headers** — becomes implementable without temporary stubs. These three issues all ride on top of the v3.10.0 foundation:

- **#49 Tables 進階** — `set_table_conditional_style` and `set_table_style` need to reference paragraph/character styles created via the v3.10.0 styles tools. Existing `Table.swift` (465L) covers basic CRUD, but lacks: conditional formatting (`<w:tblStylePr w:type="firstRow|lastRow|bandedRows">`), nested tables (table-in-cell), header row repetition (`<w:tblHeader/>`), table layout mode (`<w:tblLayout w:type="fixed|autofit"/>`), table-level indent (`<w:tblInd>`), diagonal cell borders (`<w:tl2br>` / `<w:tr2bl>`), explicit gridSpan vs vMerge semantics, type variants for cell width (`dxa|pct|auto`) and row height (`exact|atLeast`).
- **#50 Hyperlinks 完整支援** — current `Hyperlink.swift` (120L) supports URL hyperlinks but conflates 3 distinct target types (external URL via rId, internal bookmark via `w:anchor`, email via `mailto:` rId). Missing: explicit per-type tools, `w:tooltip` attribute (mouse-hover hint), `w:history='0'` to skip "visited" tracking, automatic `Hyperlink` character style creation (the v3.10.0 `link_styles` tool now makes this clean).
- **#51 Headers/Footers 多類型** — current `add_header` / `update_header` (in `che-word-mcp-headers-footers-tools` capability) supports only `default` type. The OOXML model `<w:headerReference w:type="default|first|even"/>` allows three header XML parts per section. v3.10.0 already shipped `set_title_page_distinct` (`<w:titlePg/>`) and `set_section_header_footer_references` (per-type rId assignment), so #51 reduces to: `add_header(type:)` extension, `enable_even_odd_headers` (settings.xml flag), `link_section_header_to_previous` / `unlink_section_header_from_previous` (clone semantics), `get_section_header_map`, plus watermark text vs image discrimination.

Bundling all three lets us share one ooxml-swift release ceremony (v0.17.0) plus reuse the v3.10.0 dirty-tracking discipline pattern across `word/document.xml` (tables / hyperlinks live in body), `word/header[N].xml` (per-instance header parts), and `word/settings.xml` (evenAndOddHeaders flag). Splitting would force three back-to-back patch releases for related work.

## What Changes

### Phase 1 — ooxml-swift v0.17.0 (model + WordDocument extensions)

**Table extensions:**
- `Table` model gains `conditionalFormatting: [TableConditionalStyle]`, `nestedTables` (handled via existing `cell.paragraphs` recursion since cells already hold body content), `headerRow: Bool`, `tableLayout: TableLayout`, `tableIndent: Int?`, `diagonalBorders: TableCellDiagonalBorders?` per cell.
- New types: `TableConditionalStyle` (type + properties), `TableLayoutType` enum (`fixed` / `autofit`), `CellWidthType` enum (`dxa` / `pct` / `auto`), `RowHeightRule` enum (`exact` / `atLeast`).
- `Cell` model gets `nestedTables: [Table]` field — distinct from `paragraphs` so reader can populate cells containing `<w:tbl>` directly.
- Reader: `parseTable` becomes recursive (depth-limited to 5 — see design.md decision 1) when encountering `<w:tbl>` inside `<w:tc>`.
- Writer: emit new attributes; `tblStylePr` block.

**Hyperlink extensions:**
- `Hyperlink` model gains `tooltip: String?`, `history: Bool` (default `true` — Word default behavior).
- `HyperlinkType` enum already exists with `url` / `bookmark` / `email` cases — make sure all three are surfaced via writer attribute discipline (`r:id` for url/email, `w:anchor` for bookmark).
- Reader populates new fields from existing element.

**Header extensions:**
- `Header` and `Footer` already have `fileName` field (e.g., `header1.xml`). Add `referenceType: HeaderFooterReferenceType` (`default` / `first` / `even`) so a section can have multiple header parts of distinct types.
- New `Document.evenAndOddHeaders: Bool` field — written into `word/settings.xml` `<w:evenAndOddHeaders/>`.
- New helper: `Document.cloneHeaderForSection(sourceFileName:type:)` for `link_to_previous` semantics.

**WordDocument mutations (~9 new methods):**
- Table: `setTableConditionalStyle`, `setTableLayout`, `setHeaderRow`, `setTableIndent`, `insertNestedTable`.
- Hyperlink: `setHyperlinkTooltip` (modifies existing hyperlink in place by id).
- Header: `addHeaderOfType`, `setEvenAndOddHeaders`, `cloneHeaderForSection`.

All mutations explicitly mark the relevant `word/<part>.xml` dirty.

### Phase 2 — che-word-mcp v3.11.0 (~19 new MCP tools)

**Table tools (8):**
- `set_table_conditional_style` (apply firstRow / lastRow / firstCol / lastCol / bandedRows / bandedCols)
- `insert_nested_table` (parent table + cell ref + new table dims)
- `set_table_layout` (fixed vs autofit)
- `set_header_row` (`<w:tblHeader/>` for repeat-on-page-break)
- `set_table_indent` (table-level indent)
- `merge_cells` extended with explicit `mode: gridSpan|vMerge` argument
- `set_table_style` extended with `diagonal_borders: { tl2br: bool, tr2bl: bool }`
- `set_cell_width` extended with `type: dxa|pct|auto`; `set_row_height` extended with `h_rule: exact|atLeast`

**Hyperlink tools (3 new + 1 extended):**
- `insert_url_hyperlink(url, text, tooltip?, history?)`
- `insert_bookmark_hyperlink(anchor, text, tooltip?)`
- `insert_email_hyperlink(email, text, tooltip?)`
- `list_hyperlinks` extended to surface `type` (url / bookmark / email) and `tooltip` per entry
- (Existing `insert_hyperlink` retained as deprecated soft-alias delegating to `insert_url_hyperlink` — emits warning in description, removed in v4.0.0)

**Header tools (6):**
- `add_header` extended with `type: default|first|even` argument
- `add_footer` extended with same
- `enable_even_odd_headers` (settings.xml flag)
- `link_section_header_to_previous(section_index, type)` — re-uses the v3.10.0 `set_section_header_footer_references` API but with cross-section rId resolution
- `unlink_section_header_from_previous(section_index, type)` — clones the source header XML part, gives the section its own
- `get_section_header_map` — returns which section uses which header XML part for which type
- `insert_watermark` / `insert_image_watermark` extended to discriminate text-via-`<v:textpath>` vs image-via-anchored-shape

### Phase 3 — Release ceremony

- ooxml-swift v0.17.0 push + tag + GitHub release
- che-word-mcp v3.11.0 build, install, mcpb package, GitHub release
- psychquant-claude-plugins marketplace.json sync
- Close #49 #50 #51 via `/idd-close`

## Non-Goals

- **#43 §15 Theme deeper integration** — theme references are out of scope; v3.10.0 already covers basic theme CRUD.
- **#43 §17 Bookmarks 進階 + cross-references** — `insert_bookmark_hyperlink` consumes existing bookmarks but does NOT create new ones. Bookmark mutation tools belong to a separate SDD.
- **Multi-section split (more than one section per document)** — v3.10.0 already exposed the API surface (sectionIndex param) but with single-section limitation. Multi-section split is its own architectural change.
- **Track Changes for Tables / Hyperlinks / Headers (`<w:tblPrChange>` / `<w:rPrChange>` for hyperlink runs)** — covered by #45 (separate SDD).
- **Cross-document hyperlink validation** (does the URL resolve? does the bookmark exist in target doc?) — out of scope; the tools accept any string.
- **Header/footer image extraction** — `list_images` already covers body images; header image extraction is a separate concern not requested by #51.
- **Watermark image cropping or rotation** — `insert_image_watermark` accepts an existing image; transformations are out of scope.

## Capabilities

### New Capabilities

- `che-word-mcp-tables-tools`: 8 new MCP tools for advanced table operations (conditional formatting / nested tables / layout / header row / indent / diagonal borders / explicit merge modes / typed widths)
- `che-word-mcp-hyperlinks-tools`: 3 new typed hyperlink tools + extended `list_hyperlinks` with type discrimination

### Modified Capabilities

- `che-word-mcp-headers-footers-tools`: extends `add_header` / `add_footer` with `type: default|first|even`, adds 5 new tools (`enable_even_odd_headers` / `link_section_header_to_previous` / `unlink_section_header_from_previous` / `get_section_header_map` / watermark text-vs-image discrimination on existing `insert_watermark`)
- `ooxml-document-part-mutations`: extends with 9 new WordDocument methods covering Table / Hyperlink / Header mutations, all using consistent dirty-tracking discipline established in v0.16.0

## Impact

- Affected specs:
  - New: `openspec/specs/che-word-mcp-tables-tools/spec.md`
  - New: `openspec/specs/che-word-mcp-hyperlinks-tools/spec.md`
  - Modified: `openspec/specs/che-word-mcp-headers-footers-tools/spec.md`
  - Modified: `openspec/specs/ooxml-document-part-mutations/spec.md`
- Affected code:
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Table.swift` (add conditional formatting / layout / header row / indent / diagonal borders / nested table cell field)
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Hyperlink.swift` (add tooltip + history fields)
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Header.swift` (add referenceType field)
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Footer.swift` (add referenceType field)
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift` (add 9 new mutation methods, all explicitly marking relevant XML parts dirty)
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift` (recursive parseTable for nested tables; parse new attributes)
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxWriter.swift` (emit new attributes; tblStylePr block; cloned header XML parts)
  - Modified: `mcp/che-word-mcp/Sources/CheWordMCP/Server.swift` (register 19 new tools + dispatcher cases + helper functions; extend 4 existing tools)
  - Modified: `packages/ooxml-swift/Package.swift` (version bump to 0.17.0)
  - Modified: `mcp/che-word-mcp/Package.swift` (ooxml-swift dep bump to 0.17.0)
  - Modified: `mcp/che-word-mcp/mcpb/manifest.json` (version 3.11.0)
  - Modified: `mcp/che-word-mcp/CHANGELOG.md` (v3.11.0 entry)
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/TableAdvancedTests.swift`
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/HyperlinkTypedTests.swift`
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/HeaderMultiTypeTests.swift`
  - New: `mcp/che-word-mcp/Tests/CheWordMCPTests/TablesHyperlinksHeadersToolsTests.swift`
  - New: `mcp/che-word-mcp/Tests/CheWordMCPTests/MeetingMinutesE2ETests.swift`
