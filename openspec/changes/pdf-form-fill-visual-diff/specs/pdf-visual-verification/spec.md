## Purpose

Threshold-free pixel verification for any PDF produced from another PDF: both documents are rendered by the same renderer, compared pixel by pixel and channel by channel, and every differing pixel must be explained. It exists because ratio thresholds and visual inspection hide one- or two-pixel defects such as typed text touching a printed line.

## ADDED Requirements

### Requirement: Deterministic page rasterization

The verification library SHALL render a PDF page with CoreGraphics into an 8-bit sRGB RGB buffer on a white background, aligned to the page's top-left corner, at a caller-chosen resolution in dots per inch (default 144). Rendering the same page of the same file twice SHALL produce byte-identical buffers. The library SHALL refuse with an error, instead of crashing, a resolution that is not a finite number above 0 and at most 2400 dpi, a bitmap larger than 100 million pixels, and a page with a non-zero rotation.

#### Scenario: Same page renders identically twice

- **WHEN** page 1 of a PDF is rendered twice at 144 dpi
- **THEN** both buffers have the same width, height and bytes

#### Scenario: Buffer size follows page size and resolution

- **WHEN** a 595.2756×841.8898 bp page is rendered at 144 dpi
- **THEN** the buffer is 1191 pixels wide and 1684 pixels tall

#### Scenario: Out-of-range resolution is refused

- **WHEN** a page is rendered at 2401 dpi, at an infinite resolution or at 0 dpi
- **THEN** the call fails with an invalid-resolution error and the process keeps running

### Requirement: Signed RGB difference without thresholds

The library SHALL compute D = output − original for every pixel and every RGB channel as a signed integer in the range −255 to 255, with both renders aligned at the top-left corner and compared over their common width and height. It SHALL NOT apply thresholds, binarization, dilation, erosion or any other noise filter to D. It SHALL report the number of pixels with any non-zero channel, the true minimum and maximum of D per channel over every compared pixel, and whether the two pages have the same size in bp and the two renders the same width and height.

#### Scenario: Identical documents give an all-zero difference

- **WHEN** a PDF is compared with a byte-identical copy of itself
- **THEN** the changed-pixel count is 0, every channel's minimum and maximum of D are 0, and the sizes match

#### Scenario: Black text on white darkens all channels

- **GIVEN** an original blank page and an output with one black glyph added
- **WHEN** the difference is computed
- **THEN** every changed pixel has D ≤ 0 in all three channels and the maximum of D is 0 in every channel

#### Scenario: A sub-pixel size difference is a size mismatch

- **GIVEN** an A4 page of 595.2756×841.8898 bp and a page of 595.28×841.89 bp, both blank
- **WHEN** they are rendered at 72 dpi and compared
- **THEN** both renders have the same width and height, and the sizes are reported as not matching

#### Scenario: Extremes are not clamped at zero

- **GIVEN** an original white 100×100 bp page and an output of the same size filled black
- **WHEN** the difference is computed at 72 dpi
- **THEN** the minimum and the maximum of D are −255 in every channel

### Requirement: Five overlay checks

Given an original PDF page, an output page, and the overlay rendered alone on a white page, the library SHALL evaluate five checks and report a pixel count for each: (1) difference outside the overlay — pixels of the output whose overlay render is pure white in all channels but which differ from the original (D non-zero in the common region, any non-white output pixel where the output is larger than the original); (2) original made lighter — pixels with D > 0 in any channel; (3) overlay ink on original ink — pixels where both the overlay render and the original render are non-white; (4) ink in a cropped strip — non-white pixels of the original that fall outside the output's common region; (5) overlay missing from the output — pixels where the overlay render is non-white and that lie outside the output, or where the original is white or absent and the output pixel is not exactly the overlay render's pixel (typed text that did not arrive, or arrived faint or recoloured). Verification SHALL pass only when all five counts are 0. For every failing check the report SHALL list the affected horizontal bands as top, bottom, left and right in bp with a pixel count.

#### Scenario: Clean overlay on a near-A4 form

- **GIVEN** a synthetic 596×843 bp blank form with a 1 bp line from (100,100) to (300,100) bp and the glyph 甲 at (150,300) bp
- **WHEN** an overlay placing 42 at (123,310) bp is stamped with A4 normalization and verified
- **THEN** all five check counts are 0 and verification passes

##### Example: collision is located

- **GIVEN** the same form
- **WHEN** the overlay places 42 on the same baseline as 甲, at (148,300) bp, so that it overlaps 甲
- **THEN** the overlay-on-ink count is greater than 0 and the reported band lies inside the bounding box of 甲

#### Scenario: Overlap is detected where D is near zero

