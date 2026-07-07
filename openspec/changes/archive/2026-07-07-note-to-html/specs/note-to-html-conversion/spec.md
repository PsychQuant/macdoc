## ADDED Requirements

### Requirement: Self-contained HTML output

The system SHALL produce a single HTML file containing all resources (audio as base64 data URIs, images as base64 data URIs, stroke data as embedded JSON, CSS and JS inline). The output file SHALL have no external dependencies.

#### Scenario: Full document output

- **WHEN** the user runs `macdoc convert --to html file.note --full`
- **THEN** the output SHALL be a complete HTML document (DOCTYPE, head with embedded CSS, body with embedded JS and data)

#### Scenario: Fragment output

- **WHEN** the user runs `macdoc convert --to html file.note` without `--full`
- **THEN** the output SHALL be an HTML fragment containing the player markup, inline styles, and inline script

#### Scenario: Output to file

- **WHEN** `--output path` is specified
- **THEN** the system SHALL write the HTML to the specified path and report `已寫入: <path>` to stderr

#### Scenario: Output to stdout

- **WHEN** no `--output` is specified or `--stdout` is used
- **THEN** the system SHALL write the HTML to stdout

### Requirement: Continuous scroll viewing

The system SHALL render all pages as a single continuous vertical canvas. The note content SHALL be displayed as one tall document with a white background, scrollable via standard trackpad/mouse gestures.

#### Scenario: Vertical scrolling

- **WHEN** the user performs a two-finger scroll gesture on a Mac trackpad
- **THEN** the canvas pans vertically through all pages continuously without page boundaries blocking content

#### Scenario: Page counter auto-update

- **WHEN** the user scrolls to a different region of the note
- **THEN** the page indicator in the toolbar SHALL update to reflect the approximate current page based on scroll position

#### Scenario: Page jump navigation

- **WHEN** the user clicks the ◀ or ▶ page navigation buttons
- **THEN** the canvas SHALL scroll to the beginning of the previous or next page

### Requirement: Synchronized stroke playback

The system SHALL render handwritten strokes progressively as the audio plays. Synchronization SHALL use linear mapping: stroke progress = audio progress, based on the SpatialHash curve order (which matches top-to-bottom writing order).

#### Scenario: Play from beginning

- **WHEN** the user clicks the play button
- **THEN** audio begins playing and strokes appear on the canvas sequentially from curve 0 to curve N, proportional to audio playback position

#### Scenario: Seek via progress bar

- **WHEN** the user clicks on the progress bar at a specific position
- **THEN** the audio seeks to that position and the canvas immediately displays all strokes up to the corresponding curve index

#### Scenario: Click on stroke to seek

- **WHEN** the user clicks on a visible stroke on the canvas
- **THEN** the audio seeks to the time position corresponding to that stroke's sequential position (curveIndex / totalCurves * totalDuration)

#### Scenario: All strokes visible by default

- **WHEN** the player loads and audio is NOT playing
- **THEN** all strokes SHALL be visible (visibleCurveCount = totalCurves)

### Requirement: Playback controls

The system SHALL provide audio playback controls including play/pause toggle, progress bar with seek, playback speed selection, and fullscreen toggle.

#### Scenario: Speed adjustment

- **WHEN** the user selects a playback speed (0.5x, 1x, 1.5x, 2x)
- **THEN** the audio playback rate changes and stroke animation speed adjusts proportionally

#### Scenario: Pause and resume

- **WHEN** the user pauses playback and then resumes
- **THEN** both audio and stroke animation resume from the paused position

#### Scenario: Fullscreen

- **WHEN** the user clicks the fullscreen button
- **THEN** the player enters fullscreen mode

#### Scenario: Time display

- **WHEN** total duration exceeds 1 hour
- **THEN** time SHALL be displayed as `h:mm:ss` format (e.g., `2:14:19`), otherwise `m:ss`

### Requirement: Zoom and pan with macOS trackpad conventions

The system SHALL support zooming and panning following native macOS trackpad behavior.

#### Scenario: Two-finger scroll to pan

- **WHEN** the user performs a two-finger scroll gesture (no modifier key)
- **THEN** the canvas viewport SHALL pan in the scroll direction (deltaX, deltaY)

#### Scenario: Pinch to zoom

- **WHEN** the user performs a pinch gesture (detected via wheel event with ctrlKey)
- **THEN** the canvas SHALL zoom in or out centered on the cursor position

#### Scenario: Mouse drag to pan

- **WHEN** the user clicks and drags on the canvas
- **THEN** the canvas viewport SHALL pan in the drag direction

#### Scenario: Touch pinch on mobile

- **WHEN** the user performs a two-finger pinch on a touch device
- **THEN** the canvas SHALL zoom centered on the pinch midpoint

### Requirement: PDF export

The system SHALL provide a PDF export button that renders each page to a separate canvas and triggers the browser's print dialog for "Save as PDF" functionality.

#### Scenario: Export to PDF

- **WHEN** the user clicks the 📥 (download) button
- **THEN** the system renders each page to a separate high-resolution canvas in a hidden print container, applies `@media print` CSS with `page-break-after: always`, and calls `window.print()`

### Requirement: Handwriting text search

The system SHALL provide a search input that highlights strokes matching recognized handwriting text from the HandwritingIndex.

#### Scenario: Search match found

- **WHEN** the user types a search query that matches text in the handwriting index
- **THEN** the matching strokes are visually highlighted on the canvas

#### Scenario: Search unavailable

- **WHEN** the note file has no HandwritingIndex
- **THEN** the search input SHALL be hidden

### Requirement: CSS theme support

The system SHALL support `--css dark` and `--css light` theme options.

#### Scenario: Dark theme

- **WHEN** `--css dark` is specified
- **THEN** the player uses a dark background with light-colored controls

#### Scenario: Light theme

- **WHEN** `--css light` is specified or no `--css` is given
- **THEN** the player uses a light background matching the original Notability paper appearance

### Requirement: Static rendering without audio

The system SHALL render all strokes statically when the note file contains no recordings.

#### Scenario: No recordings

- **WHEN** the `.note` file has no `Recordings/` directory or no m4a files
- **THEN** the output HTML SHALL display all strokes fully rendered without audio controls, functioning as a static handwriting viewer with scroll, zoom/pan, and PDF export

### Requirement: Multiple recording segments

The system SHALL handle notes with multiple sequential recording segments, presenting them as a continuous timeline.

#### Scenario: Multi-segment playback

- **WHEN** the note contains multiple recording files with distinct durations
- **THEN** the player presents a single continuous progress bar spanning the total duration, automatically transitioning between `<audio>` element sources at segment boundaries
