## 1. pptx-swift — metric geometry module (TDD)

- [ ] 1.1 Write failing tests at packages/pptx-swift/Tests/PPTXSwiftTests/MetricGeometryTests.swift covering spec Requirement "Centimeter-EMU conversion is exact-ratio and round-trip stable": the 6-row worked-conversion table from `##### Example: Worked conversions` (2.0cm→720000, 3.0cm→1080000, 10.0cm→3600000, 2.54cm→914400, 9144000EMU→25.4, 6858000EMU→19.05) as parameterized cases, plus round-trip stability (`abs(cm(emu(x)) - x) < 0.0001` for x in 0, 0.01, 2.54, 33.33, 100). **Verify**: `swift test --filter MetricGeometryTests` fails with "cannot find PPTXMetric" (RED).

- [ ] 1.2 Implement packages/pptx-swift/Sources/PPTXSwift/Geometry/MetricGeometry.swift per design "Decision 1: cm↔EMU conversion is a pure-function pair on Double, rounding half-away-from-zero to Int EMU" and design "Decision 2: Geometry module extends existing types rather than introducing parallel ones": `PPTXMetric.emu(fromCm:)` (Int((cm * 360_000).rounded())) + `PPTXMetric.cm(fromEmu:)`; extensions adding `Position.xCm/.yCm`, `Size.widthCm/.heightCm` getters, `Position(xCm:yCm:)` / `Size(widthCm:heightCm:)` initializers, `SlideSize.widthCm/.heightCm` getters (mirroring the existing xInches/xPoints accessor pattern). Covers spec Requirement "Existing geometry types gain centimeter accessors" (both Scenarios: default-slide 25.4/19.05 + cm-denominated construction). **Verify**: 1.1 tests pass (GREEN) + new accessor tests for both Scenarios green.

- [ ] 1.3 Write failing tests then implement `NativeAspect.pixelDimensions(of: Data)` in the Geometry module per design "Decision 3: Native aspect via ImageIO (CGImageSource) on embedded media bytes" — header-only `CGImageSourceCopyPropertiesAtIndex` property read. Covers spec Requirement "Native pixel dimensions are read via ImageIO header-only decode": a programmatically-generated 1600x1200 PNG (CoreGraphics-drawn in test code, no fixture file) returns (1600, 1200); random non-image bytes throw `PPTXError` (typed, not crash) per Scenario "Undecodable media is a typed error". **Verify**: `swift test --filter NativeAspectTests` green.

- [ ] 1.4 Write failing tests then implement `Shape.setGeometry(xCm:yCm:widthCm:heightCm:)` mutating offset/extent EMU. Covers spec Requirement "Shape geometry mutation in centimeters" — all Scenarios: "Setting shape geometry" (2.0/3.0/10.0/7.5 cm → offset (720000, 1080000) + extent (3600000, 2700000)), "Group-child rejection" (shapes inside GroupShape throw typed error), and `##### Example: Aspect-fit derivation` (1600x1200 image + width 10.0cm → derived height 7.5cm → extent (3600000, 2700000)). **Verify**: `swift test` green across pptx-swift.

- [ ] 1.5 Commit, push, tag pptx-swift v0.2.0 per the swift-package-update rule (commit in package repo → push → tag → push --tags). **Verify**: GitHub shows v0.2.0 tag; `git -C packages/pptx-swift describe --tags` prints v0.2.0.

## 2. che-pptx-mcp — three geometry tools

- [ ] 2.1 Bump mcp/che-pptx-mcp/Package.swift pptx-swift dependency `from: "0.1.0"` → `from: "0.2.0"`, run `swift package update && swift build -c release` in mcp/che-pptx-mcp. **Verify**: build succeeds; `PPTXMetric` symbols resolve.

