## Why

Real-world `.docx` files pasted into a template (LaTeX-converted Word, Google Docs, external Word docs) commonly carry caption text as **plain runs** (e.g., "圖 4-1：<title>") rather than properly-structured `SEQ`-field captions. This breaks downstream MCP tooling:

- `update_all_fields` correctly reports `"no SEQ fields found"` because there are none
- `insert_table_of_figures` / `insert_table_of_tables` produce empty TOFs (no `SEQ Figure` / `SEQ Table` fields exist to index)

Today the only paths are (1) tell the user to manually click each caption in Word and use **Insert > Field > SEQ** for every caption, or (2) hand-edit `word/document.xml` to inject `<w:fldSimple>` elements. Both are unfriendly for AI-driven thesis rescue / template population workflows where the caption text was pasted in from another source without structured fields.

A new bulk-conversion tool `wrap_caption_seq` closes the upstream gap that prevents `update_all_fields` and `insert_table_of_figures` / `insert_table_of_tables` from being useful in pasted-template workflows.

## What Changes

A new MCP tool `wrap_caption_seq` (cross-repo: lib-layer method in ooxml-swift + MCP wrapper in che-word-mcp).

For every paragraph whose text matches a user-supplied regex with one numeric capture group, the captured numeric portion is replaced in-place by a `<w:fldSimple w:instr=" SEQ {sequence_name} \* {format} ">{captured}</w:fldSimple>`-bearing run (cachedResult set to the captured number so Word does not re-shuffle on first open before F9 recalculation).

API surface:

```
wrap_caption_seq(
  doc_id: String,
  pattern: String,                   // regex with ONE numeric capture group
  sequence_name: String,             // "Figure" | "Table" | custom SEQ identifier
  format: String? = "ARABIC",        // "ARABIC" | "ROMAN" | "ALPHABETIC"
  scope: String? = "body",           // "body" | "all"
  insert_bookmark: Bool? = false,
  bookmark_template: String? = nil   // e.g. "fig${number}" — only used when insert_bookmark = true
) -> {
  matched_paragraphs: Int,
  fields_inserted: Int,
  paragraphs_modified: [Int],        // body.children indices, document order
  skipped: [{ paragraph_index: Int, reason: String }]
}
```

Behavior:

- **Match interface**: regex string with exactly ONE numeric capture group. Validation rejects patterns missing the group or with multiple groups (ambiguous which one is the number)
- **Bookmark wrapping**: default OFF; `insert_bookmark: true` wraps the rewritten paragraph in `<w:bookmarkStart>/<w:bookmarkEnd>` with bookmark name from `bookmark_template` (substituting `${number}` with the captured numeric)
- **Scope**: `"body"` (default) walks `body.children` only; `"all"` mirrors `WordDocument.updateAllFields(isolatePerContainer:)` traversal — body + headers + footers + footnotes + endnotes
- **Format**: emitted as `\* ARABIC` / `\* ROMAN` / `\* ALPHABETIC` in the `w:instr` value. User-typed numerals are REPLACED by the SEQ-field cachedResult, not preserved (silent preserve diverges on next F9)
- **Idempotency / skip rule**: paragraphs whose runs or `fieldSimples` already contain a `SEQ {sequence_name}` field are reported in `skipped` with reason `"already wraps SEQ {sequence_name}"`; never double-wrapped
- **Return shape**: structured result enables LLM caller to verify "did all 23 captions get fields?" rather than parsing free-form text

## Non-Goals

The following are explicitly out of scope; users compose other tools or open separate enhancements:

- **STYLEREF chapter-number prefix** (e.g., `圖 2-1` vs plain `圖 1`). `insert_caption` already supports `include_chapter_number: true`; users wrap pre-existing plain-text captions with this tool, then use `insert_caption` for new captions that need chapter numbering
- **Caption description text rewriting**. This tool only wraps the NUMBER portion; description text after the number stays as plain runs. Migrating the description text would require structured-text policy decisions outside the SEQ-field gap
- **TOF/TOT bookmark cross-ref population**. `insert_bookmark` here only adds the bookmark; populating cross-references requires separate `insert_cross_reference` invocations
- **Auto-detection of caption labels** (e.g., "look for any text starting with 圖/Figure/表/Table"). Users supply the regex; auto-detection would require label-vocabulary curation that fights with i18n

## Capabilities

### New Capabilities

(none — extends existing capabilities)

### Modified Capabilities

- `che-word-mcp-field-equation-crud`: add MCP tool `wrap_caption_seq` — bulk-wraps plain-text caption number portions in SEQ fields
- `ooxml-content-insertion-primitives`: add lib method `Document.wrapCaptionSequenceFields(...)` — emits SEQ-field runs into matching paragraphs across configurable scope

## Impact

- Affected specs:
  - `openspec/specs/che-word-mcp-field-equation-crud/spec.md` (ADDED requirement: `wrap_caption_seq` MCP tool)
  - `openspec/specs/ooxml-content-insertion-primitives/spec.md` (ADDED requirement: `Document.wrapCaptionSequenceFields` lib method)

- Affected code:
  - Modified:
    - `mcp/che-word-mcp/Sources/CheWordMCP/Server.swift` (+~80 lines: tool schema entry, dispatcher case, handler that maps args → lib call → JSON return)
    - `mcp/che-word-mcp/CHANGELOG.md` (v3.17.0 entry)
    - `mcp/che-word-mcp/mcpb/manifest.json` (version + description bump)
    - `mcp/che-word-mcp/Package.swift` (ooxml-swift dep bump 0.20.5 → 0.21.0)
    - `packages/ooxml-swift/CHANGELOG.md` (v0.21.0 entry)
  - New:
    - `packages/ooxml-swift/Sources/OOXMLSwift/Models/WordDocument+WrapCaptionSequenceFields.swift` (lib method + WrapCaptionResult struct + TextScope enum if not already in shared module)
    - `packages/ooxml-swift/Tests/OOXMLSwiftTests/WrapCaptionSequenceFieldsTests.swift` (~10 sub-tests)
    - `mcp/che-word-mcp/Tests/CheWordMCPTests/Issue62WrapCaptionSeqTests.swift` (~5 integration sub-tests via MCP dispatcher)
  - Removed: (none)
