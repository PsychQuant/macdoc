## ADDED Requirements

### Requirement: ZIP extraction

The system SHALL extract `.note` files as ZIP archives using ZIPFoundation and provide access to all contained entries (plists, recordings, images).

#### Scenario: Valid note file extraction

- **WHEN** a valid `.note` file is provided as input
- **THEN** the system extracts all entries to a temporary directory, locates the note subdirectory, and returns paths to `Session.plist`, `metadata.plist`, `Recordings/`, `Images/`, and `HandwritingIndex/`

#### Scenario: Invalid or corrupted file

- **WHEN** the input file is not a valid ZIP archive or is corrupted
- **THEN** the system SHALL throw `NoteError.invalidZIP` with a 繁體中文 error message and exit with non-zero status

### Requirement: GLKeyedArchiver plist navigation

The system SHALL parse `Session.plist` using `PropertyListSerialization` and navigate the GLKeyedArchiver `$objects` array via UID references. UIDs stored as `CFKeyedArchiverUID` (`__NSCFType`) SHALL be parsed from their description string (`{value = N}`). The `$top` key SHALL be read as `$0` (GLKeyedArchiver convention, not `root`).

#### Scenario: Navigate to root object

- **WHEN** `Session.plist` is parsed
- **THEN** the system reads `$top.$0` as a UID, resolves it through `$objects` to reach the root `SessionInfo` dictionary containing `richText`, `contentPlaybackEventManager`, and `NBNoteTakingSessionDocumentPaperLayoutModelKey`

#### Scenario: Resolve UID-referenced string values

- **WHEN** a dictionary value (e.g., `documentOrigin`) is a UID pointing to a string in `$objects`
- **THEN** the `PlistNavigator` SHALL dereference the UID to retrieve the actual string value (e.g., `"{276.7, 331.9}"`)

### Requirement: Stroke data extraction via SpatialHash

The system SHALL extract stroke data from `richText` → `Handwriting Overlay` → `SpatialHash`, NOT directly from the `Handwriting Overlay` object. The `SpatialHash` contains all binary stroke buffers.

#### Scenario: Decode stroke curves

- **WHEN** the `SpatialHash` object contains `curvespoints`, `curvesnumpoints`, `curvescolors`, `curveswidth`, and `numcurves`
- **THEN** the system SHALL decode: `curvespoints` as Float32 x,y interleaved pairs, `curvesnumpoints` as UInt32 (points per curve), `curvescolors` as UInt32 RGBA, `curveswidth` as Float32, `curvesstyles` as UInt8 (1 byte per curve)

#### Scenario: Compute stroke bounds

- **WHEN** strokes are decoded
- **THEN** the system SHALL compute the bounding box (minX, minY, maxX, maxY) across all curve points

#### Scenario: Extract curveUUIDs

- **WHEN** the `SpatialHash` contains a `curveUUIDs` Data field
- **THEN** the system SHALL split it into 16-byte UUID chunks, one per curve, for timeline mapping

### Requirement: Page layout extraction

The system SHALL extract page count from `richText.pageLayoutArray` and paper width from `NBNoteTakingSessionDocumentPaperLayoutModelKey` → `documentPaperAttributes` → `paperSizingBehavior`.

#### Scenario: Extract page dimensions

- **WHEN** `paperSizingBehavior` contains a string like `"lockedWidth:583.8:iPad"`
- **THEN** the system SHALL parse the width (583.8) and compute `pageHeight` as `totalContentY / pageCount`

### Requirement: Timeline event decoding with UUID mapping

The system SHALL decode the `NBCPEventManager` object and map event UUIDs to curve indices via `curveUUIDs`.

#### Scenario: Decode and map timeline

- **WHEN** `contentPlaybackEventManager` contains `SOATimestampsKey`, `SOADurationsKey`, `SOARecordingIDsKey`, and `SOAEventUUIDsKey`
- **THEN** the system SHALL decode each as typed arrays, build a UUID→curveIndex mapping from `curveUUIDs`, and produce timeline events with correct curve indices (not sequential event indices)

#### Scenario: No recording present

- **WHEN** `contentPlaybackEventManager` is absent or `SOANumEventsKey` is 0
- **THEN** the system SHALL produce an empty timeline and all strokes SHALL be rendered statically

### Requirement: Recording metadata parsing

The system SHALL parse `Recordings/library.plist` to extract recording metadata (filename, duration, identifier) sorted by identifier.

#### Scenario: Multiple recordings

- **WHEN** `library.plist` contains multiple recording entries
- **THEN** the system SHALL parse all entries, sort by identifier, and read corresponding m4a files as Data for base64 encoding

### Requirement: Image extraction with positions

The system SHALL extract PNG files from `Images/` and their positions from `Session.plist` `mediaObjects`. Position values (`documentOrigin`, `unscaledContentSize`) are UID references to string values that SHALL be dereferenced before parsing.

#### Scenario: Embedded images with positions

- **WHEN** `mediaObjects` contains entries with `documentOrigin` and `unscaledContentSize` as UIDs
- **THEN** the system SHALL dereference UIDs to get strings like `"{276.7, 331.9}"`, parse as point/size, and associate with corresponding image files

### Requirement: Handwriting index parsing

The system SHALL parse `HandwritingIndex/index.plist` when present.

#### Scenario: Index available

- **WHEN** `HandwritingIndex/index.plist` exists
- **THEN** the system SHALL produce a searchable index mapping text strings to stroke index ranges

#### Scenario: Index absent

- **WHEN** `HandwritingIndex/index.plist` does not exist
- **THEN** the system SHALL disable text search without error
