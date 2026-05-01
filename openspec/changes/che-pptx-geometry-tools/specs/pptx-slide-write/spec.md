## ADDED Requirements

### Requirement: Metric geometry conversion

The system SHALL provide deterministic conversion helpers between centimetres and EMU for presentation geometry. The conversion SHALL use 360000 EMU per centimetre. Centimetre-to-EMU conversion SHALL round half-up to the nearest integer EMU. EMU-to-centimetre conversion SHALL return a Double value without truncating precision.

#### Scenario: Convert centimetres to EMU

- **WHEN** the caller converts 2.54 cm to EMU
- **THEN** the result is 914400 EMU

##### Example: conversion table

| Centimetres | Expected EMU |
| ----------- | ------------ |
| 0.0 | 0 |
| 1.0 | 360000 |
| 2.54 | 914400 |
| 10.0 | 3600000 |

#### Scenario: Convert EMU to centimetres

- **WHEN** the caller converts 914400 EMU to centimetres
- **THEN** the result is 2.54 cm within 0.0001 cm tolerance

### Requirement: Set shape geometry in centimetres

The system SHALL allow callers to set an existing shape or picture geometry using centimetre values for left, top, width, and height. The stored model SHALL update the underlying EMU position and size fields. Negative left, top, width, or height values SHALL fail validation before mutating the slide.

#### Scenario: Update shape geometry from centimetres

- **WHEN** a shape is updated to left 1.0 cm, top 2.0 cm, width 5.0 cm, and height 3.0 cm
- **THEN** the shape position is x 360000 EMU and y 720000 EMU
- **AND** the shape size is width 1800000 EMU and height 1080000 EMU

#### Scenario: Reject negative size

- **WHEN** the caller sets width to -1.0 cm
- **THEN** the system returns a validation error and leaves the shape geometry unchanged

### Requirement: Image fit rectangle calculation

The system SHALL calculate image placement rectangles for `contain`, `cover`, and `stretch` fit modes inside a target box. `contain` SHALL preserve image aspect ratio and fit entirely inside the target box. `cover` SHALL preserve image aspect ratio and fill the target box. `stretch` SHALL use the target box exactly and ignore native aspect ratio.

#### Scenario: Contain wide image in square box

- **WHEN** a 1600x900 image is placed with `contain` inside a 10 cm by 10 cm box
- **THEN** the calculated rectangle is 10 cm wide and 5.625 cm high
- **AND** the rectangle is vertically centered when center alignment is requested

#### Scenario: Cover wide image in square box

- **WHEN** a 1600x900 image is placed with `cover` inside a 10 cm by 10 cm box
- **THEN** the calculated rectangle fills at least 10 cm width and 10 cm height while preserving 16:9 aspect ratio

#### Scenario: Stretch image to target box

- **WHEN** a 1600x900 image is placed with `stretch` inside a 10 cm by 4 cm box
- **THEN** the calculated rectangle is exactly 10 cm wide and 4 cm high

### Requirement: Native image dimension reading

The system SHALL read native pixel dimensions for PNG and JPEG files used by picture placement helpers. Unsupported or unreadable image files SHALL fail validation before mutating the presentation.

#### Scenario: Read PNG dimensions

- **WHEN** the caller provides a PNG image file with native size 800x600 pixels
- **THEN** the system reports width 800 and height 600 for fit calculations

#### Scenario: Unsupported image format fails

- **WHEN** the caller provides an unsupported image format for native-aspect placement
- **THEN** the system returns an unsupported image format error before changing the slide

##### Example: SVG input is rejected

- **GIVEN** the caller provides `diagram.svg` to the native image dimension reader
- **WHEN** the reader attempts to determine pixel dimensions for picture placement
- **THEN** the system returns an unsupported image format error
- **AND** the slide model is unchanged

### Requirement: Insert picture with fit mode

The system SHALL insert a picture into a target centimetre box using the requested fit mode. The persisted picture geometry SHALL match the fit rectangle converted to EMU. If the writer cannot persist a requested cover/crop representation faithfully, the system SHALL return an unsupported fit error before mutating the presentation.

#### Scenario: Insert contained picture

- **WHEN** the caller inserts an 800x600 image into a 10 cm by 10 cm target box with `contain`
- **THEN** the persisted picture size is 10 cm by 7.5 cm converted to EMU

#### Scenario: Cover fails when unsupported

- **WHEN** the caller requests `cover` and the writer lacks faithful crop or oversized-picture persistence for the requested output
- **THEN** the system returns an unsupported fit error and leaves the slide unchanged