- [ ] 2.2 Add `set_placeholder_geometry` tool to mcp/che-pptx-mcp/Sources/ChePPTXMCP/Server.swift, implementing spec Requirement "Centimeter-denominated geometry tools" per design "Decision 4: Tool boundary is cm-Double; addressing follows the existing slide_index + shape_id convention": params (doc_id, slide_index, shape_id, x_cm, y_cm, width_cm, height_cm); description states "any shape (placeholder or otherwise)" per design Risk "Tool name set_placeholder_geometry implies placeholder-only"; covers Scenarios "set_placeholder_geometry mutates any shape's geometry", "Off-slide placement warns but succeeds" (apply + warning naming exceeded bound), "Non-positive dimensions are a hard error" (error before mutation); response carries cm (2-decimal) + EMU geometry. **Verify**: XCTest against the handler asserts the Scenario values (2.0/3.0/10.0/7.5 cm → 720000/1080000/3600000/2700000 EMU) + warning/error cases.

- [ ] 2.3 Add `place_picture_at` tool per design "Decision 5: place_picture_at composes insert + geometry rather than duplicating insert logic": params (doc_id, slide_index, image_path or image_base64, x_cm, y_cm, width_cm, optional height_cm); omitted height_cm derives from native aspect via NativeAspect, undecodable media → error instructing explicit height_cm (design Risk "ImageIO unavailable for exotic embedded media"). Covers spec Requirement "Centimeter-denominated geometry tools" Scenario "place_picture_at inserts and positions in one call" (response includes new shape_id). **Verify**: XCTest inserts a generated 4:3 PNG with width_cm 10.0 and asserts extent (3600000, 2700000) + shape_id present.

- [ ] 2.4 Add `fit_picture_to_native_aspect` tool covering spec Requirement "Centimeter-denominated geometry tools" Scenarios "fit_picture_to_native_aspect re-derives the non-anchored dimension" (3600000x1800000 distorted + anchor width → 3600000x2700000) and "fit on a non-picture shape is an error": params (doc_id, slide_index, shape_id, anchor "width"|"height"); group-child → error (consistent with 1.4 group-child rejection). **Verify**: XCTest distorts then fits and asserts both Scenarios.

- [ ] 2.5 Update the tool-count reference in mcp/che-pptx-mcp/README.md (37 → 40) and add the three tools to its tool table with one-line descriptions naming cm-denominated params. **Verify**: README lists 40 tools with the 3 new entries.

## 3. Reference + docs

- [ ] 3.1 [P] Add python-pptx row to reference/README.md clone-on-demand table: repo URL https://github.com/scanny/python-pptx, role "API-shape reference for metric geometry (Cm/Emu/Length util classes) — no code ported", consumer "pptx-swift Geometry module". **Verify**: row present; no python-pptx code appears anywhere in packages/.

- [ ] 3.2 [P] Update macdoc CLAUDE.md Sub-Repositories table pptx-swift row to mention v0.2.0+ metric geometry, and grep docs/ + CLAUDE.md for stale "37" che-pptx-mcp tool-count references (update to 40 where found). **Verify**: grep returns no stale counts.

## 4. Verification gates

- [ ] 4.1 Full test suites: `swift test` in packages/pptx-swift and `swift test` in mcp/che-pptx-mcp both green. **Verify**: zero failures; new tests (MetricGeometryTests, NativeAspectTests, 3 tool XCTests) all listed in output.

- [ ] 4.2 Run `spectra validate pptx-geometry-tools` from macdoc root. **Verify**: exits 0 with "valid".

- [ ] 4.3 Integration smoke: via MCP stdio against the release binary, open a fresh presentation → `place_picture_at` (generated 4:3 PNG, x_cm 2.0, y_cm 3.0, width_cm 10.0) → `get_slide_shapes` reports the picture at the requested cm values; then `set_placeholder_geometry` moves it to (5.0, 5.0) with no warning field; then x_cm 30.0 produces the off-slide warning. **Verify**: all three assertions pass; transcript attached to the #90 umbrella comment at close time.
