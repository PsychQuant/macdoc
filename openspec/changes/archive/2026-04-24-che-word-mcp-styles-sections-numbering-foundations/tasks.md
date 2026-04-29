## 1. Test Fixtures and Scaffolding

- [x] 1.1 [P] Create `packages/ooxml-swift/Tests/OOXMLSwiftTests/StylesInheritanceTests.swift` scaffold with XCTest helpers for building doc fixtures via writer + asserting basedOn / linked / next / qFormat / latentStyles round-trip
- [x] 1.2 [P] Create `packages/ooxml-swift/Tests/OOXMLSwiftTests/NumberingLifecycleTests.swift` scaffold with helper to build doc with N numIds + N referencing paragraphs (used by GC tests + create / override tests)
- [x] 1.3 [P] Create `packages/ooxml-swift/Tests/OOXMLSwiftTests/SectionPropertiesExtendedTests.swift` scaffold with helper to build doc with multiple sectPr blocks each carrying lnNumType / vAlign / pgNumType / titlePg / break-type
- [x] 1.4 [P] Create `mcp/che-word-mcp/Tests/CheWordMCPTests/StylesNumberingSectionsToolsTests.swift` scaffold with MCP tool invocation helpers + result-text JSON-substring assertions (mirrors `ContentControlToolsTests` shape)

## 2. ooxml-swift Style Model Extensions

- [x] 2.1 Style struct gains basedOn / linkedStyleId / nextStyleId / qFormat / hidden / semiHidden — extend `packages/ooxml-swift/Sources/OOXMLSwift/Models/Style.swift`'s `Style` with 6 new optional fields; default values preserve v0.15.x behavior
- [x] 2.2 [P] LatentStyle struct + Document.latentStyles collection — add `LatentStyle` (name / uiPriority / semiHidden / unhideWhenUsed / qFormat) and `WordDocument.latentStyles: [LatentStyle]` field; supports the `WordDocument exposes latentStyles management` requirement
- [x] 2.3 [P] StyleAlias struct + Style.aliases — add `StyleAlias(lang: String, name: String)` and `Style.aliases: [StyleAlias]` field for localized `<w:name>` entries; supports the `WordDocument exposes style linking and naming` requirement
- [x] 2.4 DocxReader populates new Style fields from styles.xml — extend `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift`'s style parser to read `<w:basedOn>` / `<w:link>` / `<w:next>` / `<w:qFormat/>` / `<w:hidden/>` / `<w:semiHidden/>` and the localized `<w:name>` family
- [x] 2.5 DocxReader populates Document.latentStyles from `<w:latentStyles>` block — parse `<w:lsdException>` children into LatentStyle entries
- [x] 2.6 DocxWriter emits new Style fields when present — extend `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxWriter.swift` to serialize the 6 new style attributes + alias `<w:name>` entries
- [x] 2.7 DocxWriter emits `<w:latentStyles>` block when Document.latentStyles non-empty

## 3. ooxml-swift Style WordDocument Mutations

- [x] 3.1 [P] WordDocument.getStyleInheritanceChain — implement the `WordDocument exposes style inheritance traversal` requirement; traverse basedOn references with cycle detection via visited-set
- [x] 3.2 [P] WordDocument.linkStyles — implement first half of the `WordDocument exposes style linking and naming` requirement; throws styleNotFound; marks word/styles.xml dirty
- [x] 3.3 [P] WordDocument.addStyleNameAlias — implement second half of the `WordDocument exposes style linking and naming` requirement; replaces existing alias for same lang
- [x] 3.4 [P] WordDocument.setLatentStyles — implement the mutator from `WordDocument exposes latentStyles management`; replaces collection wholesale; marks word/styles.xml dirty
- [x] 3.5 New WordError cases: styleNotFound / typeMismatch / numIdNotFound — add to `packages/ooxml-swift/Sources/OOXMLSwift/Errors/WordError.swift`

## 4. ooxml-swift Numbering Extensions

- [x] 4.1 WordDocument.createNumberingDefinition — implement first part of `WordDocument exposes numbering definition lifecycle` requirement; max 9 levels; returns new numId; marks word/numbering.xml dirty
- [x] 4.2 WordDocument.overrideNumberingLevel — emit `<w:lvlOverride>`; throws numIdNotFound; marks word/numbering.xml dirty
- [x] 4.3 WordDocument.assignNumberingToParagraph — adds `<w:numPr>` to paragraph; marks both word/numbering.xml AND word/document.xml dirty
- [x] 4.4 [P] WordDocument.continueList — assigns existing num_id to a new paragraph (one-line wrapper around assignNumberingToParagraph)
- [x] 4.5 [P] WordDocument.startNewList — creates new num referencing existing abstractNum, then assigns to paragraph
- [x] 4.6 WordDocument.gcOrphanNumbering — implement final part of `WordDocument exposes numbering definition lifecycle` requirement; scans paragraphs (including tables and block-level SDTs) for numId references; deletes unreferenced `<w:num>` (NOT abstractNums); returns deleted ids in order

## 5. ooxml-swift Section Extensions

