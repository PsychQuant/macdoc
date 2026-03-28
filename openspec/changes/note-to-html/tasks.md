## 1. Package Setup

- [x] 1.1 Create `packages/note-to-html-swift/` with Package.swift, depending on `common-converter-swift` and `ZIPFoundation`
- [x] 1.2 Add `note-to-html-swift` dependency to root `Package.swift` and wire into MacDocCLI target
- [x] 1.3 Add `case ("note", "html")` route in `MacDoc+Convert.swift` following convert entry point convention

## 2. ZIP Extraction and GLKeyedArchiver Plist Navigation

- [x] 2.1 Implement ZIP extraction for `.note` files using ZIPFoundation, extracting to a temporary directory
- [x] 2.2 Implement GLKeyedArchiver plist navigation — use PropertyListSerialization with CFKeyedArchiverUID parsing, `PlistNavigator` to navigate `$objects` array, resolve `$top.$0` (not `root`), and parse UIDs from description strings
- [x] 2.3 Add error handling with 繁體中文 messages for invalid or corrupted files (NoteError enum)

## 3. Stroke Data Extraction via SpatialHash

- [x] 3.1 Implement stroke data extraction via SpatialHash — navigate Handwriting Overlay → SpatialHash for stroke data (not directly from Handwriting Overlay)
- [x] 3.2 Implement `StrokeDecoder` to decode binary float buffers: `curvespoints` (Float32 x,y interleaved), `curveswidth` (Float32), `curvescolors` (UInt32 RGBA), `curvesnumpoints` (UInt32), `curvesstyles` (UInt8)
- [x] 3.3 Extract `curveUUIDs` (16-byte UUIDs per curve) for timeline event decoding with UUID mapping
- [x] 3.4 Compute stroke bounds (minX, minY, maxX, maxY) across all curve points

## 4. Page Layout Extraction and Timeline

- [x] 4.1 Implement page layout extraction — extract page count from `pageLayoutArray` and paper width from `documentPaperAttributes.paperSizingBehavior`
- [x] 4.2 Implement timeline event decoding with UUID mapping — decode `NBCPEventManager`, map `SOAEventUUIDsKey` to curve indices via `curveUUIDs`
- [x] 4.3 Handle no-recording case: produce empty timeline when `contentPlaybackEventManager` is absent

## 5. Image Extraction with Positions and Recording Metadata

- [x] 5.1 Image positioning via UID-dereferenced mediaObjects — implement image extraction with positions, dereference `documentOrigin` and `unscaledContentSize` UIDs
- [x] 5.2 Implement recording metadata parsing from `Recordings/library.plist`, sorted by identifier
- [x] 5.3 Read m4a recording files as Data for base64 encoding, supporting multiple recording segments

## 6. Handwriting Index

- [x] 6.1 Implement handwriting index parsing from `HandwritingIndex/index.plist`
- [x] 6.2 Handle absent index gracefully (disable search without error)

## 7. HTML Player — Continuous Scroll Viewing and Controls

- [x] 7.1 Create `PlayerTemplate.swift` using Canvas 2D for stroke rendering with quadratic smoothing (`quadraticCurveTo`)
- [x] 7.2 Implement continuous scroll viewing (not paginated) — single tall canvas, white background, fit-to-width scaling, auto page counter update
- [x] 7.3 Implement synchronized stroke playback via linear stroke-audio synchronization (not timeline-based) — curve order = writing order, visibleCurveCount proportional to audio progress
- [x] 7.4 Implement playback controls: play/pause toggle, progress bar with seek, speed selection (0.5x/1x/1.5x/2x), time display with h:mm:ss format
- [x] 7.5 Implement zoom and pan with macOS trackpad conventions: two-finger scroll = pan, pinch = zoom (ctrlKey), mouse drag = pan, touch pinch (macOS trackpad gesture mapping)
- [x] 7.6 Implement PDF export via window.print() — render each page to separate canvas in hidden print container with `@media print` CSS
- [x] 7.7 Implement page jump navigation (◀ ▶ buttons) and fullscreen toggle
- [x] 7.8 Implement handwriting text search UI — search input with stroke highlighting
- [x] 7.9 Implement multiple recording segments as continuous timeline using `<audio>` elements with playlist controller
- [x] 7.10 Implement static rendering without audio — display all strokes with scroll/zoom/pan, no audio controls
- [x] 7.11 Implement CSS theme support: `--css dark` and `--css light` themes

## 8. Converter Orchestrator

- [x] 8.1 Implement `NoteConverter` producing self-contained HTML output — orchestrate parse → decode → JSON → template, pack binary float arrays into JSON at build time
- [x] 8.2 Base64-encode all resources (audio, images) and embed as data URIs with correct positions
- [x] 8.3 Support `--full` (complete HTML document) and fragment output modes for self-contained HTML output
- [x] 8.4 Support `--output` file path and `--stdout` output following existing conventions

## 9. Integration and Documentation

- [x] 9.1 Update `CONVERSIONS.md` with Note → HTML row in the cross matrix
- [x] 9.2 Update `README.md` with `macdoc convert --to html file.note` usage examples
- [ ] 9.3 Add tests: ZIP extraction, plist parsing, stroke decoding, timeline decoding, HTML output structure

## 10. Layer 3 Package Structure Verification

- [x] 10.1 Verify `note-to-html-swift` follows layer 3 package structure conventions: depends only on `common-converter-swift` + `ZIPFoundation`, no converter-to-converter imports
