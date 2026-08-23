## Why

Notability exports from at least app version 16.8.1 can use a ZIP-based `.ntb` generation whose document body is the FlatBuffers `noteBundle` entry rather than the legacy plist-based `Session.plist`. macdoc currently forwards every `.note` input to the legacy parser and rejects `.ntb` as an unsupported extension, so modern Notability containers receive a misleading diagnostic or no generation-specific guidance.

## What Changes

- Add bounded, metadata-only ZIP entry classification for legacy `Session.plist` and modern `noteBundle` containers without extracting or reading document payloads.
- Accept `.ntb` as a recognized note input only to emit a precise fail-loud unsupported-generation diagnostic for HTML and PDF targets.
- Detect a modern container even when it has been renamed with a `.note` suffix, while preserving the existing legacy `.note` conversion path.
- Reject malformed, ZIP64, or over-complex `.ntb` inputs locally so classification cannot trigger unbounded central-directory work or leak an input path through the legacy parser.
- Add compiled CLI acceptance for exact diagnostics and no output creation.
- Qualify README and conversion-matrix claims so interactive conversion is explicitly limited to legacy plist-based `.note`; modern `.ntb` is detected but not converted.

## Non-Goals

- Reverse-engineering or parsing the `noteBundle`, handwriting, or recording FlatBuffers schemas.
- Extracting `assets/` audio or `thumbnail.png` as a degraded conversion path.
- Claiming interactive replay, HTML, or PDF support for modern `.ntb` files.
- Inspecting `manifest.json` contents or any private note payload.

## Capabilities

### New Capabilities

- `notability-container-detection`: Metadata-only classification and generation-specific CLI rejection for modern Notability `.ntb` containers.

### Modified Capabilities

- `e2e-conversion-routes`: Add compiled route coverage for modern `.ntb` and renamed modern `.note` rejection without partial output.

## Impact

- Affected specs: `notability-container-detection`, `e2e-conversion-routes`
- Affected code:
  - New: `Sources/NotabilityContainerDetection/NotabilityContainerDetector.swift`, `Tests/MacDocCLITests/NotabilityContainerDetectionTests.swift`
  - Modified: `Package.swift`, `Sources/MacDocCLI/MacDoc+Convert.swift`, `README.md`, `CONVERSIONS.md`
  - Removed: none
- Dependency surface: declare the already-resolved `ZIPFoundation` package and isolate it behind a lightweight `NotabilityContainerDetection` target used by the CLI and tests. This avoids linking the full executable target into XCTest merely to test the detector.
