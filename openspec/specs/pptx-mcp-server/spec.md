# pptx-mcp-server Specification

## Purpose

MCP server exposing pptx-swift capabilities as 37 tools — session mode (open/edit/save lifecycle) and direct mode (read-only via source_path) for PowerPoint file manipulation.

## Requirements

### Requirement: Session mode lifecycle

The MCP server SHALL support session mode with `open_presentation` → edit → `save_presentation` → `close_presentation` lifecycle, using a `doc_id` identifier for all operations.

#### Scenario: Open, edit, save workflow

- **WHEN** the caller opens a .pptx with `doc_id: "deck"`, modifies slide text, then saves
- **THEN** all operations use the same `doc_id` and the saved file reflects all changes

#### Scenario: Close without save

- **WHEN** the caller attempts to close a presentation with unsaved changes
- **THEN** the server blocks the close and returns an error indicating unsaved changes


<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - mcp/che-pptx-mcp/Sources/ChePPTXMCP/Server.swift
-->

---
### Requirement: Direct mode read access

The MCP server SHALL support direct mode using `source_path` for read-only operations, without requiring an open session.

#### Scenario: Direct text extraction

- **WHEN** the caller calls `get_slide_text` with `source_path: "/path/to/deck.pptx"` and `slide_index: 0`
- **THEN** the server reads the file, extracts text from slide 1, and returns it without creating a session


<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - mcp/che-pptx-mcp/Sources/ChePPTXMCP/Server.swift
-->

---
### Requirement: Presentation info tools

The MCP server SHALL provide tools to get presentation metadata: `get_presentation_info` (slide count, dimensions, properties), `get_slide_count`, `get_text` (all text).

#### Scenario: Presentation info

- **WHEN** the caller calls `get_presentation_info` on a 10-slide deck
- **THEN** the server returns slide count (10), slide dimensions, and document properties


<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - mcp/che-pptx-mcp/Sources/ChePPTXMCP/Server.swift
-->

---
### Requirement: Slide content tools

The MCP server SHALL provide tools to read slide content: `get_slide_text`, `get_slide_shapes`, `get_shape_text`, `get_slide_notes`.

#### Scenario: Get shapes on a slide

- **WHEN** the caller calls `get_slide_shapes` for slide index 2
- **THEN** the server returns a list of shapes with their IDs, names, types, positions, and sizes


<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - mcp/che-pptx-mcp/Sources/ChePPTXMCP/Server.swift
-->

---
### Requirement: Image tools

The MCP server SHALL provide tools for image operations: `list_images`, `export_image`, `insert_image`, `delete_image`.

#### Scenario: Export image

- **WHEN** the caller calls `export_image` with a shape ID
- **THEN** the server returns the image data as base64 with format metadata


<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - mcp/che-pptx-mcp/Sources/ChePPTXMCP/Server.swift
-->

---
### Requirement: Table tools

The MCP server SHALL provide tools for table operations: `get_tables`, `get_table_data`, `insert_table`, `update_cell`.

#### Scenario: Get table data

- **WHEN** the caller calls `get_table_data` for a table on slide 3
- **THEN** the server returns a 2D array of cell text values with column/row counts


<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - mcp/che-pptx-mcp/Sources/ChePPTXMCP/Server.swift
-->

---
### Requirement: Slide management tools

The MCP server SHALL provide tools to manage slides: `add_slide`, `delete_slide`, `reorder_slides`, `duplicate_slide`.

#### Scenario: Duplicate slide

- **WHEN** the caller calls `duplicate_slide` for slide index 2
- **THEN** a copy of slide 2 is inserted at index 3 with all shapes and content preserved


<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - mcp/che-pptx-mcp/Sources/ChePPTXMCP/Server.swift
-->

---
### Requirement: Shape editing tools

The MCP server SHALL provide tools to edit shapes: `insert_text_shape`, `update_shape_text`, `delete_shape`, `set_shape_position`, `set_shape_size`, `set_shape_fill`.

#### Scenario: Update shape text

- **WHEN** the caller calls `update_shape_text` with shape ID and new text
- **THEN** the shape's text content is replaced with the new text


<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - mcp/che-pptx-mcp/Sources/ChePPTXMCP/Server.swift
-->

---
### Requirement: Search tool

The MCP server SHALL provide a `search_text` tool to find text across all slides, returning matching slide indices and shape IDs.

#### Scenario: Text search

- **WHEN** the caller searches for "revenue" in a 20-slide deck
- **THEN** the server returns all occurrences with slide index, shape ID, and surrounding context


<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - mcp/che-pptx-mcp/Sources/ChePPTXMCP/Server.swift
-->

---
### Requirement: Export tool

The MCP server SHALL provide an `export_markdown` tool that converts presentation content to structured Markdown with slide separators.

#### Scenario: Markdown export

- **WHEN** the caller calls `export_markdown`
- **THEN** the server returns Markdown with `---` slide separators, headings from title placeholders, and body text from content placeholders


<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - mcp/che-pptx-mcp/Sources/ChePPTXMCP/Server.swift
-->

---
### Requirement: Theme and master tools

The MCP server SHALL provide read-only tools for theme inspection: `get_theme`, `get_slide_master`, `get_slide_layouts`.

#### Scenario: Get theme colors

- **WHEN** the caller calls `get_theme`
- **THEN** the server returns the color scheme (12 named colors with hex values) and font scheme

<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - mcp/che-pptx-mcp/Sources/ChePPTXMCP/Server.swift
-->