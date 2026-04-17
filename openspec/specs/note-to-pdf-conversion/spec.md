# note-to-pdf-conversion Specification

## Purpose

Renders `ParsedNote` handwritten strokes and embedded images into a static multi-page PDF via Core Graphics. Coordinate transform (scale + Y-flip) maps Notability space to PDF space. Images render as background; audio is skipped.

## Requirements

- NoteToPDFConverter renders strokes to multi-page PDF
- Coordinate transform applies scale and Y-flip
- Images render as background layer under strokes
- CLI route converts .note to PDF
