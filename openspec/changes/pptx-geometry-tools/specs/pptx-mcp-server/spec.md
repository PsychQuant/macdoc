## ADDED Requirements

### Requirement: Centimeter-denominated geometry tools

The MCP server SHALL expose three geometry tools whose length parameters are denominated exclusively in centimeters (Double) at the tool boundary, converting to EMU internally: `set_placeholder_geometry`, `place_picture_at`, and `fit_picture_to_native_aspect`. Shape addressing SHALL follow the existing `slide_index` + `shape_id` convention. Each tool's response SHALL include the resulting geometry in both cm (2-decimal precision) and EMU so callers can verify placement without a follow-up read.

#### Scenario: set_placeholder_geometry mutates any shape's geometry

- **GIVEN** an open presentation and a top-level shape with a known shape_id
- **WHEN** the caller invokes set_placeholder_geometry with x_cm 2.0, y_cm 3.0, width_cm 10.0, height_cm 7.5
- **THEN** the shape's stored offset MUST be (720000, 1080000) EMU and extent (3600000, 2700000) EMU
- **AND** the response MUST report both the cm and EMU values

#### Scenario: Off-slide placement warns but succeeds

- **GIVEN** a default slide (25.4 cm wide)
- **WHEN** the caller sets a shape's geometry with x_cm 30.0 (beyond the right edge)
- **THEN** the tool MUST apply the geometry
- **AND** the response MUST contain a warning naming the exceeded bound

#### Scenario: Non-positive dimensions are a hard error

- **WHEN** the caller invokes any geometry tool with width_cm 0 or a negative height_cm
- **THEN** the tool MUST return an error without mutating the document

#### Scenario: place_picture_at inserts and positions in one call

- **GIVEN** an open presentation and a 1600 x 1200 pixel PNG
- **WHEN** the caller invokes place_picture_at with x_cm 2.0, y_cm 3.0, width_cm 10.0 and no height_cm
- **THEN** the picture MUST be inserted with offset (720000, 1080000) EMU and extent (3600000, 2700000) EMU (height derived from the 4:3 native aspect)
- **AND** the response MUST include the new shape_id

#### Scenario: fit_picture_to_native_aspect re-derives the non-anchored dimension

- **GIVEN** a picture shape whose current extent is 3600000 x 1800000 EMU (distorted) and whose embedded image is 4:3
- **WHEN** the caller invokes fit_picture_to_native_aspect with anchor "width"
- **THEN** the extent MUST become 3600000 x 2700000 EMU (height re-derived)

#### Scenario: fit on a non-picture shape is an error

- **GIVEN** a shape_id that addresses a text shape
- **WHEN** the caller invokes fit_picture_to_native_aspect
- **THEN** the tool MUST return an error stating the shape is not a picture