- **GIVEN** overlay ink drawn exactly on top of existing black ink
- **WHEN** the checks run
- **THEN** the overlay-on-ink check is non-zero even though D at those pixels is 0

#### Scenario: Typed text missing from the output is detected

- **GIVEN** the same form, an overlay placing 42 at (123,310) bp, and an output that is the unfilled form at A4
- **WHEN** the checks run
- **THEN** the overlay-missing count is greater than 0 and verification fails

#### Scenario: A faint stamp is detected

- **GIVEN** a blank A4 original, an overlay with black 42 at (123,310) bp and an output with the same 42 in grey
- **WHEN** the checks run
- **THEN** the overlay-missing count is greater than 0 and verification fails

#### Scenario: Ink beyond the original's size is not ignored

- **GIVEN** an A4 original, an empty A4 overlay and a 600×850 bp output with a 2×2 bp mark at (597,100) bp
- **WHEN** the checks run at 144 dpi
- **THEN** the difference-outside-overlay count is 16

### Requirement: Preserved regions

The library SHALL accept a list of preserved rectangles in bp with a top-left origin and SHALL require D to be 0 in all channels for every pixel inside each rectangle, and every such pixel to lie inside the compared area. A rectangle with a non-finite coordinate or no area SHALL be refused with an error naming its index. For each rectangle the result SHALL give the index, the number of differing pixels and the number of pixels outside the compared area; it SHALL pass only when both are 0.

#### Scenario: One changed pixel inside a preserved region fails

- **GIVEN** a preserved rectangle (50,50)–(150,150) bp
- **WHEN** the output differs from the original by a mark at (100,100) bp
- **THEN** the preserved-region check fails for rectangle 0 with a non-zero pixel count

#### Scenario: A region far off the page cannot pass

- **GIVEN** an A4 page compared with itself and a preserved rectangle 10 bp square at x = 1 000 000 000 bp
- **WHEN** the check runs at 144 dpi
- **THEN** rectangle 0 has 400 pixels outside the compared area and fails

#### Scenario: A region beyond the page cannot pass

- **GIVEN** an A4 page compared with itself and a preserved rectangle (590,830)–(690,930) bp
- **WHEN** the check runs at 144 dpi
- **THEN** rectangle 0 has 0 differing pixels, 39736 pixels outside the compared area, and fails

### Requirement: Exact A4 page geometry

The library SHALL define A4 as 210×297 mm, that is 595.2756×841.8898 bp, and SHALL NOT use the rounded 595×842 size. A page SHALL count as near A4 when both its width and height are within 1.5 bp of A4. The library SHALL count the inked pixels of the strip that a top-left crop to a target size would remove, drawing both strips as one clip so that every pixel, including the shared corner and pixels the cut passes through, is counted once. It SHALL also count the inked pixels drawn outside a page's crop box, up to one page width or height beyond each edge, which every render clips away; the count SHALL include ink just past an edge and exclude ink on the page, and SHALL lower its resolution rather than fail when the area would exceed the bitmap limit. Normalizing a near-A4 page to A4 (part of stamping in the pdf-form-fill capability) SHALL keep the page's top-left corner fixed and translate the page content without scaling it and without rasterizing it, and SHALL fail with an error that names the pixel count when the original has non-white pixels in the strip that would be removed.

#### Scenario: Near-A4 page normalizes without moving content

- **GIVEN** a 596×843 bp page
- **WHEN** it is normalized to A4 and rendered at 144 dpi
- **THEN** the result is 595.2756×841.8898 bp and its render equals the original's render over the common region pixel for pixel

#### Scenario: Ink in the removed strip refuses normalization

- **GIVEN** a 596×843 bp page with a line drawn at y = 841.95 bp
- **WHEN** A4 normalization is requested
- **THEN** normalization fails and reports the number of inked pixels in the removed strip

#### Scenario: A pixel the cut passes through is counted once

- **GIVEN** a 597×843 bp page with a 1×0.5 bp mark at (595.0,842.5) bp, across the right-strip cut at 595.28 bp
- **WHEN** the removed-strip ink is counted against A4 at 144 dpi
- **THEN** the count is 2

#### Scenario: Ink past the crop box is found

- **WHEN** a page has text starting at x = 580 bp that runs past its right edge
- **THEN** the count of ink outside the crop box is greater than 0, and it is 0 for the same text at x = 100 bp

#### Scenario: The shared corner is counted once

- **GIVEN** a 597×843 bp page with a 1×0.5 bp mark at (595.5,842.0) bp, inside both removed strips
- **WHEN** the removed-strip ink is counted against A4 at 144 dpi
- **THEN** the count is 2

### Requirement: Diff artifacts

