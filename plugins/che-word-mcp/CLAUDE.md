# che-word-mcp — CLAUDE.md

## Purpose

Microsoft Word (.docx) MCP plugin. Wraps the [CheWordMCP](https://github.com/PsychQuant/che-word-mcp) Swift binary via auto-download wrapper. **Swift-native OOXML manipulation** — reads and writes .docx without requiring Microsoft Word installation. 218+ tools cover the full Office.js OOXML Roadmap P0 set ([#43](https://github.com/PsychQuant/che-word-mcp/issues/43) closed 100%).

Built on [`ooxml-swift`](https://github.com/PsychQuant/ooxml-swift) v0.18.0.

## Components

### MCP Tools (218+)

| Category | Representative tools |
|----------|---------------------|
| Document lifecycle | `create_document`, `open_document`, `save_document`, `close_document`, `finalize_document`, `recover_from_autosave`, `checkpoint`, `revert_to_disk` |
| Properties / theme | `get_document_properties`, `set_theme`, `update_theme_color`, `update_theme_fonts`, `set_language` |
| Content (text + paragraphs) | `get_text`, `get_paragraphs`, `insert_paragraph`, `update_paragraph`, `replace_text`, `replace_text_batch`, `search_text_with_formatting`, `list_all_formatted_text` |
| Formatting | `format_text` (with `as_revision`), `set_paragraph_format` (with `as_revision`), `set_character_spacing`, `set_text_effect`, `set_paragraph_border`, `set_paragraph_shading` |
| Styles (v3.10) | `list_styles`, `apply_style`, `create_style`, `update_style`, `delete_style` |
| Numbering / lists (v3.10) | `insert_bullet_list`, `insert_numbered_list`, `set_list_level`, `set_outline_level` |
| Sections / page setup (v3.10) | `get_section_properties`, `insert_section_break`, `set_page_size`, `set_page_margins`, `set_page_orientation`, `set_columns`, `set_line_numbers` |
| Tables (v3.11) | `insert_table`, `update_cell`, `add_row_to_table`, `merge_cells`, `set_cell_vertical_alignment`, `set_table_style`, `set_header_row`, `set_table_alignment` |
| Hyperlinks (v3.11) | `insert_hyperlink`, `update_hyperlink`, `list_hyperlinks`, `insert_internal_link`, `insert_cross_reference` |
| Headers / footers (v3.11) | `add_header`, `update_header`, `list_headers`, `add_footer`, `insert_page_number` (even/odd + section header map) |
| Comments | `insert_comment`, `update_comment`, `reply_to_comment`, `resolve_comment`, `list_comment_threads`, `sync_extended_comments`, `add_person`, `list_people` |
| Track Changes — accept/reject | `enable_track_changes`, `disable_track_changes`, `get_revisions`, `accept_revision`, `reject_revision`, `accept_all_revisions`, `reject_all_revisions` |
| Track Changes — write side (v3.12) | `insert_text_as_revision`, `delete_text_as_revision`, `move_text_as_revision`, `format_text` / `set_paragraph_format` with `as_revision: true` |
| Content controls / SDT (v3.9) | `insert_content_control`, `list_content_controls`, `update_content_control_text`, `replace_content_control_content`, `insert_repeating_section`, `insert_checkbox`, `insert_dropdown` |
| Images | `insert_image`, `insert_floating_image`, `update_image`, `set_image_style`, `export_image`, `export_all_images`, `insert_drop_cap` |
| Footnotes / endnotes / equations / captions | `insert_footnote`, `insert_endnote`, `insert_equation`, `insert_caption`, `list_captions` |
| Bookmarks / TOC / watermarks | `insert_bookmark`, `insert_toc`, `insert_table_of_figures`, `insert_index`, `insert_watermark`, `insert_image_watermark` |
| Fields | `insert_date_field`, `insert_page_field`, `insert_sequence_field`, `insert_calculation_field`, `insert_if_field`, `insert_merge_field`, `update_all_fields` |
| Document protection | `protect_document`, `set_document_password`, `restrict_editing_region` |
| Compare / export | `compare_documents`, `compare_documents_markdown`, `export_text`, `export_markdown`, `export_revision_summary_markdown`, `export_comment_threads_markdown` |

MCP namespace: `mcp__che-word-mcp__<tool>`.

### Skills

| Skill | 用途 |
|-------|------|
| `che-word-mcp` | 工作流指南：Direct vs Session 模式、tool 分類、Track Changes 寫側合約（`as_revision` + `track_changes_not_enabled` 例外）、SDT 控件、author resolution chain、常見 workflow（contract redline、multi-author review、fillable form） |

## Two Operating Modes

| Mode | Param | Tools | Use when |
|------|-------|-------|----------|
| Direct | `source_path` | 18 | 快速 read-only 檢查（list/search/info），不需 open/close lifecycle |
| Session | `doc_id` | All 218+ | 任何寫入或多步驟編輯都要走這個 |

## Track Changes Contract（v3.12.0+ 重要）

`as_revision: true` 是 **per-call opt-in**，不會自動開啟 track changes：

| 狀態 | `as_revision: true` 行為 |
|------|--------------------------|
| Track changes enabled | 包成 `<w:ins>` / `<w:del>` / `<w:rPrChange>` / `<w:pPrChange>` 標記 |
| Track changes disabled | **拋出 `track_changes_not_enabled`**，不靜默 enable |

設計理由：避免副作用 — 呼叫 `format_text(as_revision: true)` 不會偷偷修改文件全域的 track changes 狀態。要先 `enable_track_changes(author: "...")` 再呼叫。

**Author resolution chain**：explicit `author` arg → `revisions.settings.author`（在 `enable_track_changes` 時設定）→ `"Unknown"`。

## Binary Dependency

這是 binary-based plugin：`.mcp.json` 指向 `bin/che-word-mcp-wrapper.sh`，wrapper 會 auto-download `CheWordMCP` binary 到 `~/bin/`。

- Binary repo: [`PsychQuant/che-word-mcp`](https://github.com/PsychQuant/che-word-mcp)
- Binary name: `CheWordMCP`
- Underlying lib: [`PsychQuant/ooxml-swift`](https://github.com/PsychQuant/ooxml-swift) v0.18.0
- Release asset naming: asset filename must contain `CheWordMCP`

### Plugin vs Binary Version Sync

| 改動類型 | 處理 |
|----------|------|
| 改 plugin shell（skill、CLAUDE.md、wrapper、`.mcp.json`） | `/plugin-tools:plugin-update che-word-mcp` |
| 改 binary source（新 tool、bug fix、ooxml-swift 升級） | 先 `/mcp-tools:mcp-deploy`（在 `mcp/che-word-mcp/`）→ 發 GitHub Release → 再跑 `plugin-update` |
| 同時改兩邊 | `plugin-update`（v1.11+ 會 detect 依賴不同步並 prompt 連動 mcp-deploy） |

Plugin shell 與 binary 版本獨立。Plugin shell 升 minor 反映文件/skill/CLAUDE.md 變動；binary 版升反映 MCP server 內部新增 tool 或修 bug。

## Permissions

無 macOS TCC 權限需求。plugin 跑在使用者層級，讀寫 `.docx` 檔案使用標準檔案系統權限（會繼承呼叫者的 sandbox / FDA 設定）。

## Development

- Update after plugin-shell changes: `/plugin-tools:plugin-update che-word-mcp`
- Full release (binary + plugin): `/plugin-tools:plugin-deploy che-word-mcp`
- Binary source edits: go to `mcp/che-word-mcp/` (or sibling clone of `PsychQuant/che-word-mcp`) then `/mcp-tools:mcp-deploy`
- Health check: `/plugin-tools:plugin-health`

## Office.js OOXML Roadmap P0 Closure Map

| § | Sub-issue | che-word-mcp version |
|---|-----------|----------------------|
| §1 Content Controls (SDT) | [#44](https://github.com/PsychQuant/che-word-mcp/issues/44) | v3.9.0 |
| §2 Track Changes 寫側 | [#45](https://github.com/PsychQuant/che-word-mcp/issues/45) | v3.12.0 |
| §3 Numbering | [#46](https://github.com/PsychQuant/che-word-mcp/issues/46) | v3.10.0 |
| §4 Sections | [#47](https://github.com/PsychQuant/che-word-mcp/issues/47) | v3.10.0 |
| §8 Styles | [#48](https://github.com/PsychQuant/che-word-mcp/issues/48) | v3.10.0 |
| §9 Tables | [#49](https://github.com/PsychQuant/che-word-mcp/issues/49) | v3.11.0 |
| §14 Hyperlinks | [#50](https://github.com/PsychQuant/che-word-mcp/issues/50) | v3.11.0 |
| §16 Headers / Footers | [#51](https://github.com/PsychQuant/che-word-mcp/issues/51) | v3.11.0 |

Umbrella: [#43](https://github.com/PsychQuant/che-word-mcp/issues/43) — closed 2026-04-25.
