# che-word-mcp — CLAUDE.md

## Purpose

Microsoft Word (.docx) MCP plugin. Wraps the [CheWordMCP](https://github.com/PsychQuant/che-word-mcp) Swift binary via auto-download wrapper. **Swift-native OOXML manipulation** — reads and writes .docx without requiring Microsoft Word installation. 245 tools（binary v4.0.0 `tools/list` 實測）cover the full Office.js OOXML Roadmap P0 set ([#43](https://github.com/PsychQuant/che-word-mcp/issues/43) closed 100%).

Built on [`ooxml-swift`](https://github.com/PsychQuant/ooxml-swift). **版本以 binary repo 的 `Package.swift` 為準** —— 這裡不寫死版號，因為它在每次上游發布後就過期，本檔已為此改過三次。

## Components

### MCP Tools (245)

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
| Session | `doc_id` | All 245 | 任何寫入或多步驟編輯都要走這個 |

## Track Changes Contract（v3.12.0+ 重要）

`as_revision: true` 是 **per-call opt-in**，不會自動開啟 track changes：

| 狀態 | `as_revision: true` 行為 |
|------|--------------------------|
| Track changes enabled | 包成 `<w:ins>` / `<w:del>` / `<w:rPrChange>` / `<w:pPrChange>` 標記 |
| Track changes disabled | **拋出 `track_changes_not_enabled`**，不靜默 enable |

設計理由：避免副作用 — 呼叫 `format_text(as_revision: true)` 不會偷偷修改文件全域的 track changes 狀態。要先 `enable_track_changes(author: "...")` 再呼叫。

**Author resolution chain**：explicit `author` arg → `revisions.settings.author`（在 `enable_track_changes` 時設定）→ `"Unknown"`。

## Binary Dependency

這是 binary-based plugin：`.mcp.json` 指向 `bin/che-word-mcp-wrapper.sh`，wrapper 會 auto-download `CheWordMCP` binary 到 plugin 層級的 `.bin-cache/`（#117）。

- Binary repo: [`PsychQuant/che-word-mcp`](https://github.com/PsychQuant/che-word-mcp)
- Binary name: `CheWordMCP`
- Underlying lib: [`PsychQuant/ooxml-swift`](https://github.com/PsychQuant/ooxml-swift)（版本見 binary repo 的 `Package.swift`）
- Release asset naming: asset filename must contain `CheWordMCP`

### Plugin vs Binary Version Sync

| 改動類型 | 處理 |
|----------|------|
| 改 plugin shell（skill、CLAUDE.md、wrapper、`.mcp.json`） | `/plugin-tools:plugin-update che-word-mcp` |
| 改 binary source（新 tool、bug fix、ooxml-swift 升級） | 先 `/mcp-tools:mcp-deploy`（在 `mcp/che-word-mcp/`）→ 發 GitHub Release → 再跑 `plugin-update` |
| 同時改兩邊 | `plugin-update`（v1.11+ 會 detect 依賴不同步並 prompt 連動 mcp-deploy） |

Plugin shell 與 binary 版本獨立。Plugin shell 升 minor 反映文件/skill/CLAUDE.md 變動；binary 版升反映 MCP server 內部新增 tool 或修 bug。

## Save-time image-consistency gate（binary 4.0.6+，4.0.10 定型；PsychQuant/macdoc#175）

`save_document` / `finalize_document` / 帶顯式 `path` 的 `checkpoint` 在寫檔前先序列化並用 ooxml-swift `PackageInspector` 檢查：若會寫出**本 session 新產生**的孤兒 image relationship（rels/media 存在但該 part 內無引用——#175「插圖回報成功但存檔後圖不在」的簽名），回 `E_IMAGE_CONSISTENCY` 拒絕寫檔（正本不動、session 存活）；檢查本身失敗回 `E_IMAGE_CONSISTENCY_INSPECTION`。

| 要點 | 行為 |
|------|------|
| baseline | 開檔時的封包快照（revert / reload / 通過 gate 的存檔後更新）；開檔時就存在的孤兒不擋 |
| 逃生口 | `allow_orphan_images: true`（刻意刪除含圖段落、想保留殘留 relationship 時）；必須是 boolean |
| 側門 | `autosave: true` 與 shutdown flush 同樣過 gate，拒絕時狀態寫到 `<source>.unsaved*.docx`（不覆蓋既有檔、成功存檔後自動清理）；只有**不帶 path** 的 `checkpoint`（recovery sidecar）不 gate |
| 拒絕後該做什麼 | 先比對 `list_images` 與 `get_paragraphs`：圖真的不在正文才重插；是刻意刪圖就帶 `allow_orphan_images: true` 重存。**不要**用 checkpoint / 換路徑繞過——同一道 gate |

根因（ooxml-swift 3.6.x）：append 模式的段落若含 op payload 無法表示的內容（圖片、marker、raw children），改為 graft 進 live tree，不再整份 `document.xml` 走 typed 重序列化；anchored 插圖與其他 typed-dirty 操作仍走 typed 路徑（PsychQuant/ooxml-swift#133）。

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
