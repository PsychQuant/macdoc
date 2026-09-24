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

---
### Requirement: Centimeter-denominated geometry tools

The MCP server SHALL expose three geometry tools whose length parameters are denominated exclusively in centimeters (Double) at the tool boundary, converting to EMU internally: `set_placeholder_geometry`, `place_picture_at`, and `fit_picture_to_native_aspect`. Shape addressing SHALL follow the existing `slide_index` + `shape_id` convention. Each tool's response SHALL include the resulting geometry in both cm (2-decimal precision) and EMU so callers can verify placement without a follow-up read.

#### Scenario: set_placeholder_geometry mutates any shape's geometry

- **GIVEN** an open presentation and a top-level shape with a known shape_id
- **WHEN** the caller invokes set_placeholder_geometry with x_cm 2.0, y_cm 3.0, width_cm 10.0, height_cm 7.5
- **THEN** the shape's stored offset MUST be (720000, 1080000) EMU and extent (3600000, 2700000) EMU
- **AND** the response MUST report both the cm and EMU values

#### Scenario: Off-slide placement warns but succeeds

- **GIVEN** a default slide (25.4 cm wide)
- **WHEN** the caller sets a shape's geometry with x_cm 30.0 (beyond the right edge)
- **THEN** the tool MUST apply the geometry
- **AND** the response MUST contain a warning naming the exceeded bound

#### Scenario: Non-positive dimensions are a hard error

- **WHEN** the caller invokes any geometry tool with width_cm 0 or a negative height_cm
- **THEN** the tool MUST return an error without mutating the document

#### Scenario: place_picture_at inserts and positions in one call

- **GIVEN** an open presentation and a 1600 x 1200 pixel PNG
- **WHEN** the caller invokes place_picture_at with x_cm 2.0, y_cm 3.0, width_cm 10.0 and no height_cm
- **THEN** the picture MUST be inserted with offset (720000, 1080000) EMU and extent (3600000, 2700000) EMU (height derived from the 4:3 native aspect)
- **AND** the response MUST include the new shape_id

#### Scenario: fit_picture_to_native_aspect re-derives the non-anchored dimension

- **GIVEN** a picture shape whose current extent is 3600000 x 1800000 EMU (distorted) and whose embedded image is 4:3
- **WHEN** the caller invokes fit_picture_to_native_aspect with anchor "width"
- **THEN** the extent MUST become 3600000 x 2700000 EMU (height re-derived)

#### Scenario: fit on a non-picture shape is an error

- **GIVEN** a shape_id that addresses a text shape
- **WHEN** the caller invokes fit_picture_to_native_aspect
- **THEN** the tool MUST return an error stating the shape is not a picture
