## Why

PowerPoint geometry in OOXML is expressed in EMU (914,400 per inch; 360,000 per cm) — unreadable and error-prone for users and AI agents placing content on slides. Today `che-pptx-mcp`'s `insert_image` / `insert_text_shape` accept raw EMU or default placement only; there is no way to say "place this picture at 2cm from the left, 3cm from the top, 10cm wide, keeping its native aspect ratio". PR #95 attempted exactly this slice and was closed unmerged (2026-05-25); its scope was re-confirmed at the 2026-06-12 `/spectra-discuss` for #90 as the first of three partitioned slices (geometry-tools now; `pptx-edit-isomorphism-foundation` and mpptx scripting deferred — see #90 umbrella).

Per the discuss verdict, this slice implements directly on Layer 1 (`PPTXSwift` models, same pattern as the existing ~37 MCP tools) with **no Edit-algebra dependency** — the Edit-algebra driver (replayable typed edits for scripting) is not yet scheduled.

## What Changes

1. **pptx-swift** gains a metric geometry module: cm ↔ EMU conversion types, slide-dimension queries in cm, placeholder geometry mutation, and native-aspect-fit computation for pictures.
2. **che-pptx-mcp** gains 3 tools (37 → 40): `set_placeholder_geometry`, `place_picture_at`, `fit_picture_to_native_aspect` — all cm-denominated at the tool boundary, converting to EMU internally.
3. **reference/README.md** gains a python-pptx row (clone-on-demand, API-shape reference for its `Cm` / `Emu` / `Length` util classes — no copied code, mirroring the docx.js precedent for word-builder-swift).

## Non-Goals

- **No PPTX Edit algebra / lens model / op-log** — deferred to `pptx-edit-isomorphism-foundation` (opens when mpptx scripting is scheduled; tracked on #90 umbrella).
- **No `.mpptx` scripting surface** — third slice on #90.
- **No EMU-denominated tool variants** — cm is the only unit at the MCP boundary (matches python-pptx user expectations; EMU remains internal).
- **No slide-size mutation** — tools read slide dimensions but do not change them.
- **No python-pptx code port** — reference is API-shape only.

## Capabilities

### New Capabilities

- `pptx-metric-geometry`: cm-denominated geometry primitives over PPTXSwift — cm↔EMU conversion, slide dimensions in cm, placeholder geometry set, native-aspect picture fit.

### Modified Capabilities

- `pptx-mcp-server`: tool count 37 → 40; adds the 3 geometry tools with cm-denominated parameters.

## Impact

- Affected specs: `pptx-metric-geometry` (new), `pptx-mcp-server` (modified)
- Affected code:
  - New: packages/pptx-swift/Sources/PPTXSwift/Geometry/MetricGeometry.swift, packages/pptx-swift/Tests/PPTXSwiftTests/MetricGeometryTests.swift
  - Modified: mcp/che-pptx-mcp/Sources/ChePPTXMCP/Server.swift, packages/pptx-swift/Sources/PPTXSwift/Models/Shape.swift, reference/README.md
  - Removed: (none)
