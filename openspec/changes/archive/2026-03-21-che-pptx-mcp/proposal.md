## Why

macdoc already has che-word-mcp (148 tools) for .docx manipulation and che-pdf-mcp (25 tools) for PDF processing. PowerPoint (.pptx) is the third major Office format but has no MCP support. Adding che-pptx-mcp lets Claude read, analyze, and modify presentations — extracting text, images, speaker notes, and slide structure from .pptx files.

## What Changes

- New `pptx-swift` package (Layer 1) for parsing PresentationML XML inside .pptx ZIP archives
- New `che-pptx-mcp` MCP server (Layer 4) exposing ~40-50 tools for slide read/write
- Reuse existing ooxml-swift infrastructure: `ZipHelper`, `Relationship`, `ImageReference`, `DocumentProperties`
- New Swift models: `Presentation`, `Slide`, `Shape`, `TextBody`, `Theme`, `SlideMaster`, `SlideLayout`

## Capabilities

### New Capabilities

- `pptx-parsing`: Parse .pptx ZIP structure — slides, masters, layouts, themes, media, relationships
- `pptx-slide-read`: Read slide content — shapes, text bodies, images, tables, notes, transitions
- `pptx-slide-write`: Create and modify slides — add/delete/reorder slides, insert shapes/images/tables, update text
- `pptx-mcp-server`: MCP server exposing pptx-swift capabilities as ~40-50 tools with session/direct modes

### Modified Capabilities

(none)

## Impact

- New packages: `packages/pptx-swift/`, `mcp/che-pptx-mcp/`
- Dependency: ZIPFoundation (same as ooxml-swift)
- Shared code: `ZipHelper`, `Relationship` model, `ImageReference`, `DocumentProperties` from ooxml-swift
- CLI integration (future): `macdoc convert --to md file.pptx` route in MacDoc+Convert.swift
- Platform: macOS 14+ (same as existing packages)
