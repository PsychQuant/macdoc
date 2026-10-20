## Purpose

Threshold-free pixel verification for any PDF produced from another PDF: both documents are rendered by the same renderer, compared pixel by pixel and channel by channel, and every differing pixel must be explained. It exists because ratio thresholds and visual inspection hide one- or two-pixel defects such as typed text touching a printed line.

## ADDED Requirements

### Requirement: Deterministic page rasterization

The verification library SHALL render a PDF page with CoreGraphics into an 8-bit sRGB RGB buffer on a white background, aligned to the page's top-left corner, at a caller-chosen resolution in dots per inch (default 144). Rendering the same page of the same file twice SHALL produce byte-identical buffers.

#### Scenario: Same page renders identically twice

- **WHEN** page 1 of a PDF is rendered twice at 144 dpi
- **THEN** both buffers have the same width, height and bytes

#### Scenario: Buffer size follows page size and resolution

- **WHEN** a 595.2756×841.8898 bp page is rendered at 144 dpi
- **THEN** the buffer is 1191 pixels wide and 1684 pixels tall

### Requirement: Signed RGB difference without thresholds

The library SHALL compute D = output − original for every pixel and every RGB channel as a signed integer in the range −255 to 255, with both renders aligned at the top-left corner and compared over their common width and height. It SHALL NOT apply thresholds, binarization, dilation, erosion or any other noise filter to D. It SHALL report the number of pixels with any non-zero channel and the minimum and maximum of D per channel.

#### Scenario: Identical documents give an all-zero difference

- **WHEN** a PDF is compared with a byte-identical copy of itself
- **THEN** the changed-pixel count is 0 and every channel's minimum and maximum of D are 0

#### Scenario: Black text on white darkens all channels

- **GIVEN** an original blank page and an output with one black glyph added
- **WHEN** the difference is computed
- **THEN** every changed pixel has D ≤ 0 in all three channels and the maximum of D is 0 in every channel

### Requirement: Four overlay checks

Given an original PDF page, an output page, and the overlay rendered alone on a white page of the same size, the library SHALL evaluate four checks and report a pixel count for each: (1) difference outside the overlay — pixels whose overlay render is pure white in all channels but whose D is non-zero in any channel; (2) original made lighter — pixels with D > 0 in any channel; (3) overlay ink on original ink — pixels where both the overlay render and the original render are non-white; (4) ink in a cropped strip — non-white pixels of the original that fall outside the output's common region. Verification SHALL pass only when all four counts are 0. For every failing check the report SHALL list the affected horizontal bands as top, bottom, left and right in bp with a pixel count.

#### Scenario: Clean overlay on a near-A4 form

- **GIVEN** a synthetic 596×843 bp blank form with a 1 bp line from (100,100) to (300,100) bp and the glyph 甲 at (150,300) bp
- **WHEN** an overlay placing 42 at (123,310) bp is stamped with A4 normalization and verified
- **THEN** all four check counts are 0 and verification passes

##### Example: collision is located

- **GIVEN** the same form
- **WHEN** the overlay places 42 on the same baseline as 甲, at (148,300) bp, so that it overlaps 甲
- **THEN** the overlay-on-ink count is greater than 0 and the reported band lies inside the bounding box of 甲

#### Scenario: Overlap is detected where D is near zero

- **GIVEN** overlay ink drawn exactly on top of existing black ink
- **WHEN** the checks run
- **THEN** the overlay-on-ink check is non-zero even though D at those pixels is 0

### Requirement: Preserved regions

The library SHALL accept a list of preserved rectangles in bp with a top-left origin and SHALL require D to be 0 in all channels for every pixel inside each rectangle. A failure SHALL name the rectangle index and the number of differing pixels inside it.

#### Scenario: One changed pixel inside a preserved region fails

- **GIVEN** a preserved rectangle (50,50)–(150,150) bp
- **WHEN** the output differs from the original by a mark at (100,100) bp
- **THEN** the preserved-region check fails for rectangle 0 with a non-zero pixel count

### Requirement: Exact A4 page geometry

The library SHALL define A4 as 210×297 mm, that is 595.2756×841.8898 bp, and SHALL NOT use the rounded 595×842 size. A page SHALL count as near A4 when both its width and height are within 1.5 bp of A4. Normalizing a near-A4 page to A4 SHALL keep the page's top-left corner fixed and change only the page box, without scaling or redrawing the content. Normalization SHALL fail with an error that names the pixel count when the original has non-white pixels in the strip that would be removed.

#### Scenario: Near-A4 page normalizes without moving content

- **GIVEN** a 596×843 bp page
- **WHEN** it is normalized to A4 and rendered at 144 dpi
- **THEN** the result is 595.2756×841.8898 bp and its render equals the original's render over the common region pixel for pixel

#### Scenario: Ink in the removed strip refuses normalization

- **GIVEN** a 596×843 bp page with a line drawn at y = 841.95 bp
- **WHEN** A4 normalization is requested
- **THEN** normalization fails and reports the number of inked pixels in the removed strip

### Requirement: Diff artifacts

On request the library SHALL write four artifacts to a caller-chosen directory: diff_signed.png with each channel equal to 128 + D/2 clamped to 0–255; diff_abs.png with each channel equal to 255 − |D|; diff.bin holding D as little-endian signed 16-bit integers in row-major height × width × 3 order; and report.json with the dimensions, resolution, changed-pixel count, per-channel extremes and the result of every check that ran.

#### Scenario: Raw difference round-trips

- **WHEN** diff.bin is read back using the dimensions in report.json
- **THEN** the values equal the in-memory D

### Requirement: macdoc pdf visual-diff subcommand

macdoc SHALL provide `macdoc pdf visual-diff` taking `--original`, `--output`, an optional `--overlay` (the overlay rendered alone), zero or more `--preserve x0,y0,x1,y1` rectangles in bp, `--dpi` (default 144) and an optional `--diff-dir`. It SHALL print the changed-pixel count, per-channel extremes and the result of each applicable check, write the diff artifacts when `--diff-dir` is given, and exit with status 0 only when every applicable check passes. The applicable checks are the four overlay checks when `--overlay` is given, the preserved-region check when `--preserve` is given, and, when neither is given, an identity check that requires the changed-pixel count to be 0.

#### Scenario: Identical documents pass the identity check

- **WHEN** `macdoc pdf visual-diff` runs on two byte-identical PDFs without `--overlay` or `--preserve`
- **THEN** it prints a changed-pixel count of 0 and exits with status 0

#### Scenario: Failing check sets a non-zero exit status

- **WHEN** `macdoc pdf visual-diff` runs with an overlay whose ink touches the original's ink
- **THEN** the overlay-on-ink line reports a non-zero count with its bands and the process exits with a non-zero status

### Requirement: Page geometry in macdoc pdf compare

`macdoc pdf compare` SHALL report, in addition to its existing text comparison, the page size in bp of every page of both documents grouped by size, whether each size is exact A4, near A4 or other, and the indices of pages whose sizes differ between the original and the reproduced document. The existing text-layer report SHALL remain unchanged.

#### Scenario: Size mismatch is listed

- **GIVEN** an original whose pages are 596×843 bp and a reproduction whose page 3 is 612×792 bp
- **WHEN** `macdoc pdf compare` runs
- **THEN** the geometry section lists page 3 as differing and classifies 612×792 as other
