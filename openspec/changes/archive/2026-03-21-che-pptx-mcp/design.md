## Context

macdoc has established patterns for OOXML processing via ooxml-swift (DOCX) and MCP servers via che-word-mcp (148 tools) and che-pdf-mcp (25 tools). PowerPoint .pptx files use the same OOXML standard (ECMA-376 PresentationML) — a ZIP archive of XML files. The infrastructure for ZIP extraction, relationship parsing, image handling, and document properties already exists.

PPTX differs from DOCX in its data model: DOCX is document-centric (linear paragraphs/tables), while PPTX is canvas-centric (slides contain shape trees with absolute positioning). Text lives inside shapes via DrawingML (`a:p > a:r > a:t`), not directly in the body.

## Goals / Non-Goals

**Goals:**

- Parse .pptx files: slides, shapes, text, images, tables, notes, theme, masters, layouts
- Provide read/write MCP tools (~40-50) following che-word-mcp patterns (session + direct mode)
- Reuse ooxml-swift's ZipHelper, Relationship, ImageReference, DocumentProperties
- Support the three-layer style inheritance: Theme → SlideMaster → SlideLayout → Slide

**Non-Goals:**

- Animation/timing support (`p:timing`) — too complex, low MCP value
- Chart editing (`c:chart`) — requires DrawingML Charts sub-specification
- SmartArt / diagrams — requires separate DrawingML Diagram spec
- Audio/video playback — MCP is text-based
- CLI integration (`macdoc convert --to md file.pptx`) — future work, not in this change

## Decisions

### Two-package architecture

Create `pptx-swift` (Layer 1 format parser) separate from `che-pptx-mcp` (Layer 4 MCP server), mirroring the ooxml-swift / che-word-mcp split. This allows future converters (pptx-to-md, pptx-to-html) to depend on pptx-swift without pulling in MCP dependencies.

Alternative: single package with everything. Rejected — violates macdoc's layered architecture principle.

### Reuse ooxml-swift via dependency, not fork

pptx-swift will depend on ooxml-swift for shared types: `ZipHelper`, `Relationship`, `ImageReference`, `DocumentProperties`. DrawingML text models (`a:p`, `a:r`, `a:rPr`) will be new types in pptx-swift because PresentationML uses different properties than WordprocessingML.

Alternative: fork shared code into pptx-swift. Rejected — duplication, maintenance burden.

### EMU coordinate system

PPTX uses English Metric Units (EMU) for all positioning: 1 inch = 914400 EMU. The internal model stores EMU natively. Convenience accessors convert to points/inches/cm for MCP tool responses.

### Session + Direct mode (matching che-word-mcp)

Direct mode (`source_path`) for read-only operations. Session mode (`doc_id` via open/save/close) for read-write. This matches the established che-word-mcp pattern for consistency.

### Shape-centric model

The core model is `Slide > ShapeTree > SlideElement` where SlideElement is an enum of Shape, Picture, GraphicFrame, GroupShape. This directly maps to the PresentationML structure (`p:spTree > p:sp | p:pic | p:graphicFrame | p:grpSp`).

### Theme color resolution via lookup table

Theme colors (`dk1`, `lt1`, `accent1`-`accent6`, etc.) are resolved at read time into a color lookup table. Shapes reference scheme colors; the resolver maps them to actual hex values. This avoids repeated XML traversal.

## Risks / Trade-offs

- [Risk] Theme/Master/Layout inheritance is complex — shapes inherit properties through a three-layer chain → Mitigation: Start with direct slide properties only; add inheritance resolution incrementally
- [Risk] Real-world .pptx files vary widely (Google Slides, Keynote exports, older PowerPoint versions) → Mitigation: Test with diverse sample files; graceful fallback for unsupported elements
- [Risk] DrawingML text formatting (`a:rPr`) has many attributes → Mitigation: Implement core attributes first (font, size, bold, italic, color); extend as needed
- [Trade-off] Not supporting animations means some presentation metadata is lost → Acceptable for MCP use case (text extraction, content editing)
