## Context

PPTX geometry lives in EMU integers (`a:off x/y`, `a:ext cx/cy`): 914,400 EMU per inch, 360,000 EMU per cm. `PPTXSwift` names these models `Position` (x/y, the `a:off`) and `Size` (width/height, the `a:ext`) in packages/pptx-swift/Sources/PPTXSwift/Models/Shape.swift — they already store EMU `Int`s and expose `xInches` / `xPoints` convenience accessors, but no centimeter accessors, and nothing converts the *inbound* direction (cm → EMU). `che-pptx-mcp` (37 tools) addresses shapes by `slide_index` + `shape_id` (integer) and operates directly on Layer 1 models — no Edit algebra exists for PPTX (per the 2026-06-12 #90 discuss verdict, that foundation is deferred until mpptx scripting is scheduled).

This change revives the PR #95 slice: cm-denominated geometry at the MCP boundary, EMU internally. Three stakeholding surfaces: `pptx-swift` (geometry module), `che-pptx-mcp` (3 new tools), `reference/README.md` (python-pptx API-shape row).

## Goals / Non-Goals

**Goals**

- A user or AI agent can place and resize slide content in centimeters without ever seeing an EMU.
- Aspect-correct picture placement: given a target width, height derives from the image's native pixel dimensions.
- Tool semantics match python-pptx user expectations (its `Cm()` constructor is the de-facto mental model for scripted PPTX geometry).

**Non-Goals**

- No PPTX Edit algebra / op-log / lens model (deferred; #90 umbrella slice 2).
- No EMU- or inch-denominated MCP parameter variants — cm only at the boundary.
- No slide-size mutation; no new shape creation (the 3 tools mutate geometry of *existing* shapes/pictures, except `place_picture_at` which composes existing `insert_image` + geometry set).
- No python-pptx code port.

## Decisions

### Decision 1: cm↔EMU conversion is a pure-function pair on Double, rounding half-away-from-zero to Int EMU

`emu(fromCm:) = Int((cm * 360_000).rounded())` and `cm(fromEmu:) = Double(emu) / 360_000`. Rationale: 1 cm = exactly 360,000 EMU, so error only enters via Double cm inputs; `.rounded()` (half-away-from-zero) keeps 0.5-boundary behavior intuitive for users typing `2.54`. Alternative considered: banker's rounding (`.toNearestOrEven`) — rejected: no accumulation context exists (each conversion is independent), and half-away matches python-pptx's `Cm()` int truncation behavior more closely at typical 1-2 decimal inputs.

### Decision 2: Geometry module extends existing types rather than introducing parallel ones

New file packages/pptx-swift/Sources/PPTXSwift/Geometry/MetricGeometry.swift adds `cm`-suffixed accessors to the existing `Position` / `Size` (e.g., `xCm`, `widthCm`) plus inbound constructors (`Position(xCm:yCm:)`, `Size(widthCm:heightCm:)`), and a `SlideSize.widthCm/heightCm` query. Rationale: the existing `xInches` / `xPoints` accessors establish this exact pattern — cm is the third unit family on the same types. Alternative considered: a separate `MetricPoint` / `MetricSize` value-type layer — rejected: parallel types force conversions at every call-site and diverge from the established model shape.

### Decision 3: Native aspect via ImageIO (CGImageSource) on embedded media bytes

`fit_picture_to_native_aspect` reads the picture's embedded media data from the archive and decodes pixel dimensions with `CGImageSourceCreateWithData` + `CGImageSourceCopyPropertiesAtIndex` (kCGImagePropertyPixelWidth/Height) — header-only, no full bitmap decode. Rationale: native-macos-compat rule mandates CoreGraphics/ImageIO for image work; header-only property read is O(KB) even for large images. Alternative considered: parsing PNG/JPEG headers by hand — rejected: ImageIO covers all formats PowerPoint embeds (PNG, JPEG, GIF, TIFF, BMP, HEIC) for free.

### Decision 4: Tool boundary is cm-Double; addressing follows the existing slide_index + shape_id convention

All three tools take `Double` cm parameters and integer `slide_index` / `shape_id` (same as the 37 existing tools). Out-of-slide-bounds placement is allowed with a warning in the response (PowerPoint itself permits off-slide content; hard-rejecting breaks legitimate bleed/overflow layouts). Non-positive width/height is a hard error. Rationale: consistency with the existing Server.swift surface beats novel addressing; warning-not-error for bounds matches PowerPoint semantics.

### Decision 5: place_picture_at composes insert + geometry rather than duplicating insert logic

`place_picture_at` = existing image-insertion path + immediate geometry set in one tool call (image source params + `x_cm` / `y_cm` / `width_cm`, height derived from native aspect unless `height_cm` given). Rationale: zero duplication of media-part plumbing; the tool exists because two-step insert-then-position forces the agent to re-discover the shape_id between calls.

## Implementation Contract

**pptx-swift `pptx-metric-geometry` surface** (packages/pptx-swift/Sources/PPTXSwift/Geometry/MetricGeometry.swift):

- `PPTXMetric.emu(fromCm: Double) -> Int` and `PPTXMetric.cm(fromEmu: Int) -> Double`; round-trip `cm(fromEmu: emu(fromCm: x))` differs from `x` by < 0.0001 for `x` in [0, 100].
- `Position.xCm` / `Position.yCm` / `Size.widthCm` / `Size.heightCm` (get) and `Position(xCm:yCm:)` / `Size(widthCm:heightCm:)` (init); `SlideSize.widthCm` / `SlideSize.heightCm` (get). Default slide: widthCm = 25.4, heightCm = 19.05.
- `NativeAspect.pixelDimensions(of imageData: Data) throws -> (width: Int, height: Int)` via ImageIO; throws `PPTXError` for undecodable data.
- `Shape.setGeometry(xCm:yCm:widthCm:heightCm:)` mutates the shape's `position` (a:off) and `size` (a:ext) in EMU.

**che-pptx-mcp tools** (mcp/che-pptx-mcp/Sources/ChePPTXMCP/Server.swift, 37 → 40 tools):

- `set_placeholder_geometry(doc_id, slide_index, shape_id, x_cm, y_cm, width_cm, height_cm)` — mutates any shape's geometry (placeholder or not; name keeps PR #95 continuity, description clarifies). Error if shape_id not found; warning field in response if geometry extends beyond slide bounds.
- `place_picture_at(doc_id, slide_index, image_path | image_base64, x_cm, y_cm, width_cm, height_cm?)` — inserts image and sets geometry in one call; `height_cm` omitted → derived from native aspect.
- `fit_picture_to_native_aspect(doc_id, slide_index, shape_id, anchor: "width"|"height")` — re-derives the non-anchored dimension from the embedded image's native aspect; error if the shape is not a picture or media is undecodable.
- All three return the resulting geometry in both cm (2-decimal) and EMU in the response payload, so agents can verify without a follow-up read.

**Acceptance criteria**: unit tests for conversion round-trip + boundary rounding; golden geometry test using the spec's worked example (2cm, 3cm, 10cm on a 4:3 picture → EMU 720000/1080000/3600000/2700000); MCP-level test that `place_picture_at` then `get_slide_shapes` reports the requested cm values; `swift test` green in both repos.

**Out of scope**: shape rotation (`rot` attribute), flip flags, group-shape child geometry (child transforms compound — needs its own design), slide-size mutation.

## Risks / Trade-offs

- [Tool name `set_placeholder_geometry` implies placeholder-only but works on any shape] → Keep name for PR #95 continuity; tool description states "any shape (placeholder or otherwise)". Revisit at rename-cost only if user confusion materializes.
- [ImageIO unavailable for exotic embedded media (EMF/WMF vector metafiles)] → `fit_picture_to_native_aspect` returns a typed error naming the media format; `place_picture_at` with omitted height falls back to requiring explicit `height_cm` (error message says so).
- [Group-shape children: setting geometry on a child inside `GroupShape` produces wrong visual position (parent transform compounds)] → Phase 1 rejects shape_ids that live inside groups with a clear error; lifted when group transforms are designed.
- [Two repos must release in lockstep (pptx-swift tag → che-pptx-mcp dependency bump)] → Same flow as every existing pptx-swift change; tasks sequence the tag-then-bump explicitly.

## Migration Plan

Additive only — no existing tool signatures change, no behavior changes for the 37 existing tools. Deploy = pptx-swift tag + che-pptx-mcp rebuild/release per the repo's standard release flow. Rollback = revert the dependency bump; no data-format implications (EMU was and remains the stored unit).
