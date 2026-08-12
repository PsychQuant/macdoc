## ADDED Requirements

### Requirement: Classify Notability container generation from ZIP entry metadata

MacDocCLI SHALL classify a readable Notability archive as legacy when a regular ZIP entry's final path component is `Session.plist`. If no legacy marker exists, it SHALL classify the archive as modern FlatBuffers when a regular entry's final path component is `noteBundle`. It SHALL otherwise classify the archive as unknown. Classification SHALL enumerate entry paths only and SHALL NOT extract or read entry payloads, `manifest.json`, note content, media, or indexes.

#### Scenario: Classify a legacy archive

- **WHEN** a readable ZIP contains `export/Session.plist`
- **THEN** the detector classifies it as legacy even if another entry is named `noteBundle`

#### Scenario: Classify a modern archive

- **WHEN** a readable ZIP contains `noteBundle` and contains no `Session.plist`
- **THEN** the detector classifies it as modern FlatBuffers without reading the `noteBundle` payload

#### Scenario: Preserve unknown archive handling

- **WHEN** the file is not a readable ZIP or contains neither generation marker
- **THEN** the detector classifies it as unknown and the established downstream parser remains responsible for the final malformed or missing-session diagnostic

### Requirement: Reject modern FlatBuffers note conversion precisely and before output

The HTML and PDF note routes SHALL recognize both `.note` and `.ntb` input suffixes. Before constructing a converter or creating output, they SHALL reject a modern FlatBuffers classification with the exact diagnostic `偵測到新版 Notability .ntb 容器（noteBundle／FlatBuffers）；目前僅支援舊版 plist-based .note（Session.plist）`. The rejection SHALL be local, SHALL emit no stdout, SHALL create no destination file or directory, and SHALL NOT log archive entry lists, paths, payloads, or manifest content.

#### Scenario: Reject a modern .ntb HTML conversion

- **WHEN** `macdoc convert --to html modern.ntb --output out` receives a ZIP containing `noteBundle`
- **THEN** the command exits non-zero with the exact modern-container diagnostic, empty stdout, and no `out` destination

#### Scenario: Reject a modern .ntb PDF conversion

- **WHEN** `macdoc convert --to pdf modern.ntb --output out.pdf` receives a ZIP containing `noteBundle`
- **THEN** the command exits non-zero with the exact modern-container diagnostic, empty stdout, and no `out.pdf`

#### Scenario: Reject a renamed modern container

- **WHEN** the same modern ZIP is named `modern.note` and requested as HTML
- **THEN** the command produces the same modern-container rejection instead of the legacy missing-session diagnostic

#### Scenario: Preserve legacy note conversion

- **WHEN** a `.note` ZIP contains a parseable `Session.plist`
- **THEN** the detector permits the existing HTML or PDF converter to process the archive unchanged

### Requirement: State the Notability generation support boundary

User-facing note conversion documentation SHALL identify plist-based `.note` with `Session.plist` as the implemented interactive HTML/PDF input and modern `.ntb` with FlatBuffers `noteBundle` as detected-but-not-supported. The documentation SHALL NOT claim FlatBuffers handwriting, timeline, recording, thumbnail, HTML, or PDF support.

#### Scenario: Read note conversion documentation

- **WHEN** a user reads README or the conversion matrix
- **THEN** they can distinguish the supported legacy `.note` generation from the precisely detected but unsupported modern `.ntb` generation
