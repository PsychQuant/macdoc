## ADDED Requirements

### Requirement: Shape tree traversal

The system SHALL traverse the shape tree (`p:spTree`) of each slide and return all elements as typed `SlideElement` values: Shape, Picture, GraphicFrame, or GroupShape.

#### Scenario: Mixed content slide

- **WHEN** a slide contains a text box, an image, and a table
- **THEN** the system returns three SlideElement values with correct types and properties

### Requirement: Text extraction from shapes

The system SHALL extract text from shape text bodies (`p:txBody > a:p > a:r > a:t`), preserving paragraph boundaries and run-level formatting (font, size, bold, italic, color, underline).

#### Scenario: Multi-paragraph text box

- **WHEN** a shape contains 3 paragraphs with different formatting
- **THEN** the system returns all 3 paragraphs with their respective runs and formatting properties

#### Scenario: Plain text extraction

- **WHEN** the caller requests plain text from a slide
- **THEN** the system concatenates all text from all shapes, separated by newlines per paragraph and double newlines per shape

### Requirement: Placeholder identification

The system SHALL identify shapes that are placeholders (`<p:ph type="..."/>`) and report their type: title, body (ctrTitle, subTitle, dt, ftr, sldNum, etc.).

#### Scenario: Title and body detection

- **WHEN** a slide has a title placeholder and a body placeholder
- **THEN** the system marks them with `placeholder: .title` and `placeholder: .body` respectively

### Requirement: Shape geometry and positioning

The system SHALL read shape position (`a:off x, y`) and size (`a:ext cx, cy`) in EMU, and provide convenience accessors for points and inches. Preset geometry type (`a:prstGeom prst="rect"`) SHALL be preserved.

#### Scenario: Position reading

- **WHEN** a shape has `<a:off x="914400" y="1828800"/>`
- **THEN** the system reports position as (914400, 1828800) EMU or (1.0, 2.0) inches

### Requirement: Image reading

The system SHALL read picture shapes (`p:pic`), resolving the embedded image reference (`a:blip r:embed`) to the actual media file, and report dimensions and image format.

#### Scenario: Embedded image resolution

- **WHEN** a picture shape references `r:embed="rId3"`
- **THEN** the system resolves it to the media file path and returns image data, format, and dimensions

### Requirement: Table reading

The system SHALL read tables inside graphic frames (`p:graphicFrame > a:graphic > a:graphicData > a:tbl`), extracting grid dimensions, cell text, and cell formatting.

#### Scenario: Table data extraction

- **WHEN** a slide contains a 3x4 table
- **THEN** the system returns 3 columns, 4 rows, and the text content of each cell

### Requirement: Speaker notes reading

The system SHALL read speaker notes from `ppt/notesSlides/notesSlideN.xml`, extracting the text content associated with each slide.

#### Scenario: Notes extraction

- **WHEN** slide 1 has associated notes
- **THEN** the system returns the notes text for slide 1

#### Scenario: Slide without notes

- **WHEN** a slide has no associated notes file
- **THEN** the system returns nil/empty for that slide's notes

### Requirement: Slide transition reading

The system SHALL read slide transition settings (`p:transition`) including transition type and speed.

#### Scenario: Fade transition

- **WHEN** a slide has `<p:transition spd="med"><p:fade/></p:transition>`
- **THEN** the system reports transition type "fade" with speed "medium"

### Requirement: Shape fill and outline reading

The system SHALL read shape fill (`a:solidFill`, `a:gradFill`, `a:noFill`) and outline (`a:ln`) properties.

#### Scenario: Solid fill color

- **WHEN** a shape has `<a:solidFill><a:srgbClr val="FF0000"/></a:solidFill>`
- **THEN** the system reports fill color as "#FF0000"

#### Scenario: Theme color fill

- **WHEN** a shape has `<a:solidFill><a:schemeClr val="accent1"/></a:solidFill>`
- **THEN** the system resolves "accent1" to the actual hex color from the theme
