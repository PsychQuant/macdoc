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

All `slide_index`, row, and column indices are zero-based. Use `get_slide_shapes` to discover IDs. `update_shape_text`, `set_shape_position`, `set_shape_size`, and `set_shape_fill` accept only entries reported as `Shape`, not picture/table/group IDs; use image or table tools for those elements. Geometry parameters are raw EMU integers; centimetre helpers are not shipped yet.

## Read without opening a session

```text
get_presentation_info(source_path: "/in/deck.pptx")
get_slide_count(source_path: "/in/deck.pptx")
get_slide_text(source_path: "/in/deck.pptx", slide_index: 0)
```

Direct mode is read-only. Use `create_presentation` to start a new session, or `open_presentation` before modifying an existing file.

## Create a presentation

```text
1. create_presentation(doc_id: "deck")
2. insert_text_shape(doc_id: "deck", slide_index: 0, text: "Title",
                     x: 720000, y: 720000, width: 7200000, height: 900000)
3. save_presentation(doc_id: "deck", path: "/out/new-deck.pptx")
4. close_presentation(doc_id: "deck")
```

`create_presentation` starts with one blank slide at index 0; call `add_slide` only when another slide is needed.

## Edit an existing presentation

```text
1. open_presentation(path: "/in/deck.pptx", doc_id: "deck")
2. get_slide_shapes(doc_id: "deck", slide_index: 1)
3. update_shape_text(doc_id: "deck", slide_index: 1,
                     shape_id: <title shape id>, text: "New title")
4. save_presentation(doc_id: "deck", path: "/out/deck-edited.pptx")
5. close_presentation(doc_id: "deck")
```

Edits stay in memory until `save_presentation` unless the session was opened with `autosave: true`. Use `autosave: false` and a different output path to preserve the source; autosave writes edits back to the opened path.

## Common tools

| Task | Tools |
|---|---|
| Sessions | `create_presentation`, `open_presentation`, `save_presentation`, `close_presentation`, `list_open_presentations` |
| Inspect | `get_presentation_info`, `get_slide_count`, `get_text`, `get_slide_text`, `get_slide_shapes`, `get_shape_text`, `search_text` |
| Slides | `add_slide`, `delete_slide`, `duplicate_slide`, `reorder_slides` |
| Shapes | `insert_text_shape`, `update_shape_text`, `delete_shape`, `set_shape_position`, `set_shape_size`, `set_shape_fill` |
| Tables | `get_tables`, `get_table_data`, `insert_table`, `update_cell` |
| Images | `list_images`, `export_image`, `insert_image`, `delete_image` |
| Notes/theme | `get_slide_notes`, `add_notes`, `set_transition`, `get_theme`, `get_slide_master`, `get_slide_layouts` |
| Export | `export_markdown` |

Read tools accept either `source_path` or `doc_id` when their schema offers both. After `create_presentation` or `open_presentation` establishes a session, content mutation tools require its `doc_id`.

## Honest boundaries

- No PDF export, slide rendering, PNG preview, or PowerPoint/Keynote automation tool is currently exposed. Do not promise a visual preview; use another renderer after saving when one is available.
- `export_image` returns an embedded image as base64; it does not render a slide.
- `insert_image`, text-shape placement, position, and size use EMU.
- Rich text runs, layout-based slide creation, and the #90 centimetre geometry tools are not part of the current published surface.

## Common mistakes

- Editing with `source_path`: open a session first.
- Treating the second slide as index 2: use `slide_index: 1`.
- Guessing a shape ID or its element kind: call `get_slide_shapes`; use Shape-only editors only on entries marked `Shape`.
- Closing before saving: save the intended output path, then close.