- [x] 5.1 LineNumbers / VerticalAlignment / PageNumberFormat / LineNumberRestart types — add to `packages/ooxml-swift/Sources/OOXMLSwift/Models/Section.swift`; SectionProperties gains lineNumbers / verticalAlignment / pageNumberFormat / titlePageDistinct fields; supports the `WordDocument exposes section property extensions` requirement
- [x] 5.2 DocxReader populates new SectionProperties fields — parse `<w:lnNumType>` / `<w:vAlign>` / `<w:pgNumType w:fmt>` / `<w:titlePg/>` / `<w:type>` from sectPr
- [x] 5.3 DocxWriter emits new sectPr children — serialize the 5 new types
- [x] 5.4 WordDocument.setSectionLineNumbers / setSectionVerticalAlignment / setSectionPageNumberFormat / setSectionBreakType / setTitlePageDistinct — 5 sibling mutators; each throws invalidIndex on out-of-bounds section_index; each marks word/document.xml dirty (sectPr lives inside document.xml)
- [x] 5.5 WordDocument.getAllSections — return SectionInfo array per `WordDocument exposes section property extensions` scenario; one entry per section in document order with paragraph_range + sectPr summary

## 6. ooxml-swift v0.16.0 Release

- [x] 6.1 Run full ooxml-swift test suite (target: 510+ pass) + push commits + tag v0.16.0 + create GitHub release with description matching proposal Why section
- [x] 6.2 Bump `mcp/che-word-mcp/Package.swift` ooxml-swift dep from 0.15.1 to 0.16.0; run `swift package update`; verify build green

## 7. che-word-mcp Style Tools

- [x] 7.1 Extend create_style with 6 new args + extend update_style with same args — implement the `create_style accepts inheritance and gallery args` and `update_style accepts inheritance and gallery args` requirements; passing q_format / hidden / semi_hidden = false on update_style removes the corresponding XML element
- [x] 7.2 [P] Tool get_style_inheritance_chain — register MCP tool implementing the `get_style_inheritance_chain returns ancestor chain` requirement; supports both doc_id and source_path; returns cycle_detected flag when chain repeats
- [x] 7.3 [P] Tool link_styles — register MCP tool implementing the `link_styles binds paragraph and character styles` requirement; surfaces type_mismatch error when style types don't match expected
- [x] 7.4 [P] Tool set_latent_styles + add_style_name_alias — register both MCP tools implementing the `set_latent_styles configures Quick Style Gallery defaults` and `add_style_name_alias adds a localized name to a style` requirements

## 8. che-word-mcp Numbering Tools

- [x] 8.1 [P] Tools list_numbering_definitions + get_numbering_definition — implement the `list_numbering_definitions enumerates abstractNum and num pairs` and `get_numbering_definition fetches one num by id` requirements; returns array of num entries with abstract_num_id + levels details
- [x] 8.2 [P] Tools create_numbering_definition + override_numbering_level — implement the `create_numbering_definition adds a new abstractNum and num` and `override_numbering_level sets level start value` requirements; surfaces invalid_levels and not_found errors
- [x] 8.3 [P] Tools assign_numbering_to_paragraph + continue_list + start_new_list — implement the `assign_numbering_to_paragraph attaches numId to paragraph` and `continue_list and start_new_list manage list continuity` requirements
- [x] 8.4 [P] Tool gc_orphan_numbering — implement the `gc_orphan_numbering removes unreferenced num definitions` requirement; returns array of deleted num_ids

## 9. che-word-mcp Section Tools

- [x] 9.1 [P] Tools set_line_numbers_for_section + set_section_vertical_alignment — implement the `set_line_numbers_for_section enables line numbering on a section` and `set_section_vertical_alignment sets vertical alignment` requirements
- [x] 9.2 [P] Tools set_page_number_format + set_section_break_type — implement the `set_page_number_format sets page number style and start` and `set_section_break_type changes the section break` requirements
- [x] 9.3 [P] Tools set_title_page_distinct + set_section_header_footer_references — implement the `set_title_page_distinct toggles per-section first-page header` and `set_section_header_footer_references assigns header / footer parts` requirements; latter surfaces relationship_not_found error
- [x] 9.4 [P] Tool get_all_sections — implement the `get_all_sections returns every section's properties summary` requirement; supports both doc_id and source_path

## 10. End-to-end Tests + che-word-mcp v3.10.0 Release

- [x] 10.1 [P] Corporate template E2E test in `mcp/che-word-mcp/Tests/CheWordMCPTests/CorporateTemplateE2ETests.swift` — build doc with 3-level Heading inheritance (basedOn) + qFormat + linked paragraph/character styles + latentStyles hiding Heading 9; save and re-read via list_styles; verify all 4 features survive round-trip
- [x] 10.2 [P] Academic preface E2E test (same file) — build doc with section 0 (Roman numerals + line numbers + center vAlign) and section 1 (decimal + nextPage break); save and verify get_all_sections returns 2 entries with correct page_number_format and break_type
- [x] 10.3 [P] Tiered list E2E test (same file) — create 3-level numbering definition via create_numbering_definition; assign 3 paragraphs at levels 0/1/2; override level 0 start; gc_orphan_numbering returns empty (all num_ids referenced)
- [x] 10.4 Update `mcp/che-word-mcp/CHANGELOG.md` with v3.10.0 entry + bump `mcp/che-word-mcp/mcpb/manifest.json` to 3.10.0 + bump `mcp/che-word-mcp/.claude-plugin/plugin.json` analog + update tool count refs in README
- [x] 10.5 Build release binary `swift build -c release` + copy to `~/bin/CheWordMCP` and `mcp/che-word-mcp/mcpb/server/CheWordMCP` + repackage `mcpb/che-word-mcp.mcpb`
- [x] 10.6 Tag v3.10.0 + push + create GitHub release with description matching CHANGELOG + upload mcpb + binary assets
- [x] 10.7 Run `/plugin-tools:plugin-update che-word-mcp` to sync marketplace.json in psychquant-claude-plugins; verify `claude plugin list` shows v3.10.0
- [x] 10.8 Close issues #46 #47 #48 via `/issue-driven-dev:idd-close` for each — Closing Summary references this SDD's archive path
