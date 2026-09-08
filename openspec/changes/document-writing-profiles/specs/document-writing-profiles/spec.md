## ADDED Requirements

### Requirement: Profile selection
CLI and Word MCP SHALL share document configuration in the existing macdoc config object. New document creation SHALL resolve explicit profile before configured default before inherit. Existing document edits and script replay SHALL use a profile only when explicitly requested.

#### Scenario: Existing replay ignores creation default
- **GIVEN** defaultProfile is official
- **WHEN** script replay is requested without a profile
- **THEN** replay SHALL remain unchanged and SHALL retain its existing verification behavior.

#### Scenario: Explicit inheritance
- **WHEN** a new document request specifies inherit while defaultProfile is official
- **THEN** the document SHALL use inherit without opening the official snapshot.

### Requirement: Inherit preserves document-owned formatting
Inherit SHALL preserve an existing document's styles, theme and direct formatting. For new documents it SHALL omit concrete font choices and font-theme overrides introduced by the generator. It SHALL NOT read the user's Normal template.

#### Scenario: New inheritance document
- **WHEN** a new document is created with inherit
- **THEN** generated defaults SHALL contain no forced Calibri, Times New Roman, Calibri Light or substitute family.
- **AND** explicit caller formatting SHALL remain effective.

### Requirement: Safe official template snapshot
Official import SHALL read the selected Normal template without modifying it and SHALL construct a versioned formatting-only snapshot using an XML element and attribute allowlist. The snapshot SHALL preserve supported styles, docDefaults, paragraph defaults, safe font/theme settings and page geometry. It SHALL NOT carry source paths, document body text, macros, document properties, revisions, comments, external relationships, embedded fonts or image payloads.

#### Scenario: Template with unsafe ancillary content
- **GIVEN** a template containing body text, VBA, core properties, an external hyperlink and header references
- **WHEN** its formatting is imported
- **THEN** the snapshot SHALL exclude all those contents and references while retaining allowed page margins, sizes and style formatting.

#### Scenario: Corrupt or unsupported input
- **WHEN** the template cannot be parsed or required formatting cannot be represented safely
- **THEN** import SHALL report a named error and SHALL leave the previous snapshot and config unchanged.

### Requirement: Official formatting
Official SHALL apply the imported snapshot and override the Traditional Chinese font to 標楷體 using the OOXML family identifier DFKai-SB, removing conflicting eastAsiaTheme overrides and updating Hant theme mappings. Other supported Western, paragraph and page formatting SHALL come from the snapshot rather than fabricated public-document rules.

#### Scenario: Selected Normal geometry
- **GIVEN** a snapshot with page width 11906 twips, height 16838 twips, font size 24 half-points, vertical margins 1440 twips and horizontal margins 1800 twips
- **WHEN** official is applied
- **THEN** those values SHALL be preserved and the Traditional Chinese font SHALL be 標楷體 with serialized family DFKai-SB.

### Requirement: Snapshot stability and failures
Imported snapshots SHALL remain stable when the original template subsequently changes or disappears. Official selection with a missing, unsupported-version or corrupt snapshot SHALL fail explicitly without fallback.

#### Scenario: Missing official snapshot
- **WHEN** official is selected before successful import
- **THEN** the request SHALL fail before publishing or registering a new document session.

### Requirement: Shared explicit OOXML API
OOXMLSwift SHALL own snapshot import, validation and profile application. Its generic APIs SHALL NOT read application configuration implicitly. Explicit application SHALL synchronize typed state, XML trees, carried parts and package metadata so both ordinary writing and authoring replay honor the profile.

#### Scenario: Equivalent writers
- **WHEN** the same profile is applied and the document is emitted through ordinary and authoring writers
- **THEN** both outputs SHALL contain the selected defaults, styles, theme and page geometry without dangling relationships.

### Requirement: Verification before publication
Profile application SHALL happen before final verification and publication. CLI and MCP SHALL preserve existing overwrite refusal and failure atomicity. The verifier SHALL evaluate the profiled output, not the unmodified intermediate.

#### Scenario: Verification rejects changed format
- **GIVEN** an existing output file
- **WHEN** explicit official formatting makes replay differ from verifyAgainst
- **THEN** the request SHALL fail and SHALL preserve the output file byte-for-byte.

### Requirement: Configuration coexistence
AI, OCR and document configuration writes SHALL preserve fields owned by other consumers and unknown fields. Explicit clearing of a known optional field SHALL remove that field. Invalid JSON or a non-object root SHALL produce an error without overwriting the file.

#### Scenario: Alternating configuration writes
- **GIVEN** document and unknown extension fields coexist with AI and OCR values
- **WHEN** AI, OCR and document settings are updated successively
- **THEN** unrelated fields SHALL retain their structure and values.
- **AND** a cleared known optional setting SHALL not be restored from old JSON.

### Requirement: Cross-platform verification honesty
Completion evidence SHALL distinguish automated XML tests from Mac Word and Windows Word rendering checks. Missing platforms or required fonts SHALL remain explicitly unverified and SHALL NOT be counted as successful visual validation.

#### Scenario: No Windows environment
- **WHEN** only macOS is available
- **THEN** automated and Mac results SHALL be reported separately and Windows validation SHALL remain unchecked.