On request the library SHALL write four artifacts to a caller-chosen directory: diff_signed.png with each channel equal to 128 + D/2 clamped to 0–255; diff_abs.png with each channel equal to 255 − |D|; diff.bin holding D as little-endian signed 16-bit integers in row-major height × width × 3 order; and report.json with the dimensions, resolution, changed-pixel count, per-channel extremes and the result of every check that ran, including the identity check. Each artifact SHALL be written under a temporary name and renamed into place, so that an existing file or symbolic link of the same name is replaced and never written through.

#### Scenario: Raw difference round-trips

- **WHEN** diff.bin is read back using the dimensions in report.json
- **THEN** the values equal the in-memory D

#### Scenario: A symbolic link in the directory is replaced, not followed

- **GIVEN** a diff directory where each artifact name is a symbolic link to another file
- **WHEN** the artifacts are written
- **THEN** the other file is unchanged and each artifact is a regular file

#### Scenario: The identity result is recorded

- **WHEN** artifacts are written after an identity check
- **THEN** report.json records whether the documents were identical

### Requirement: macdoc pdf visual-diff subcommand

macdoc SHALL provide `macdoc pdf visual-diff` taking `--original`, `--reproduced` (the PDF made from the original), an optional `--overlay` (the overlay rendered alone), zero or more `--preserve x0,y0,x1,y1` rectangles in bp with finite coordinates, `--dpi` (default 144) and an optional `--diff-dir`. It SHALL print the changed-pixel count, per-channel extremes and the result of each applicable check, print at most ten bands per check followed by the number of bands not printed, write the diff artifacts when `--diff-dir` is given and report the written directory on stderr, report errors in Traditional Chinese on stderr, and exit with status 0 only when every applicable check passes. The applicable checks are the five overlay checks when `--overlay` is given, the preserved-region check when `--preserve` is given, and, when neither is given, an identity check that requires the two pages to have the same size in bp, to render at the same size, and to have a changed-pixel count of 0; when the sizes differ, both are printed with enough decimals to tell them apart. A `--diff-dir` whose artifacts would replace one of the input PDFs SHALL be refused before anything is written.

#### Scenario: Identical documents pass the identity check

- **WHEN** `macdoc pdf visual-diff` runs on two byte-identical PDFs without `--overlay` or `--preserve`
- **THEN** it prints a changed-pixel count of 0 and exits with status 0

#### Scenario: Different page sizes fail the identity check

- **WHEN** `macdoc pdf visual-diff` runs on a blank 596×843 bp page and a blank A4 page without `--overlay` or `--preserve`
- **THEN** the identity line says the page sizes differ and the process exits with a non-zero status

#### Scenario: Failing check sets a non-zero exit status

- **WHEN** `macdoc pdf visual-diff` runs with an overlay whose ink touches the original's ink
- **THEN** the overlay-on-ink line reports a non-zero count with its bands and the process exits with a non-zero status

#### Scenario: A non-finite rectangle is rejected

- **WHEN** `macdoc pdf visual-diff` runs with `--preserve 0,0,inf,100`
- **THEN** it reports an error naming `--preserve` and exits with a non-zero status

### Requirement: Page geometry in macdoc pdf compare

`macdoc pdf compare` SHALL report, in addition to its existing text comparison, the page size in bp of every page of both documents as displayed (after the page's rotation), grouped by exact size, whether each size is exact A4, near A4 or other in either orientation, and the indices of pages whose displayed sizes are not identical between the original and the reproduced document, each listed with both of its sizes. All sizes of both documents SHALL be printed with the fewest decimals (2, 4, …, 16) at which different sizes never print alike. The summary SHALL state the page-size verdict (OK, or MISMATCH with the pages), next to the existing paper-class line, which is labelled as a class rather than a size. The existing text-layer report SHALL remain unchanged.

#### Scenario: Size mismatch is listed

- **GIVEN** an original whose pages are 596×843 bp and a reproduction whose page 3 is 612×792 bp
- **WHEN** `macdoc pdf compare` runs
- **THEN** the geometry section lists page 3 as differing and classifies 612×792 as other

#### Scenario: A sub-0.01 bp difference is still listed

- **GIVEN** an original page of 595.2756×841.8898 bp and a reproduced page of 595.28×841.89 bp
- **WHEN** the geometry is compared
- **THEN** page 1 is listed as differing with two different printed sizes, and both sizes are classified as exact A4

#### Scenario: Landscape A4 is A4

- **WHEN** a page of 841.8898×595.2756 bp is compared
- **THEN** its size is classified as exact A4

#### Scenario: Groups never mix classifications

- **GIVEN** pages 596.7752 and 596.7759 bp wide, on either side of the near-A4 limit
- **WHEN** the geometry is compared
- **THEN** they form two groups, classified near A4 and other
