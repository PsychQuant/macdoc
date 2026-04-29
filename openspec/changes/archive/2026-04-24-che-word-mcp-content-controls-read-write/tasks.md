## 1. Test Fixture and Scaffolding

- [x] 1.1 [P] Build `packages/ooxml-swift/Tests/OOXMLSwiftTests/Fixtures/sdt-template.docx` — a Word-generated document containing one SDT per supported type (11 SDTs: richText, text, picture, date, dropDownList, comboBox, checkbox, bibliography, citation, group, repeatingSection with 3 items), covering nested Group→PlainText and block-level SDT cases
- [x] 1.2 [P] Create `packages/ooxml-swift/Tests/OOXMLSwiftTests/SDTParserTests.swift` scaffold with XCTest fixture loader and helper to assert parsed ContentControl equality
- [x] 1.3 [P] Create `mcp/che-word-mcp/Tests/CheWordMCPTests/ContentControlToolsTests.swift` scaffold with MCP tool invocation helper and fixture loading

## 2. ooxml-swift Model Layer

- [x] 2.1 [P] ContentControl model supports nested children — extend `Models/Field.swift` `ContentControl` struct with `children: [ContentControl]` and `parentSdtId: Int?` fields, update factory methods and `toXML()` to serialize children in order
- [x] 2.2 [P] RepeatingSection model supports item-level update + RepeatingSection emits allowInsertDeleteSections attribute — add `updateItem(atIndex:newText:)` method and `allowInsertDeleteSections: Bool` property (default true) to RepeatingSection struct, emit `<w15:repeatingSection w15:allowInsertDeleteSections="0|1"/>` in `toSdtPrXML()`
- [x] 2.3 WordDocument.allocateSdtId uses max-plus-one strategy — add `allocateSdtId() -> Int` method to `Models/Document.swift` that scans all SDT ids across body/tables/headers/footers/comments and returns max+1 (or 1 when empty), with per-session cache invalidated on disk re-read

## 3. DocxReader SDT Parser

- [x] 3.0 [PREREQUISITE] Refactor `WordDocument.insertContentControl` to produce proper Word XML structure — the existing implementation at `Sources/OOXMLSwift/Models/Document.swift:2295-2310` wraps the entire `<w:sdt>...</w:sdt>` XML inside `Run.rawXML`, producing malformed `<w:p><w:r><w:sdt>...</w:sdt></w:r></w:p>` (SDT inside Run). Refactor to produce `<w:p><w:sdt>...</w:sdt></w:p>` (SDT as direct child of paragraph, sibling of runs). Add `Paragraph.contentControls: [ContentControl]` field; `Paragraph.toXML()` emits SDT XML in source-document order; update `insertContentControl` to set `paragraph.contentControls = [control]` instead of stuffing into Run.rawXML. Update `SDTFixtureBuilder` to verify proper structure. **Rationale**: Phase 3 SDTParser spec scenarios assume proper structure (`<w:p><w:sdt>...`); without this prerequisite, parser would never see the existing fixture's SDTs (they'd be hidden inside Run.rawXML/rawElements). Backward-compat: SDTs were write-only before this SDD, so no existing readers rely on the malformed shape; existing on-disk SDTs get migrated automatically when re-saved through the new writer.
- [x] 3.1 DocxReader parses w:sdt into structured ContentControl values — DocxReader SDT parser attaches SDTs as a first-class Paragraph child, not a Run.rawXML blob. Implement `SDTParser` in new file `packages/ooxml-swift/Sources/OOXMLSwift/IO/SDTParser.swift`, hook into DocxReader's paragraph element walker to detect `<w:sdt>` siblings
- [x] 3.2 SDTParser distinguishes all 12 SDT types — implement type discrimination by inspecting `<w:sdtPr>` children (`<w:text/>`, `<w:picture/>`, `<w:date>`, `<w:dropDownList>`, `<w:comboBox>`, `<w14:checkbox>`, `<w:bibliography/>`, `<w:citation/>`, `<w:group/>`, `<w15:repeatingSection>`, `<w15:repeatingSectionItem>`; default richText when absent)
- [x] 3.3 SDTParser handles nested SDTs by preserving tree structure — SDT parse in DocxReader handles nested SDTs by preserving tree structure, recursively parsing `<w:sdt>` inside `<w:sdtContent>`, populating `children: [ContentControl]` and `parentSdtId` on each nested entry
- [x] 3.4 SDTParser handles block-level SDTs wrapping paragraphs and tables — detect `<w:sdt>` directly inside `<w:body>` or `<w:tc>`, produce block-level ContentControl container with child BodyElements preserving original order
- [x] 3.5 SDT round-trip preserves byte-level content fidelity — add round-trip test in SDTParserTests using the `sdt-template.docx` fixture, verify id/tag/alias/type marker/lockType/placeholder match between input and output, open output in Word 2021+ manually to confirm no error dialog

