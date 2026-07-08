## ADDED Requirements

### Requirement: Format-payload additive extensions

Payload types SHALL gain additive optional fields required by five-layer extraction: `RunPayload` gains font (ascii/eastAsia), size, underline, and vertical-alignment fields; `ParagraphPayload` gains spacing, indentation, alignment, and numbering-reference fields; a `SectionPayload` carries page size, margins, orientation, column count, and header/footer references. All extensions follow the additive-only wire discipline (#128): existing JSONL lines decode unchanged, absent fields mean "not specified", and new field names SHALL NOT collide with the envelope keys op_id / ts / source / op_type (v1.0.2 moveNode lesson).

#### Scenario: old sidecar decodes under extended payloads

- **WHEN** a v1.0.x oplog sidecar is decoded by a build carrying the extended payloads
- **THEN** every line decodes with the new fields absent and replay behavior is unchanged

#### Scenario: extended fields round-trip the wire

- **GIVEN** an appendParagraph whose RunPayload carries eastAsia font and size
- **WHEN** the entry is encoded to JSONL and decoded back
- **THEN** the payload round-trips field-for-field with camelCase discriminators per the OOXML-mirror naming table
