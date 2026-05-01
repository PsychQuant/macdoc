## 1. pptx-swift Geometry Foundation

- [ ] 1.1 Implement Metric geometry conversion and tests in packages/pptx-swift, following Add metric geometry primitives to pptx-swift with 360000 EMU per centimetre and half-up rounding.
- [ ] 1.2 Implement Set shape geometry in centimetres for Shape and Picture models, including negative-value validation and unchanged-model assertions on failure.
- [ ] 1.3 Implement Image fit rectangle calculation with contain, cover, and stretch examples, following Centralize image fit rectangle math.
- [ ] 1.4 Implement Native image dimension reading for PNG and JPEG through macOS image metadata, following Read image dimensions through native macOS image metadata.
- [ ] 1.5 Implement Insert picture with fit mode so persisted picture geometry matches the calculated fit rectangle or returns an unsupported-fit error before mutation.

## 2. che-pptx-mcp Tool Surface

- [ ] 2.1 Add Placeholder geometry MCP tool schema and handler for `set_placeholder_geometry`, following Keep MCP geometry tools session-only and Resolve placeholders by slide index and placeholder identity.
- [ ] 2.2 Add Place picture at MCP tool schema and handler for `place_picture_at`, validating fit values and returning created picture id plus final geometry.
- [ ] 2.3 Add Fit picture to native aspect MCP tool schema and handler for `fit_picture_to_native_aspect`, validating anchor values and using native image dimensions.
- [ ] 2.4 Add Geometry tool persistence through save tests that open, mutate, save, and read back PPTX geometry for placeholder and picture placement.

## 3. Documentation and Scope Guard

- [ ] 3.1 Update README.md or MCP tool documentation with cm-based examples for all three new tools and explicitly defer rich text, template copying, notes, export, scripts, and python-pptx references to later #90 slices.
- [ ] 3.2 Run package-level tests for packages/pptx-swift and mcp/che-pptx-mcp, plus Spectra validation for che-pptx-geometry-tools.
