## ADDED Requirements

### Requirement: Centimeter-EMU conversion is exact-ratio and round-trip stable

The library SHALL expose pure conversion functions between centimeters (Double) and EMU (Int) using the exact ratio 1 cm = 360,000 EMU, rounding half-away-from-zero when producing EMU.

#### Scenario: cm to EMU conversion

- **WHEN** a caller converts 2.0 cm to EMU
- **THEN** the result MUST be exactly 720000

#### Scenario: Round-trip stability

- **WHEN** a caller converts a cm value x in [0, 100] to EMU and back to cm
- **THEN** the recovered value MUST differ from x by less than 0.0001

##### Example: Worked conversions

- **GIVEN** the conversion functions
- **WHEN** converting the values below
- **THEN** the outputs MUST match this table:

| Input | Direction | Output |
|-------|-----------|--------|
| 2.0 cm | cm → EMU | 720000 |
| 3.0 cm | cm → EMU | 1080000 |
| 10.0 cm | cm → EMU | 3600000 |
| 2.54 cm | cm → EMU | 914400 |
| 9144000 EMU | EMU → cm | 25.4 |
| 6858000 EMU | EMU → cm | 19.05 |

### Requirement: Existing geometry types gain centimeter accessors

`Position` (the `a:off` model) and `Size` (the `a:ext` model) SHALL expose centimeter getters (`xCm`, `yCm`, `widthCm`, `heightCm`) and centimeter-denominated initializers, following the same pattern as the existing `xInches` / `xPoints` accessors. `SlideSize` SHALL expose `widthCm` / `heightCm` getters.

#### Scenario: Default slide dimensions in cm

- **GIVEN** a presentation with the default slide size (9144000 x 6858000 EMU)
- **WHEN** the caller reads `slideSize.widthCm` and `slideSize.heightCm`
- **THEN** the values MUST be 25.4 and 19.05 respectively

#### Scenario: Centimeter-denominated construction

- **WHEN** a caller constructs a Position with xCm 2.0 and yCm 3.0
- **THEN** the stored EMU values MUST be x = 720000 and y = 1080000

### Requirement: Native pixel dimensions are read via ImageIO header-only decode

The library SHALL expose a function returning the pixel dimensions of embedded image data using ImageIO (CGImageSource) property reads without decoding the full bitmap. Undecodable data (including vector metafiles such as EMF/WMF) SHALL produce a typed error naming the failure.

#### Scenario: Raster image dimensions

- **GIVEN** embedded PNG data with native size 1600 x 1200 pixels
- **WHEN** the caller requests pixel dimensions
- **THEN** the result MUST be width 1600, height 1200

#### Scenario: Undecodable media is a typed error

- **GIVEN** embedded data that ImageIO cannot decode
- **WHEN** the caller requests pixel dimensions
- **THEN** the call MUST throw a PPTXError (not crash, not return zero dimensions)

### Requirement: Shape geometry mutation in centimeters

`Shape` SHALL expose a geometry-set operation taking x, y, width, height in centimeters that writes the converted EMU values to the shape's offset and extent. Shapes that are children of a GroupShape SHALL be rejected with a typed error (parent transforms compound; group-child geometry is out of scope).

#### Scenario: Setting shape geometry

- **GIVEN** a top-level shape on a slide
- **WHEN** the caller sets geometry x 2.0 cm, y 3.0 cm, width 10.0 cm, height 7.5 cm
- **THEN** the shape's offset MUST be (720000, 1080000) EMU and extent MUST be (3600000, 2700000) EMU

#### Scenario: Group-child rejection

- **GIVEN** a shape nested inside a GroupShape
- **WHEN** the caller attempts to set its geometry
- **THEN** the call MUST throw a typed error explaining group-child geometry is unsupported

##### Example: Aspect-fit derivation

- **GIVEN** a picture whose embedded image is 1600 x 1200 pixels (4:3) placed with width 10.0 cm and no explicit height
- **WHEN** the height is derived from native aspect
- **THEN** the derived height MUST be 7.5 cm (3600000 x 2700000 EMU extent)
