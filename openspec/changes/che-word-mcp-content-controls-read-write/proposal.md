## Why

che-word-mcp ships 1 write-only tool for Structured Document Tags (`insert_content_control`, plus a standalone `insert_repeating_section`), but zero read/update/delete coverage. Current `insertContentControl` shoves the entire SDT XML as a `Run.rawXML` blob (Document.swift:2259-2263), and `DocxReader` never parses `<w:sdt>` back into a structured `ContentControl` — so the SDT exists on disk but is invisible to the tool layer once the document is re-opened.

This blocks the primary use case for Content Controls: **template-driven document automation**. A caller cannot list the SDTs in a template, locate a specific one by tag, or update its content without walking raw XML in userland. It also blocks downstream features (§22 Bibliography roadmap item) that will reuse SDT infrastructure.

Change A covers full CRUD over SDTs plus the missing advanced SDT types. Change B (separate, not in scope here) will add `/customXml/` part management and `<w:dataBinding>` for XPath-bound templates.

## What Changes

- **NEW** DocxReader parses `<w:sdt>` elements into structured `ContentControl` values, not `Run.rawXML` blobs. Existing write-path round-trip behavior is preserved; read-path gains first-class SDT visibility.
- **NEW** 8 che-word-mcp tools: `list_content_controls`, `get_content_control`, `update_content_control_text`, `replace_content_control_content`, `delete_content_control`, `list_repeating_section_items`, `update_repeating_section_item`, `list_custom_xml_parts` (stub returning empty list; Change B will populate).
- **MODIFIED** `insert_content_control` adds 4 SDT types (bibliography, citation, group, repeatingSectionItem) plus args `list_items` (dropdown/comboBox), `date_format` (date), `lock_type` (all types). Non-breaking — all new args optional.
- **MODIFIED** `insert_repeating_section` adds optional `allow_insert_delete_sections` arg (default true preserves existing behavior). Non-breaking.
- **MODIFIED** SDT id allocation strategy changes from `Int.random(100000...999999)` to "scan existing max id + 1" (Server.swift:8393). Eliminates the collision window for documents with many SDTs.
- **NEW** `WordDocument.updateContentControl(id:newText:)`, `replaceContentControlContent(id:contentXML:)`, `deleteContentControl(id:keepContent:)` methods on the ooxml-swift model layer.
- `insert_repeating_section` stays a separate tool from `insert_content_control`. Their argument shapes differ (items array vs single content, section_title vs alias) and merging would force a tagged-union schema more awkward than two tools.

## Non-Goals

- **Data binding (`<w:dataBinding>`).** No `bind_content_control` tool, no `/customXml/` part management, no `[Content_Types].xml` customXml registration. That infrastructure is Change B (`che-word-mcp-customxml-databinding`) and will also serve §22 Bibliography.
- **Bibliography-specific API.** Although this change adds `bibliography` and `citation` as SDT types, it does NOT add typed APIs for `<b:Source>` management. §22 Bibliography is a separate future change.
- **Regex-based SDT search over rawXML as a fallback.** Rejected in discuss — the real DocxReader parser is the foundation. Regex search would become technical debt once the parser lands.
- **Merging `insert_repeating_section` into `insert_content_control`.** Rejected — argument shapes differ substantively; merging would force a polymorphic schema less ergonomic than two tools.
- **New specs.** No new capabilities introduced. All changes attach to three existing capabilities.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `che-word-mcp-insertion-tools`: adds 8 new tools (list/get/update/replace/delete for content controls, list/update for repeating section items, list_custom_xml_parts stub) and extends `insert_content_control` / `insert_repeating_section` args.
- `ooxml-read-back-parsers`: DocxReader gains a structured SDT parser that replaces rawXML blob preservation for `<w:sdt>` elements, surfacing SDT metadata (tag/alias/type/lockType/placeholder/currentContent) to callers.
- `ooxml-content-insertion-primitives`: WordDocument gains update/replace/delete methods for content controls by id, plus a max-id allocator for collision-free SDT ids.

## Impact

- Affected specs:
  - openspec/specs/che-word-mcp-insertion-tools/spec.md
  - openspec/specs/ooxml-read-back-parsers/spec.md
  - openspec/specs/ooxml-content-insertion-primitives/spec.md
- Affected code:
  - Modified: packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift
  - Modified: packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift
  - Modified: packages/ooxml-swift/Sources/OOXMLSwift/Models/Field.swift
  - Modified: mcp/che-word-mcp/Sources/CheWordMCP/Server.swift
  - New: packages/ooxml-swift/Tests/OOXMLSwiftTests/SDTParserTests.swift
  - New: packages/ooxml-swift/Tests/OOXMLSwiftTests/Fixtures/sdt-template.docx
  - New: mcp/che-word-mcp/Tests/CheWordMCPTests/ContentControlToolsTests.swift
- Downstream consumers: che-word-mcp v3.8.0 release; marketplace sync required after binary rebuild.
- GitHub issue: PsychQuant/che-word-mcp#44 (§1 of Office.js roadmap umbrella #43).
