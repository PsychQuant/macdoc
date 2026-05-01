## Why

Issue #90 identifies a real PPTX authoring bottleneck: geometry and image-placement edits currently require low-level EMU math and repeated Python rebuild/render loops. The first coherent slice is cm-based geometry and picture-placement tooling, because it directly targets the highest-friction workflow while keeping rich text, template copying, notes, export, scripts, and references out of this PR-sized change.

## What Changes

- Add library-level helpers in `pptx-swift` for metric geometry:
  - Convert centimetres to EMU and EMU to centimetres with deterministic rounding.
  - Set an existing shape or picture frame's position and size using centimetres.
  - Compute contain, cover, and stretch placement rectangles for images inside a target box.
- Extend `che-pptx-mcp` with session-mode editing tools:
  - `set_placeholder_geometry` for cm-based placement of existing placeholder shapes.
  - `place_picture_at` for inserting a picture into a cm-based box with `contain`, `cover`, or `stretch` fit.
  - `fit_picture_to_native_aspect` for inserting a picture scaled to native aspect within a maximum cm box and aligned left, center, or right.
- Add focused tests that verify EMU conversion, fit rectangle math, MCP schema, and saved PPTX readback.
- Document the new tools as the first #90 sub-issue cluster and leave later clusters for separate changes.

## Non-Goals

- No rich bullet or run-style tooling in this change.
- No slide master/template-copying work in this change.
- No notes, PDF export, or slide PNG rendering in this change.
- No Swift script examples or `references/python-pptx` clone in this change.
- No visual rendering guarantee from Keynote or PowerPoint; this change verifies geometry through OOXML readback and deterministic math.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `pptx-slide-write`: Add cm-based geometry mutation and deterministic image fit rectangle behaviour for shapes and pictures.
- `pptx-mcp-server`: Expose the new geometry/image placement helpers as MCP tools with clear input schema and session-mode persistence.

## Impact

- Affected specs: pptx-slide-write, pptx-mcp-server
- Affected code:
  - Modified: packages/pptx-swift/Sources/PPTXSwift/Models/Shape.swift
  - Modified: packages/pptx-swift/Sources/PPTXSwift/Models/Picture.swift
  - Modified: packages/pptx-swift/Sources/PPTXSwift/Models/Slide.swift
  - Modified: packages/pptx-swift/Tests/PPTXSwiftTests/PPTXSwiftTests.swift
  - Modified: mcp/che-pptx-mcp/Sources/ChePPTXMCP/Server.swift
  - New: mcp/che-pptx-mcp/Tests/ChePPTXMCPTests/
  - Modified: README.md
- Related issue: #90
