## ADDED Requirements

### Requirement: Form-gap measurement names the first offending form

When typed extraction of a part bails to the raw channel, the transcoder SHALL record a structured form-gap: the part path, the XML path to the first offending node or attribute, and the content-class tag. The reverse result SHALL expose these records programmatically so tests and baselines can enumerate exactly which form blocks an upgrade. An upgraded part SHALL have no form-gap record.

#### Scenario: bail names the offending attribute

- **GIVEN** a document.xml whose third paragraph carries a `w:rsidR` attribute the vocabulary does not yet support
- **WHEN** reverse runs and the part stays raw
- **THEN** the result contains a form-gap naming that paragraph's XML path and the offending attribute

#### Scenario: upgraded part reports no gaps

- **WHEN** a document.xml passes the trial-rebuild byte-equal gate and upgrades
- **THEN** its form-gap list is empty

### Requirement: Word-canonical form vocabulary

Reverse extraction SHALL recognize, and the rebuild path SHALL re-serialize byte-equal, the following Word-authored forms in addition to the writer's own forms: document root elements with arbitrary namespace declarations and `mc:Ignorable` (order-preserved), paragraph- and run-level revision-session-id attributes (rsid family, order-preserved, semantically opaque), and `xml:space="preserve"` on text elements. Long-tail rPr/pPr/sectPr elements SHALL be added measurement-first: each class enters the vocabulary only with a corresponding upgrade-class regression pin, and a form the serializer cannot reproduce byte-equal SHALL stay on the raw channel per the existing gate — no canonical-form exemptions.

#### Scenario: real template document.xml upgrades

- **GIVEN** the env-gated real template whose document.xml uses only supported vocabulary
- **WHEN** reverse runs and the script re-executes
- **THEN** document.xml is rebuilt through the DSL channel byte-equal and per-part coverage for it reports 100%

#### Scenario: rsid attributes round-trip

- **GIVEN** a source paragraph carrying `w:rsidR` and `w:rsidRDefault` attributes
- **WHEN** the paragraph is extracted and rebuilt
- **THEN** the rebuilt `<w:p>` carries the same attributes with the same values in the same order

#### Scenario: unsupported long-tail form stays raw with attribution

- **GIVEN** a document.xml containing an element outside the supported vocabulary
- **WHEN** reverse runs
- **THEN** the part stays on the raw channel, Stage B remains green, and the form-gap report names the element

### Requirement: Content slots work on upgraded real templates

A real Word document whose document.xml has upgraded to the DSL channel SHALL accept slot designation: the slotted script executes with caller-provided content producing a docx whose non-slot parts are byte-equal to the reference and whose designated positions carry the new content with the reference's formatting intact.

#### Scenario: title and body slots on the real template

- **GIVEN** the env-gated real template upgraded to the DSL channel with paragraphs designated title and body
- **WHEN** the slotted script executes with new title and body text
- **THEN** the output docx carries the new text in those positions, sibling parts byte-equal to the reference, and the reference's styles and section layout intact
