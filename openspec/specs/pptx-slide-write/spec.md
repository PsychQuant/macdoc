# pptx-slide-write Specification

## Purpose

Create and modify .pptx content — add/delete/reorder slides, insert/update/delete shapes, images, and tables, manage speaker notes and transitions, serialize back to valid .pptx ZIP.

## Requirements

### Requirement: Create new presentation

The system SHALL create a new empty .pptx file with a valid OOXML structure including `[Content_Types].xml`, package relationships, a default theme, one slide master, and one slide layout.

#### Scenario: Empty presentation creation

- **WHEN** the caller creates a new presentation
- **THEN** the system generates a valid .pptx with the minimum required XML parts


<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - packages/pptx-swift/Sources/PPTXSwift/IO/PptxWriter.swift
-->

---
### Requirement: Add slide

The system SHALL add new slides to a presentation, referencing a specified slide layout. The new slide SHALL contain placeholder shapes inherited from the layout.

#### Scenario: Add slide with title layout

- **WHEN** the caller adds a slide using the "Title Slide" layout
- **THEN** the new slide contains title and subtitle placeholder shapes


<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - packages/pptx-swift/Sources/PPTXSwift/Models/Presentation.swift
-->

---
### Requirement: Delete slide

The system SHALL delete a slide by index, removing the slide XML, its relationships, notes (if any), and updating `presentation.xml`.

#### Scenario: Delete middle slide

- **WHEN** a 5-slide presentation has slide 3 deleted
- **THEN** the presentation contains 4 slides and all references are updated


<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - packages/pptx-swift/Sources/PPTXSwift/Models/Presentation.swift
-->

---
### Requirement: Reorder slides

The system SHALL reorder slides by updating the `<p:sldIdLst>` in `presentation.xml`.

#### Scenario: Move slide to new position

- **WHEN** slide 4 is moved to position 1
- **THEN** the slide order in `presentation.xml` reflects the new arrangement


<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - packages/pptx-swift/Sources/PPTXSwift/Models/Presentation.swift
-->

---
### Requirement: Insert text shape

The system SHALL insert a new text shape at a specified position and size, with initial text content.

#### Scenario: Insert text box

- **WHEN** the caller inserts a text shape at position (100, 200) with size (400, 100) and text "Hello"
- **THEN** the slide contains a new `p:sp` with the specified geometry and text body


<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - packages/pptx-swift/Sources/PPTXSwift/Models/Shape.swift
  - packages/pptx-swift/Sources/PPTXSwift/IO/PptxWriter.swift
-->

---
### Requirement: Update shape text

The system SHALL update the text content of an existing shape, replacing all paragraphs or appending new ones.

#### Scenario: Replace text

- **WHEN** the caller updates shape id=5 with new text "Updated content"
- **THEN** the shape's `p:txBody` contains the new text


<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - packages/pptx-swift/Sources/PPTXSwift/Models/Shape.swift
  - packages/pptx-swift/Sources/PPTXSwift/Models/TextBody.swift
-->

---
### Requirement: Delete shape

The system SHALL remove a shape from a slide's shape tree by shape ID.

#### Scenario: Remove shape

- **WHEN** shape id=7 is deleted from slide 2
- **THEN** the shape tree no longer contains the element with id=7


<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - packages/pptx-swift/Sources/PPTXSwift/Models/Slide.swift
-->

---
### Requirement: Insert image

The system SHALL insert an image (from file path or base64) as a `p:pic` element, creating the media file in `ppt/media/` and the relationship entry.

#### Scenario: Insert image from base64

- **WHEN** the caller provides base64 image data, position, and size
- **THEN** the slide contains a new `p:pic` element and the image is stored in `ppt/media/`


<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - packages/pptx-swift/Sources/PPTXSwift/Models/Picture.swift
  - packages/pptx-swift/Sources/PPTXSwift/IO/PptxWriter.swift
-->

---
### Requirement: Insert table

The system SHALL insert a table as a `p:graphicFrame` containing `a:tbl`, with specified column count, row count, and optional initial data.

#### Scenario: Create 3x2 table

- **WHEN** the caller inserts a table with 3 columns and 2 rows
- **THEN** the slide contains a graphic frame with a DrawingML table of the specified dimensions


<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - packages/pptx-swift/Sources/PPTXSwift/Models/GraphicFrame.swift
  - packages/pptx-swift/Sources/PPTXSwift/IO/PptxWriter.swift
-->

---
### Requirement: Update table cell

The system SHALL update the text content of a table cell by row and column index.

#### Scenario: Update cell text

- **WHEN** the caller updates cell (row=1, col=2) with text "Revenue"
- **THEN** the cell's text body contains "Revenue"


<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - packages/pptx-swift/Sources/PPTXSwift/Models/GraphicFrame.swift
-->

---
### Requirement: Set shape properties

The system SHALL update shape visual properties: position, size, fill color, outline color/width.

#### Scenario: Change fill color

- **WHEN** the caller sets shape fill to "#0066CC"
- **THEN** the shape's `spPr` contains `<a:solidFill><a:srgbClr val="0066CC"/></a:solidFill>`


<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - packages/pptx-swift/Sources/PPTXSwift/Models/Shape.swift
-->

---
### Requirement: Add/update speaker notes

The system SHALL create or update the notes slide (`notesSlideN.xml`) associated with a slide.

#### Scenario: Add notes to slide without notes

- **WHEN** the caller adds notes "Key talking point" to slide 3 which has no notes
- **THEN** a new `notesSlide3.xml` is created with the text content and linked via relationships


<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - packages/pptx-swift/Sources/PPTXSwift/Models/Slide.swift
-->

---
### Requirement: Set slide transition

The system SHALL set transition type and speed on a slide.

#### Scenario: Set fade transition

- **WHEN** the caller sets transition "fade" with speed "slow" on slide 1
- **THEN** slide 1's XML contains `<p:transition spd="slow"><p:fade/></p:transition>`


<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - packages/pptx-swift/Sources/PPTXSwift/Models/Slide.swift
-->

---
### Requirement: Save presentation

The system SHALL serialize the in-memory presentation model back to a valid .pptx ZIP file, preserving all parts and relationships.

#### Scenario: Round-trip save

- **WHEN** a presentation is opened, modified, and saved
- **THEN** the saved .pptx is a valid ZIP with correct `[Content_Types].xml` and all relationship files

<!-- @trace
source: che-pptx-mcp
updated: 2026-03-21
code:
  - packages/pptx-swift/Sources/PPTXSwift/IO/PptxWriter.swift
-->