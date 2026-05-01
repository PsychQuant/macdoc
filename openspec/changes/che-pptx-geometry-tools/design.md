## Context

`pptx-swift` already models EMU-based positions and sizes for shapes and pictures, and `che-pptx-mcp` exposes lower-level tools such as `insert_image`, `move_shape`, and `resize_shape`. In real deck authoring, agents and users reason in centimetres and bounding boxes, not EMUs. The first #90 slice therefore targets metric geometry and picture placement while leaving text, templates, notes, export, scripts, and references for later issues.

The existing MCP server is session-first for mutating operations. This change keeps that model: geometry tools mutate an opened `doc_id`, mark the session dirty, and rely on `save_presentation` for persistence.

## Goals / Non-Goals

**Goals:**

- Add deterministic cm-to-EMU and EMU-to-cm helpers in `pptx-swift`.
- Add library helpers that update existing shape/picture geometry in centimetres.
- Add image fit math for `contain`, `cover`, and `stretch` inside a target cm box.
- Add MCP tools for placeholder geometry, picture placement, and native-aspect placement.
- Verify saved PPTX output through model readback and math-level tests.

**Non-Goals:**

- Add rich text/rich bullet tools.
- Add slide master copying, template deletion, or layout cloning.
- Add presenter notes export, PDF export, or PNG rendering.
- Add Swift scripts or `references/python-pptx`.
- Verify visual rendering in Keynote, PowerPoint, or LibreOffice.

## Decisions

### Add metric geometry primitives to pptx-swift

`pptx-swift` owns geometry primitives because the conversion constants and fit algorithms are presentation-model concerns, not MCP transport concerns. Add a small public surface such as `MetricGeometry`, `GeometryFitMode`, `ImagePlacement`, and conversion helpers that use 360000 EMU per centimetre. Rounding SHALL be deterministic, with half-up rounding for centimetre-to-EMU conversions.

Alternative considered: perform cm conversion only inside `che-pptx-mcp`. Rejected because scripts and future non-MCP callers need the same calculations, and duplicating conversion constants invites drift.

### Keep MCP geometry tools session-only

The new tools mutate an opened presentation using `doc_id`. They do not accept `source_path` direct mode because direct mode is read-only in the current server contract. Each successful tool call marks the presentation dirty and returns the final EMU and cm geometry so callers can log exact placement.

Alternative considered: add direct-mode write tools with `source_path` and `output_path`. Rejected because that would introduce a second persistence model outside the existing open/save lifecycle.

### Resolve placeholders by slide index and placeholder identity

`set_placeholder_geometry` targets a slide by `slide_index` and identifies a placeholder by either shape id or placeholder type plus optional occurrence index. If both shape id and placeholder type are omitted, the tool returns a validation error. If placeholder type resolves to multiple shapes without an occurrence index, the tool returns an ambiguity error.

Alternative considered: target placeholders only by numeric shape id. Rejected because template-driven deck authoring usually starts from semantic placeholder roles such as title, body, and subtitle.

### Centralize image fit rectangle math

`place_picture_at` and `fit_picture_to_native_aspect` both call the same fit helper. `stretch` uses the target box exactly. `contain` preserves native aspect and fits entirely inside the target box. `cover` preserves native aspect and fills the target box, allowing crop metadata or an explicitly oversized picture rectangle depending on existing writer support. The initial implementation records whichever representation the writer can faithfully persist and documents unsupported crop output as an explicit error if necessary.

Alternative considered: implement `contain` first and silently map `cover` to `contain`. Rejected because silent remapping would mislead agents building pixel-sensitive medical or conference decks.

### Read image dimensions through native macOS image metadata

Use a macOS-native image metadata path such as CoreGraphics ImageIO to read width and height from PNG and JPEG files for `fit_picture_to_native_aspect`. The package already targets macOS, so this avoids adding a new third-party dependency. Unsupported image formats return a typed validation error before the presentation is mutated.

Alternative considered: require callers to pass `native_width` and `native_height`. Rejected because it pushes a common, deterministic operation onto every caller and recreates the Python-script burden #90 is trying to remove.

## Risks / Trade-offs

- [Risk] Existing writer support for crop metadata is incomplete. → Mitigation: `cover` either emits persisted crop data with readback tests or returns an unsupported-fit error; it never silently behaves like `contain`.
- [Risk] Image metadata APIs differ across file formats. → Mitigation: Phase 1 supports PNG and JPEG and returns a typed unsupported-format error for other formats.
- [Risk] Placeholder lookup by type can be ambiguous. → Mitigation: require occurrence index or shape id when more than one placeholder of the requested type exists on a slide.
- [Risk] Geometry math regressions are easy to miss visually. → Mitigation: add exact conversion tests, fit rectangle examples, and saved-readback tests for final EMU values.
