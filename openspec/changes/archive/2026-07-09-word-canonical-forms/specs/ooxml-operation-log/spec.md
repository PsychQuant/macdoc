## ADDED Requirements

### Requirement: Word-form payload additive extensions

Payload types SHALL gain additive optional fields for Word-canonical forms: `ParagraphPayload` and `RunPayload` gain revision-session-id fields (rsid family, opaque strings); `RunPayload` gains a preserve-space flag (↔ `xml:space="preserve"` on `<w:t>`); a new `setDocumentRoot` operation carries the document root's attribute list as an order-significant array of prefix/localName/value triples. All extensions follow the additive-only wire discipline: existing JSONL lines decode unchanged, absent fields mean "not specified", and new field names SHALL NOT collide with the envelope keys op_id / ts / source / op_type.

#### Scenario: old sidecar decodes under Word-form extensions

- **WHEN** a pre-extension oplog sidecar is decoded by a build carrying the Word-form payload fields
- **THEN** every line decodes with the new fields absent and replay behavior is unchanged

#### Scenario: setDocumentRoot round-trips the wire order-preserved

- **GIVEN** a `setDocumentRoot` op carrying five namespace declarations and `mc:Ignorable` in a specific order
- **WHEN** the entry is encoded to JSONL and decoded back
- **THEN** the attribute array round-trips field-for-field in the same order

#### Scenario: rsid fields round-trip field-for-field

- **GIVEN** an appendParagraph whose payload carries rsidR and rsidRDefault values
- **WHEN** the entry is encoded to JSONL and decoded back
- **THEN** the payload round-trips field-for-field

### Requirement: Document root stamping replaces attributes wholesale

The reducer SHALL apply `setDocumentRoot` by replacing the document root element's attribute list with the op's attributes in array order. When the op is absent the authoring default root (minimal namespace set) SHALL remain unchanged, preserving all existing behavior.

#### Scenario: root attributes stamped in order

- **GIVEN** an empty authoring document and a `setDocumentRoot` op with an ordered attribute list
- **WHEN** the op applies
- **THEN** the root element carries exactly those attributes in that order

#### Scenario: absent op keeps the default root

- **WHEN** a script without `setDocumentRoot` executes
- **THEN** the rebuilt root carries the authoring default namespace set, byte-identical to pre-extension behavior
