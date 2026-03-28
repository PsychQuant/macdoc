## 1. Package Setup (Two-package architecture)

- [x] 1.1 Create `packages/pptx-swift/` with Package.swift — reuse ooxml-swift via dependency, not fork (for ZipHelper, Relationship, ImageReference, DocumentProperties) + ZIPFoundation
- [x] 1.2 Create `mcp/che-pptx-mcp/` with Package.swift, depend on pptx-swift
- [x] 1.3 Set up directory structure: `Sources/PPTXSwift/IO/`, `Sources/PPTXSwift/Models/`, `Sources/PPTXSwift/Errors/`
- [x] 1.4 Verify both packages build with `swift build`

## 2. PPTX Parsing — Core IO (ZIP extraction and content discovery)

- [x] 2.1 Implement `PptxReader.read(from:)` using ZipHelper for ZIP extraction and content discovery
- [x] 2.2 Implement relationship parsing for package, presentation, and per-slide `.rels` files (reuse ooxml-swift Relationship model)
- [x] 2.3 Implement document properties parsing (reuse ooxml-swift DocumentProperties from `docProps/core.xml`)
- [x] 2.4 Implement presentation model construction from `ppt/presentation.xml` (slide list, slide size, master/layout/theme references)

## 3. PPTX Parsing — Theme, Master, Layout

- [x] 3.1 Implement theme parsing — color scheme extraction (12 named colors, EMU coordinate system), font scheme, format scheme
- [x] 3.2 Implement slide master and layout parsing — placeholder definitions, default formatting
- [x] 3.3 Implement theme color resolution via lookup table (scheme color → hex)
- [x] 3.4 Implement media extraction from `ppt/media/` with relationship linking

## 4. Shape-centric Model — Read (slide content)

- [x] 4.1 Define Shape-centric model types: `Presentation`, `Slide`, `SlideElement` enum (Shape, Picture, GraphicFrame, GroupShape), `TextBody`, `TextParagraph`, `TextRun`
- [x] 4.2 Implement shape tree traversal (`p:spTree` → typed SlideElement values)
- [x] 4.3 Implement text extraction from shapes (`p:txBody > a:p > a:r > a:t`) with run-level formatting
- [x] 4.4 Implement placeholder identification (`p:ph type="..."`)
- [x] 4.5 Implement shape geometry and positioning (EMU with convenience accessors for points/inches)
- [x] 4.6 Implement image reading (`p:pic` with `a:blip r:embed` resolution)
- [x] 4.7 Implement table reading (`p:graphicFrame > a:tbl` with cell text extraction)
- [x] 4.8 Implement speaker notes reading from `ppt/notesSlides/`
- [x] 4.9 Implement slide transition reading
- [x] 4.10 Implement shape fill and outline reading (solid fill, theme color fill, gradient fill, outline)

## 5. PPTX Write — Slide Management

- [x] 5.1 Implement PptxWriter: serialize Presentation model to valid .pptx ZIP (save presentation, round-trip)
- [x] 5.2 Implement create new presentation with minimum valid OOXML structure
- [x] 5.3 Implement add slide with layout reference
- [x] 5.4 Implement delete slide (remove XML, rels, notes, update presentation.xml)
- [x] 5.5 Implement reorder slides (update `sldIdLst`)

## 6. PPTX Write — Shape Editing

- [x] 6.1 Implement insert text shape at position/size with initial text
- [x] 6.2 Implement update shape text (replace paragraphs)
- [x] 6.3 Implement delete shape from shape tree
- [x] 6.4 Implement insert image (base64/path → `p:pic` + media file + relationship)
- [x] 6.5 Implement insert table (`p:graphicFrame > a:tbl`) with dimensions
- [x] 6.6 Implement update table cell text
- [x] 6.7 Implement set shape properties (position, size, fill color, outline)
- [x] 6.8 Implement add/update speaker notes
- [x] 6.9 Implement set slide transition

## 7. MCP Server — Session + Direct Mode (matching che-word-mcp)

- [x] 7.1 Set up MCP server skeleton (Server.swift, stdio transport) following che-word-mcp pattern
- [x] 7.2 Implement session mode lifecycle: `open_presentation` / `save_presentation` / `close_presentation` with doc_id tracking
- [x] 7.3 Implement direct mode read access with `source_path` parameter
- [x] 7.4 Implement presentation info tools: `get_presentation_info`, `get_slide_count`, `get_text`
- [x] 7.5 Implement slide content tools: `get_slide_text`, `get_slide_shapes`, `get_shape_text`, `get_slide_notes`
- [x] 7.6 Implement image tools: `list_images`, `export_image`, `insert_image`, `delete_image`
- [x] 7.7 Implement table tools: `get_tables`, `get_table_data`, `insert_table`, `update_cell`
- [x] 7.8 Implement slide management tools: `add_slide`, `delete_slide`, `reorder_slides`, `duplicate_slide`
- [x] 7.9 Implement shape editing tools: `insert_text_shape`, `update_shape_text`, `delete_shape`, `set_shape_position`, `set_shape_size`, `set_shape_fill`
- [x] 7.10 Implement search tool: `search_text` across all slides
- [x] 7.11 Implement export tool: `export_markdown` with slide separators
- [x] 7.12 Implement theme and master tools: `get_theme`, `get_slide_master`, `get_slide_layouts`

## 8. Testing & Integration

- [x] 8.1 Write unit tests for PptxReader (ZIP extraction, relationship parsing, model construction)
- [x] 8.2 Write unit tests for shape tree traversal and text extraction
- [x] 8.3 Write unit tests for PptxWriter (round-trip: open → modify → save → re-open → verify)
- [x] 8.4 Integration test: build MCP server in release mode, verify tool list via stdio
- [x] 8.5 Test with diverse .pptx files (PowerPoint, Google Slides export, Keynote export)