## 4. WordDocument Mutation Methods

- [x] 4.1 [P] WordDocument.updateContentControl modifies SDT text content by id — add method that locates ContentControl by id, replaces text runs with single run containing newText, preserves `<w:sdtPr>` untouched, throws `contentControlNotFound` or `unsupportedSDTType` errors
- [x] 4.2 [P] WordDocument.replaceContentControlContent replaces full content XML — add method that validates input XML against element whitelist (reject `<w:sdt>`, `<w:body>`, `<w:sectPr>`, XML declaration), throws `disallowedElement(name)`, replaces `<w:sdtContent>` region of target SDT
- [x] 4.3 [P] WordDocument.deleteContentControl removes SDT with optional content preservation — add method with `keepContent: Bool = true` param, unwraps children into parent container when true, removes SDT and children when false, throws `contentControlNotFound` on unknown id

## 5. che-word-mcp Read Tools

- [x] 5.1 [P] Tool list_content_controls enumerates SDTs in a document — register MCP tool accepting `doc_id` or `source_path` plus optional `nested: bool`, flat mode returns list with `parentSdtId`, nested mode returns tree with `children`, each entry includes id/tag/alias/type/lockType/currentText/paragraphIndex
- [x] 5.2 [P] Tool get_content_control fetches a single SDT by id, tag, or alias — register MCP tool requiring exactly one of {id, tag, alias}, return full metadata + `<w:sdtContent>` XML, error `not_found` when missing, error `multiple_matches` when tag/alias ambiguous
- [x] 5.3 [P] Tool list_repeating_section_items enumerates items of a repeating section SDT — register MCP tool accepting `doc_id` + `id`, return array of item entries each with item SDT id, item-level tag, current text content in document order

## 6. che-word-mcp Write Tools

- [x] 6.1 [P] Tool update_content_control_text modifies plain-text SDT content — register MCP tool accepting `doc_id` + `id` + `text`, call `WordDocument.updateContentControl`, return `unsupported_type` error for picture/dropDownList/comboBox/checkbox/group/repeatingSection targets
- [x] 6.2 [P] Tool replace_content_control_content replaces rich-text SDT content — register MCP tool accepting `doc_id` + `id` + `content_xml`, delegate to WordDocument method with XML whitelist validation, surface `disallowed_element` error
- [x] 6.3 [P] Tool delete_content_control removes SDT with optional content preservation — register MCP tool accepting `doc_id` + `id` + optional `keep_content: bool` (default true), delegate to WordDocument.deleteContentControl
- [x] 6.4 [P] Tool update_repeating_section_item modifies a single item's content — register MCP tool accepting `doc_id` + `parent_id` + `item_index` + `text`, call `RepeatingSection.updateItem`, surface `out_of_bounds` error for invalid index

## 7. che-word-mcp Tool Extensions

- [x] 7.1 Tool insert_content_control accepts advanced SDT types and extended args + Repeating section stays separate from insert_content_control — extend args schema with `list_items`/`date_format`/`lock_type`, add 4 new types (bibliography/citation/group/repeatingSectionItem), explicitly reject `type: "repeatingSection"` with error message directing caller to `insert_repeating_section`
- [x] 7.2 Tool insert_repeating_section supports allow_insert_delete_sections arg — extend args schema with optional `allow_insert_delete_sections: bool` (default true), wire to RepeatingSection property
- [x] 7.3 SDT id allocation uses scan-max + 1 — replace `Int.random(in: 100000...999999)` call at `mcp/che-word-mcp/Sources/CheWordMCP/Server.swift:8393` with `doc.allocateSdtId()` in insertContentControl and insertRepeatingSection

## 8. Stub Tool and Release

- [x] 8.1 Tool list_custom_xml_parts returns empty stub + list_custom_xml_parts ships as an empty-list stub — register MCP tool returning `[]` with schema declaring future return type (array of `{store_item_id, target_namespaces, root_element}`), add TODO comment referencing Change B (`che-word-mcp-customxml-databinding`)
- [x] 8.2 End-to-end fixture test — create invoice template with 8 content controls (client_name, date, invoice_number, plus repeating section with item_description/quantity/price/subtotal), fill via tool chain (list → update_text → list), save via `save_document`, reopen in Word 2021+ to verify no error dialog
- [x] 8.3 Release: ooxml-swift minor version bump + che-word-mcp v3.8.0 — update ooxml-swift Package.swift version, tag `v0.14.0`, push; update `mcpb/manifest.json` version + `CHANGELOG.md` + `README.md` tool count (145 → 155+); rebuild binary, copy to `~/bin/CheWordMCP` and `mcpb/server/`, create v3.8.0 GitHub release + upload mcpb asset; run `/plugin-update che-word-mcp` for marketplace sync
