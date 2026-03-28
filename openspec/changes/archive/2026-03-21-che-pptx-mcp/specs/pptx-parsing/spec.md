## ADDED Requirements

### Requirement: ZIP extraction and content discovery

The system SHALL extract .pptx files as ZIP archives and discover all contained XML parts: `[Content_Types].xml`, relationship files (`_rels/*.rels`), slides, slide masters, slide layouts, themes, media, and notes.

#### Scenario: Valid .pptx file extraction

- **WHEN** a valid .pptx file path is provided
- **THEN** the system extracts the ZIP to a temporary directory, parses `[Content_Types].xml`, and returns a list of all content parts with their types

#### Scenario: Invalid or corrupt file

- **WHEN** a non-ZIP or corrupt .pptx file is provided
- **THEN** the system SHALL throw a descriptive error without crashing

### Requirement: Relationship parsing

The system SHALL parse `.rels` files at all levels (package-level `_rels/.rels`, presentation-level `ppt/_rels/presentation.xml.rels`, and per-slide `ppt/slides/_rels/slideN.xml.rels`) to resolve references between parts.

#### Scenario: Slide relationship resolution

- **WHEN** a slide references an image via `r:embed="rId2"`
- **THEN** the system resolves `rId2` to the actual media file path (e.g., `ppt/media/image1.png`)

### Requirement: Presentation model construction

The system SHALL parse `ppt/presentation.xml` to build a `Presentation` model containing the ordered slide list, slide size, and references to masters/layouts/theme.

#### Scenario: Slide ordering

- **WHEN** `presentation.xml` contains `<p:sldIdLst>` with multiple entries
- **THEN** the system returns slides in the order specified by `p:sldId` elements

### Requirement: Theme parsing

The system SHALL parse `ppt/theme/theme1.xml` to extract the color scheme (12 named colors: dk1, lt1, dk2, lt2, accent1-6, hlink, folHlink), font scheme (major/minor), and format scheme.

#### Scenario: Color scheme extraction

- **WHEN** a theme file contains `<a:clrScheme>`
- **THEN** the system extracts all 12 named colors as hex RGB values

### Requirement: Slide master and layout parsing

The system SHALL parse slide masters (`ppt/slideMasters/`) and slide layouts (`ppt/slideLayouts/`) to extract placeholder definitions and default formatting.

#### Scenario: Placeholder type identification

- **WHEN** a slide master contains `<p:ph type="title"/>` and `<p:ph type="body"/>`
- **THEN** the system identifies these placeholder types for inheritance resolution

### Requirement: Media extraction

The system SHALL extract all media files from `ppt/media/` and associate them with their referencing slides via relationship IDs.

#### Scenario: Image listing

- **WHEN** a presentation contains 3 images across 2 slides
- **THEN** the system returns all 3 images with their file names, formats, sizes, and owning slide indices

### Requirement: Document properties parsing

The system SHALL parse `docProps/core.xml` and `docProps/app.xml` to extract metadata (title, author, created date, modified date, slide count, etc.).

#### Scenario: Core properties extraction

- **WHEN** `core.xml` contains `<dc:title>`, `<dc:creator>`, and `<dcterms:created>`
- **THEN** the system returns these as structured `DocumentProperties`
