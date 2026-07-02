---
name: che-word-mcp
description: Use when working with Microsoft Word (.docx) documents — reading content, creating new documents, modifying text/formatting/structure, working with tables/images/comments/track-changes/SDT/sections/styles/headers/hyperlinks. Swift-native OOXML server, 218+ tools, no Word install required.
---

# che-word-mcp

A Swift-native MCP server for Microsoft Word (.docx) document manipulation. **218+ tools** for reading, writing, and modifying Word documents without requiring Microsoft Word installation. Built on `ooxml-swift` v0.18.0.

Office.js OOXML Roadmap P0 = **100% complete** ([PsychQuant/che-word-mcp#43](https://github.com/PsychQuant/che-word-mcp/issues/43)). Latest: v3.12.0 ships programmatic Track Changes generation.

## Two Modes of Operation

| Mode | Parameter | Use when | Tool count |
|------|-----------|----------|------------|
| **Direct Mode** | `source_path` | Quick read-only access, no state needed | 18 tools |
| **Session Mode** | `doc_id` | Full read/write with open→edit→save lifecycle | All 218+ tools |

### Direct Mode (`source_path`)

Pass `source_path` with the .docx path. No `open_document` needed. Best for quick inspection.

```
list_images:  { "source_path": "/path/to/file.docx" }
search_text:  { "source_path": "/path/to/file.docx", "query": "keyword" }
```

### Session Mode (`doc_id`)

Call `open_document` first, then pass `doc_id`. Required for any edit.

```
open_document:    { "path": "/path/to/file.docx", "doc_id": "mydoc" }
insert_paragraph: { "doc_id": "mydoc", "text": "Hello" }
save_document:    { "doc_id": "mydoc", "path": "/path/to/output.docx" }
close_document:   { "doc_id": "mydoc" }
```

## Core Workflows

### Reading Documents

```text
1. open_document(path: "...")          → returns doc_id
2. get_document_text(doc_id: "...")    → plain text
   OR get_paragraphs(doc_id: "...")    → with formatting + indices
3. close_document(doc_id: "...")
```

### Creating Documents

```text
1. create_document(doc_id: "report")
2. insert_paragraph(doc_id, text: "Title", style: "Heading1")
   insert_table(doc_id, rows: 3, cols: 4, data: [...])
   insert_image(doc_id, path: "/image.png")
3. save_document(doc_id, path: "/out.docx")
```

### Modifying Documents

```text
1. open_document(path: "...")
2. update_paragraph(doc_id, paragraph_index: 0, text: "...")
   format_text(doc_id, paragraph_index: 0, bold: true)
   replace_text(doc_id, find: "...", replace: "...")
3. save_document(doc_id, path: "...")
```

### Track Changes Workflow (v3.12.0+)

Two paths: **accept/reject existing revisions** OR **generate new revisions programmatically**.

```text
# Accept/reject existing revisions
1. open_document(path: "...")
2. get_revisions(doc_id)                  → list with revision ids
3. accept_revision(doc_id, revision_id) / reject_revision(...)
   accept_all_revisions(doc_id) / reject_all_revisions(doc_id)

# Generate new revisions (NEW in v3.12.0)
1. enable_track_changes(doc_id, author: "Reviewer A")
2. insert_text_as_revision(doc_id, paragraph_index, position, text)
   delete_text_as_revision(doc_id, paragraph_index, start, end)
   move_text_as_revision(doc_id, source/dest)
   format_text(doc_id, paragraph_index, bold: true, as_revision: true)
   set_paragraph_format(doc_id, paragraph_index, alignment: "center", as_revision: true)
3. save_document(...)
```

**Author resolution chain**: explicit `author` arg → `revisions.settings.author` (set at `enable_track_changes`) → `"Unknown"`.

**Side-effect contract** (important): `as_revision: true` requires track changes to be enabled. If disabled, the call **throws `track_changes_not_enabled`** instead of silently auto-enabling. Call `enable_track_changes` first.

### Content Controls / SDT (v3.9.0+)

```text
insert_content_control(doc_id, paragraph_index, control_type: "richText"|"plainText"|"checkBox"|"dropDownList"|"comboBox"|"date"|"picture")
insert_repeating_section(doc_id, ...)
list_content_controls(doc_id)
get_content_control(doc_id, sdt_id)
update_content_control_text(doc_id, sdt_id, text)
replace_content_control_content(doc_id, sdt_id, content)
delete_content_control(doc_id, sdt_id)
```

SDT ids are auto-allocated via max+1 pattern (scans body + headers + footers + footnotes + endnotes).

### Exporting

```text
export_text(doc_id)                    → plain text
export_markdown(doc_id)                → Markdown
export_revision_summary_markdown(doc_id) → revision summary
export_comment_threads_markdown(doc_id)  → comment threads
export_all_images(doc_id, output_dir)
```

## Tool Categories (218+ total)

### Document Lifecycle

`create_document`, `open_document`, `save_document`, `close_document`, `list_open_documents`, `get_document_info`, `get_document_session_state`, `finalize_document`, `recover_from_autosave`, `revert_to_disk`, `reload_from_disk`, `check_disk_drift`, `checkpoint`

### Document Properties / Theme / Web Settings

`get_document_properties`, `set_document_properties`, `get_theme`, `set_theme`, `update_theme_color`, `update_theme_fonts`, `get_web_settings`, `update_web_settings`, `set_language`

### Content (text + paragraphs)

`get_text`, `get_document_text`, `get_paragraphs`, `get_paragraph_runs`, `get_text_with_formatting`, `insert_paragraph`, `update_paragraph`, `delete_paragraph`, `replace_text`, `replace_text_batch`, `search_text`, `search_text_batch`, `search_text_with_formatting`, `search_by_formatting`, `list_all_formatted_text`

### Formatting

`format_text` (with `as_revision` flag, v3.12.0+), `set_paragraph_format` (with `as_revision` flag), `set_character_spacing`, `set_text_effect`, `set_text_direction`, `set_paragraph_border`, `set_paragraph_shading`

### Styles (v3.10.0+)

`list_styles`, `apply_style`, `create_style`, `update_style`, `delete_style`

### Numbering / Lists (v3.10.0+)

`insert_bullet_list`, `insert_numbered_list`, `set_list_level`, `set_outline_level`

### Sections / Page Setup (v3.10.0+)

`get_section_properties`, `insert_section_break`, `insert_continuous_section_break`, `insert_column_break`, `insert_page_break`, `set_columns`, `set_page_size`, `set_page_margins`, `set_page_orientation`, `set_page_borders`, `set_page_break_before`, `set_keep_lines`, `set_keep_with_next`, `set_widow_orphan`, `set_line_numbers`, `get_word_count_by_section`

### Tables (v3.11.0+)

`insert_table`, `get_tables`, `update_cell`, `add_row_to_table`, `delete_row_from_table`, `add_column_to_table`, `delete_column_from_table`, `merge_cells`, `set_cell_width`, `set_cell_vertical_alignment`, `set_row_height`, `set_header_row`, `set_table_alignment`, `set_table_style`, `delete_table`

### Hyperlinks (v3.11.0+)

`insert_hyperlink`, `update_hyperlink`, `delete_hyperlink`, `list_hyperlinks`, `insert_internal_link`, `insert_cross_reference`

### Headers & Footers (v3.11.0+, even/odd + section map)

`add_header`, `update_header`, `get_header`, `delete_header`, `list_headers`, `add_footer`, `update_footer`, `get_footer`, `delete_footer`, `list_footers`, `insert_page_number`

### Comments

`insert_comment`, `update_comment`, `delete_comment`, `list_comments`, `list_comment_threads`, `get_comment_thread`, `reply_to_comment`, `resolve_comment`, `sync_extended_comments`, `add_person`, `update_person`, `delete_person`, `list_people`

### Track Changes / Revisions (v3.12.0 write side)

`enable_track_changes`, `disable_track_changes`, `get_revisions`, `accept_revision`, `reject_revision`, `accept_all_revisions`, `reject_all_revisions`, `insert_text_as_revision`, `delete_text_as_revision`, `move_text_as_revision`, `export_revision_summary_markdown`

### Content Controls / SDT (v3.9.0+)

`insert_content_control`, `list_content_controls`, `get_content_control`, `update_content_control_text`, `replace_content_control_content`, `delete_content_control`, `insert_repeating_section`, `update_repeating_section_item`, `list_repeating_section_items`, `insert_checkbox`, `insert_dropdown`, `insert_text_field`, `list_custom_xml_parts`

### Images

`insert_image`, `insert_image_from_path`, `insert_floating_image`, `update_image`, `delete_image`, `list_images`, `set_image_style`, `export_image`, `export_all_images`, `insert_drop_cap`

### Footnotes / Endnotes / Equations / Captions

`insert_footnote`, `update_footnote`, `delete_footnote`, `get_footnote`, `list_footnotes`, `insert_endnote`, `update_endnote`, `delete_endnote`, `get_endnote`, `list_endnotes`, `insert_equation`, `update_equation`, `delete_equation`, `get_equation`, `list_equations`, `insert_caption`, `update_caption`, `delete_caption`, `get_caption`, `list_captions`

### Bookmarks / Indexes / TOC / Watermarks

`insert_bookmark`, `delete_bookmark`, `list_bookmarks`, `insert_index`, `insert_index_entry`, `insert_toc`, `insert_table_of_figures`, `insert_watermark`, `insert_image_watermark`, `remove_watermark`, `get_watermark`, `list_watermarks`

### Fields

`insert_date_field`, `insert_page_field`, `insert_sequence_field`, `insert_calculation_field`, `insert_if_field`, `insert_merge_field`, `update_all_fields`

### Layout / Decoration

`insert_horizontal_line`, `insert_symbol`, `insert_tab_stop`, `clear_tab_stops`

### Document Protection

`protect_document`, `unprotect_document`, `set_document_password`, `remove_document_password`, `restrict_editing_region`

### Compare / Export

`compare_documents`, `compare_documents_markdown`, `export_text`, `export_markdown`

## Tips

1. **Track Changes is enforced by default.** `create_document` and `open_document` auto-enable track changes via `enforceTrackChangesIfNeeded`. Pass `track_changes: false` to `open_document` if you need to bypass enforcement (e.g., authoring tooling that controls revisions itself).
2. **Always save after modifications.** In-memory until `save_document`.
3. **Use `finalize_document` to save+close in one step** when done.
4. **Use styles for consistency** — `apply_style` over manual formatting.
5. **Check structure first** — `get_document_info` / `get_paragraphs` before editing.
6. **Export for AI processing** — `export_markdown` for easier text analysis.
7. **Direct Mode for read-only inspection** — pass `source_path`, skip the open/close lifecycle.

## Examples

### Contract Redline (Track Changes write side, v3.12.0)

```text
1. open_document("/contracts/draft.docx")
2. enable_track_changes(doc_id, author: "Reviewer A")
3. insert_text_as_revision(doc_id, paragraph_index: 5, position: 32,
                           text: " (subject to escalation)")
4. delete_text_as_revision(doc_id, paragraph_index: 7, start: 23, end: 31)
5. format_text(doc_id, paragraph_index: 9, bold: true, as_revision: true)
6. save_document(doc_id, path: "/contracts/draft-redlined.docx")

→ Word opens the file with proper <w:ins>/<w:del>/<w:rPrChange> markup,
  attributed to "Reviewer A", reviewable in the Review pane.
```

### Multi-author Review

```text
1. enable_track_changes(doc_id, author: "Author A")
2. insert_text_as_revision(...)             # → "Author A"

3. disable_track_changes(doc_id)
4. enable_track_changes(doc_id, author: "Author B")
5. insert_text_as_revision(..., author: "Author C")  # explicit override
6. insert_text_as_revision(...)              # falls back to "Author B"
```

### Fillable Form with Content Controls

```text
1. create_document(doc_id: "form")
2. insert_paragraph(doc_id, text: "Application Form", style: "Heading1")
3. insert_paragraph(doc_id, text: "Name: ")
4. insert_content_control(doc_id, paragraph_index: 1, control_type: "plainText",
                          tag: "applicant_name", placeholder: "Enter name...")
5. insert_paragraph(doc_id, text: "Date: ")
6. insert_content_control(doc_id, paragraph_index: 2, control_type: "date",
                          tag: "submission_date")
7. save_document(doc_id, path: "/forms/application.docx")
```

### Extract & Analyze

```text
1. open_document("/thesis.docx")
2. get_paragraphs(doc_id) + list_comments(doc_id) + get_revisions(doc_id)
3. export_markdown(doc_id) → analyze
4. close_document(doc_id)
```
