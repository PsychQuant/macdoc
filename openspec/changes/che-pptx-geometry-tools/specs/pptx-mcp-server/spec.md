## ADDED Requirements

### Requirement: Placeholder geometry MCP tool

The MCP server SHALL expose a session-mode tool named `set_placeholder_geometry`. The tool SHALL require `doc_id`, `slide_index`, `left_cm`, `top_cm`, `width_cm`, and `height_cm`. The tool SHALL identify the target placeholder by either `shape_id` or `placeholder_type` plus optional `occurrence_index`. A successful call SHALL mutate the open presentation, mark it dirty, and return the final geometry in both centimetres and EMU.

#### Scenario: Set placeholder geometry by shape id

- **WHEN** the caller invokes `set_placeholder_geometry` with `doc_id: "deck"`, `slide_index: 0`, `shape_id: 5`, left 1.0 cm, top 2.0 cm, width 10.0 cm, and height 4.0 cm
- **THEN** the shape with id 5 is updated to the corresponding EMU geometry
- **AND** the open presentation is marked dirty
- **AND** the response includes the final cm and EMU geometry

#### Scenario: Ambiguous placeholder type fails

- **WHEN** a slide contains two body placeholders and the caller invokes `set_placeholder_geometry` with `placeholder_type: "body"` and no `occurrence_index`
- **THEN** the tool returns an ambiguity error and does not mutate the presentation

### Requirement: Place picture at MCP tool

The MCP server SHALL expose a session-mode tool named `place_picture_at`. The tool SHALL require `doc_id`, `slide_index`, `image_path`, `left_cm`, `top_cm`, `width_cm`, `height_cm`, and `fit`. The `fit` value SHALL be one of `contain`, `cover`, or `stretch`. A successful call SHALL insert the image as a picture, mark the presentation dirty, and return the created picture id plus final geometry.

#### Scenario: Insert contained picture through MCP

- **WHEN** the caller invokes `place_picture_at` with fit `contain` for an 800x600 image inside a 10 cm by 10 cm box
- **THEN** the tool inserts a picture whose persisted geometry preserves 4:3 aspect ratio
- **AND** the response includes the created picture id and final geometry

#### Scenario: Invalid fit value fails

- **WHEN** the caller invokes `place_picture_at` with fit `tile`
- **THEN** the tool returns a validation error and does not mutate the presentation

### Requirement: Fit picture to native aspect MCP tool

The MCP server SHALL expose a session-mode tool named `fit_picture_to_native_aspect`. The tool SHALL require `doc_id`, `slide_index`, `image_path`, `anchor`, `max_width_cm`, and `max_height_cm`. The `anchor` value SHALL be one of `left`, `center`, or `right`. The tool SHALL read native image dimensions, calculate a contained rectangle inside the maximum box, align it horizontally according to `anchor`, insert the picture, mark the presentation dirty, and return the created picture id plus final geometry.

#### Scenario: Fit native aspect centered

- **WHEN** the caller invokes `fit_picture_to_native_aspect` with a 1600x900 image, anchor `center`, max width 12 cm, and max height 8 cm
- **THEN** the inserted picture preserves 16:9 aspect ratio inside the maximum box
- **AND** the picture is horizontally centered within the maximum box

#### Scenario: Unsupported native image format fails

- **WHEN** the image metadata reader cannot determine width and height for `image_path`
- **THEN** the tool returns an unsupported image format error and does not mutate the presentation

### Requirement: Geometry tool persistence through save

Geometry and picture placement changes made through the new MCP tools SHALL persist after `save_presentation` and re-open through `pptx-swift` readback.

#### Scenario: Save and read back geometry update

- **WHEN** the caller opens a presentation, calls `set_placeholder_geometry`, saves it to `out.pptx`, and reads `out.pptx`
- **THEN** the updated placeholder geometry in the readback model matches the requested centimetre values converted to EMU

#### Scenario: Save and read back inserted picture

- **WHEN** the caller opens a presentation, calls `place_picture_at`, saves it to `out.pptx`, and reads `out.pptx`
- **THEN** the readback model contains the inserted picture with the expected final geometry
