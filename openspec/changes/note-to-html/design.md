## Context

macdoc is a native macOS document processing toolkit with 16 conversion routes following a layered architecture: Layer 1 (format parsers) → Layer 2 (converter protocol) → Layer 3 (converters) → Layer 4 (CLI/MCP consumers). The `.note` format from Notability is a ZIP bundle containing GLKeyedArchiver plists with binary-packed stroke data, m4a audio recordings, and PNG images. The existing `srt-to-html` converter provides a precedent for producing self-contained HTML with embedded media.

## Goals / Non-Goals

**Goals:**

- Parse all player-relevant data from `.note` ZIP bundles using native macOS APIs
- Produce a single self-contained HTML file with no external dependencies
- Continuous scroll viewing with synchronized audio-stroke playback
- macOS-native trackpad interactions (two-finger pan, pinch zoom)
- PDF export for offline sharing
- Follow existing macdoc conventions (streaming output, `--full`, `--css`, error messages in 繁體中文)

**Non-Goals:**

- Editing or modifying `.note` files (read-only conversion)
- Supporting `.note` files from apps other than Notability
- Server-side rendering or backend API
- Apple Pencil pressure-sensitive rendering fidelity (uniform stroke width per curve is acceptable)
- Exact per-page boundary detection (continuous scroll eliminates this need)

## Decisions

### Use PropertyListSerialization with CFKeyedArchiverUID parsing

Notability uses GLKeyedArchiver format. UIDs are stored as `__NSCFType` (`CFKeyedArchiverUID`) which cannot be cast to Int or NSNumber. Parse the integer value from the description string: `<CFKeyedArchiverUID ...>{value = N}`.

The `$top` key in GLKeyedArchiver is `$0` (not `root` as in NSKeyedArchiver). Values like `documentOrigin` and `unscaledContentSize` are UIDs pointing to string objects in `$objects` (e.g., `"{276.7, 331.9}"`), requiring an extra dereference step.

Alternative: `NSKeyedUnarchiver` with `NSSecureCoding` — rejected because Notability's custom classes (`SessionInfo`, `NBCPEventManager`, `GLModel.PaperAttributes`) are not available outside the app.

### Navigate Handwriting Overlay → SpatialHash for stroke data

Stroke data is NOT directly in the `Handwriting Overlay` object. The path is: `richText` → `Handwriting Overlay` → `SpatialHash` → `curvespoints`/`curvescolors`/etc. The `SpatialHash` object contains all binary stroke buffers and `curveUUIDs`.

### Pack binary float arrays into JSON at build time

The stroke data is stored as raw `Float32`/`UInt32` byte buffers. The Swift converter decodes these into typed arrays and serializes as JSON embedded in the HTML. Binary layout: `curvespoints` = Float32 x,y interleaved (666KB for 83K points), `curvescolors` = UInt32 RGBA per curve, `curveswidth` = Float32 per curve, `curvesnumpoints` = UInt32 per curve, `curvesstyles` = UInt8 per curve.

Alternative: Embed raw binary as base64 and decode in JS — rejected for debuggability.

### Canvas 2D for stroke rendering with quadratic smoothing

Use HTML5 Canvas 2D with `quadraticCurveTo()` for smooth stroke rendering. Adjacent points are connected via quadratic bezier with the control point at the midpoint of each pair. This produces smoother curves than raw `lineTo()`.

Alternative: SVG paths — rejected for performance with 3924 curves.

### Linear stroke-audio synchronization (not timeline-based)

The `NBCPEventManager` timeline was initially used for stroke-audio sync, but analysis revealed that timeline events don't map chronologically to spatial position — the same timestamp can reference strokes at y=59 (page 1) and y=3384 (page 5). The `SpatialHash` curve order IS the chronological writing order (Y coordinates monotonically increase: 153→6382 across 3924 curves).

Implementation: `visibleCurveCount = floor(audioProgress * totalCurves)`. Curves 0..N are shown, where N is proportional to audio playback position.

Alternative: UUID-based timeline mapping (`curveUUIDs` ↔ `SOAEventUUIDsKey`) — implemented and verified working (3913/3918 events mapped), but produced non-intuitive playback order because Notability's timeline tracks modification timestamps, not sequential writing order.

### Continuous scroll viewing (not paginated)

The note is rendered as a single tall canvas with all 9 pages' content in one continuous vertical strip. Pages are separated visually by white background against the container's off-white background. Scrolling uses two-finger trackpad gestures (natural macOS behavior). Page counter auto-updates based on scroll position.

Alternative: Per-page view with page thumbnails — rejected because it conflicted with natural scrolling expectations and required complex page boundary detection. Notability's coordinate system has non-uniform page gaps (50-425pt), making exact per-page clipping unreliable.

### macOS trackpad gesture mapping

Two-finger scroll → pan (via `wheel` event `deltaX`/`deltaY`). Pinch-to-zoom → zoom (via `wheel` event with `ctrlKey` flag, which browsers set for pinch gestures). Mouse drag → pan.

Alternative: Scroll = zoom (common in drawing tools) — rejected because it violates macOS trackpad conventions.

### PDF export via window.print()

Each page is rendered to a separate canvas at 2x resolution, placed in a hidden `#print-container` div with `@media print` CSS (`page-break-after: always`). Clicking the 📥 button triggers `window.print()`, which opens the browser's "Save as PDF" dialog.

Alternative: Client-side PDF library (jsPDF) — rejected to maintain zero external dependencies.

### Image positioning via UID-dereferenced mediaObjects

Image positions (`documentOrigin`, `unscaledContentSize`) are stored as UIDs pointing to string values like `"{276.7, 331.9}"` in the `$objects` array. The parser dereferences UIDs before parsing the point/size strings.

### Layer 3 package structure

`packages/note-to-html-swift/` follows established pattern:
- `NoteParser.swift` — ZIP extraction + plist navigation + `PlistNavigator` (UID resolver)
- `StrokeDecoder.swift` — binary float/uint buffers → `StrokeData` (curves, bounds, curveUUIDs)
- `TimelineDecoder.swift` — `NBCPEventManager` → timeline events with UUID→curve mapping
- `NoteConverter.swift` — orchestrator implementing `DocumentConverter`, JSON serialization
- `PlayerTemplate.swift` — HTML/JS/CSS template as Swift string builders

## Risks / Trade-offs

- [Risk] Notability may change its internal plist format → Mitigation: Version detection via `sessionFormatVersion` (currently 9); fail gracefully with 繁體中文 error messages
- [Risk] Large note files with many recordings produce HTML > 50MB → Mitigation: Tested with 42MB output (4 recordings, 2+ hours); acceptable for self-contained distribution
- [Risk] `GLKeyedArchiver` UID format may change → Mitigation: `PlistNavigator.uidValue()` tries multiple parsing strategies (direct Int, CF$UID dict, description string)
- [Risk] Page boundary detection is unreliable → Mitigation: Continuous scroll eliminates the need for exact page boundaries; PDF export uses uniform `pageHeight` from paper dimensions
- [Trade-off] Linear stroke-audio sync is approximate → Accepted because true timeline mapping produces non-intuitive visual order; linear mapping matches top-to-bottom writing flow
- [Trade-off] JSON stroke data ~2x larger than binary → Accepted; typical 42MB HTML is dominated by audio (31MB), not stroke JSON (~5MB)
