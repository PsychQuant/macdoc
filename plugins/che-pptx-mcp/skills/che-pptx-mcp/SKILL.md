---
name: che-pptx-mcp
description: Use when reading, creating, or editing PowerPoint .pptx presentations with the che-pptx-mcp plugin, especially for slides, shapes, tables, notes, images, themes, or Markdown export.
---

# che-pptx-mcp

Use the Swift-native PresentationML server for `.pptx` work without launching PowerPoint.

## Choose a mode

| Need | Mode | Address |
|---|---|---|
| Inspect one file | Direct, read-only | `source_path` |
| Create or edit | Session | `doc_id` after `create_presentation` or `open_presentation` |

All `slide_index`, row, and column indices are zero-based. Shape edits use the `shape_id` returned by `get_slide_shapes`. Geometry parameters are raw EMU integers; centimetre helpers are not shipped yet.

## Edit an existing presentation

```text
1. open_presentation(path: "/in/deck.pptx", doc_id: "deck")
2. get_slide_shapes(doc_id: "deck", slide_index: 1)
3. update_shape_text(doc_id: "deck", slide_index: 1,
                     shape_id: <title shape id>, text: "New title")
4. save_presentation(doc_id: "deck", path: "/out/deck-edited.pptx")
5. close_presentation(doc_id: "deck")
```

Edits stay in memory until `save_presentation` unless the session was opened with `autosave: true`. Use a different output path to preserve the source.

## Common tools

| Task | Tools |
|---|---|
| Inspect | `get_presentation_info`, `get_slide_count`, `get_text`, `get_slide_text`, `get_slide_shapes`, `get_shape_text`, `search_text` |
| Slides | `add_slide`, `delete_slide`, `duplicate_slide`, `reorder_slides` |
| Shapes | `insert_text_shape`, `update_shape_text`, `delete_shape`, `set_shape_position`, `set_shape_size`, `set_shape_fill` |
| Tables | `get_tables`, `get_table_data`, `insert_table`, `update_cell` |
| Images | `list_images`, `export_image`, `insert_image`, `delete_image` |
| Notes/theme | `get_slide_notes`, `add_notes`, `set_transition`, `get_theme`, `get_slide_master`, `get_slide_layouts` |
| Export | `export_markdown` |

Read tools accept either `source_path` or `doc_id` when their schema offers both. Mutation tools require an open session and `doc_id`.

## Honest boundaries

- No PDF export, slide rendering, PNG preview, or PowerPoint/Keynote automation tool is currently exposed. Do not promise a visual preview; use another renderer after saving when one is available.
- `export_image` returns an embedded image as base64; it does not render a slide.
- `insert_image`, text-shape placement, position, and size use EMU.
- Rich text runs, layout-based slide creation, and the #90 centimetre geometry tools are not part of the current published surface.

## Common mistakes

- Editing with `source_path`: open a session first.
- Treating the second slide as index 2: use `slide_index: 1`.
- Guessing a shape ID: call `get_slide_shapes` and use its returned ID.
- Closing before saving: save the intended output path, then close.
