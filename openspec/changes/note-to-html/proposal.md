## Why

Notability `.note` files are ZIP bundles containing handwritten strokes (bezier curves with timestamps), audio recordings (m4a), embedded images, and handwriting recognition indices. There is no cross-platform way to replay these notes with synchronized audio-stroke playback outside the Notability app. Converting `.note` to a self-contained HTML file enables personal review, LMS embedding, and portfolio showcase — all without requiring Notability installed.

## What Changes

- Add a new conversion route: `.note` → `.html` via `macdoc convert --to html file.note --full`
- Parse Notability's proprietary plist structures: `Session.plist` (stroke data via `Handwriting Overlay → SpatialHash`, `NBCPEventManager` timeline), `Recordings/library.plist` (audio metadata), `HandwritingIndex/index.plist` (text search index)
- Decode GLKeyedArchiver `$objects` array navigation with `CFKeyedArchiverUID` parsing (description string extraction)
- Decode binary stroke buffers: `curvespoints` (Float32 x,y interleaved), `curvescolors` (UInt32 RGBA), `curveswidth` (Float32), `curvesnumpoints` (UInt32), `curvesstyles` (UInt8), `curveUUIDs` (16-byte UUIDs)
- Extract paper dimensions from `NBNoteTakingSessionDocumentPaperLayoutModelKey` → `documentPaperAttributes` → `paperSizingBehavior` (e.g., `lockedWidth:583.8:iPad`)
- Extract image positions via UID-referenced `documentOrigin` and `unscaledContentSize` strings in `mediaObjects`
- Generate a self-contained HTML file with all resources base64-encoded (audio, images, stroke data as JSON)
- Embed a Vanilla JS + Canvas 2D player supporting: continuous scroll, play/pause, seek, speed control (0.5x–2x), linear stroke-audio synchronization, click-to-seek on strokes, page jump navigation, macOS trackpad gestures (two-finger scroll = pan, pinch = zoom), fullscreen, PDF export, and handwriting text search
- Support `--css dark|light` themes consistent with existing SRT converter conventions

## Capabilities

### New Capabilities

- `note-parsing`: Parse Notability `.note` ZIP bundles — extract and decode `Session.plist` stroke data from `Handwriting Overlay → SpatialHash` (curvespoints, curvescolors, curveswidth, curvesnumpoints, curveUUIDs), recording metadata from `Recordings/library.plist`, image data with positions from `mediaObjects` (UID-dereferenced origin/size strings), paper dimensions from `documentPaperAttributes`, and handwriting indices
- `note-to-html-conversion`: Convert parsed Notability data into a self-contained HTML file with an embedded interactive player — Canvas 2D stroke rendering, continuous vertical scroll, `<audio>` element playback with multi-segment playlist, linear stroke-audio synchronization (curve order = writing order), macOS trackpad gestures, PDF export via `window.print()`, and dark/light themes

### Modified Capabilities

(none)

## Impact

- New Layer 3 package: `packages/note-to-html-swift/`
- New route in `Sources/MacDocCLI/MacDoc+Convert.swift`: `case ("note", "html")`
- Dependencies: `ZIPFoundation` (already available), `Foundation` `PropertyListSerialization` (system built-in)
- `CONVERSIONS.md`: add Note → HTML row
- `Package.swift`: add `note-to-html-swift` dependency
- GitHub Issue: #64
