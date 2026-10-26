## Context

A prototype filled PDF forms and was verified by subtracting renders of the result from renders of the original PDF. What drove this design: placing the form under a TeX overlay with pdfpages rescaled it slightly, so lines across the whole page moved; setting the TeX page size equal to the form still left a few edge pixels different because TeX rounds page sizes; stamping the overlay onto an untouched copy gave 0 pixels outside the overlay. Some PDF producers round page sizes to a device grid, so a page meant to be A4 comes out a fraction of a bp off; fitting such a page into A4 by scaling moved the whole page while a top-left 1:1 placement changed nothing. A comparison of binarized or filtered images can hide one-pixel collisions that a threshold-free comparison shows.

macdoc already has `macdoc pdf compare` (text-only, in PsychQuant/pdf-to-latex-swift) and an unrelated ratio-threshold docx visual-diff harness in che-word-mcp. Packages that have a second consumer are split into their own PsychQuant repositories and consumed by URL and version.

## Goals / Non-Goals

**Goals:**

- A reusable verification core whose acceptance rule is "every differing pixel is explained", usable by form filling, pdf compare and later by other PDF generators.
- Form filling that never alters the original form and proves it.
- Exact A4 output for near-A4 forms without moving any content.

**Non-Goals:**

- Automatic detection of table grid lines or field boxes in the skeleton (first version emits label positions only).
- Verifying figure regions of the PDF → LaTeX transcription: figures are raster crops of rendered pages, so their difference is non-zero by construction; tracked in PsychQuant/pdf-to-latex-swift#13.
- A che-pdf-mcp tool (PsychQuant/che-pdf-mcp#6) and migrating the docx harness (PsychQuant/che-word-mcp#295).
- Multi-page forms, rotated pages, and originals with annotations or form fields (refused).
- Fields on shaded cells or scanned forms, where the overlap check cannot pass (follow-up issue).
- A read sandbox for TeX (`openin_any=p` was tested and does not stop an absolute `\input` on the installed TeX Live); the .tex is trusted input.
- Cross-renderer comparison: both sides are always rendered by CoreGraphics.

## Decisions

### Separate public packages consumed by URL dependency

pdf-visual-diff-swift and pdf-form-fill-swift are new public repositories under PsychQuant, consumed by macdoc with `.package(url:_:)` and `.upToNextMinor(from:)`, because a 0.x minor version may break the API. Alternatives: keeping them as in-tree path packages (rejected: three consumers outside the macdoc CLI) or adding them as git submodules (rejected: SwiftPM already pins versions in Package.resolved; a submodule pointer would be a second source of truth). The verification core is a separate package from form filling because pdf-to-latex-swift needs only the core and must not depend on form filling.

### CoreGraphics rasterization as the single renderer

Rendering uses `CGContext` with an sRGB color space, 8 bits per component, premultiplied-last RGBA converted to RGB, filled white, scaled by dpi/72 and translated so the page's top-left corner is at the buffer origin. Buffer size is the ceiling of page size × scale. Alternatives: PDFKit thumbnails (rejected: size and interpolation are not under caller control) or MuPDF (rejected: non-native dependency). Results are only compared within one renderer.

### Signed difference without filtering and overlap from the overlay-only render

D is computed per channel as Int16 with no thresholds or morphology, over the common region of the two rasters; whether the rasters have the same size is reported separately, and an identity check requires both. Overlap cannot be read from D because ink on ink leaves D near 0, so the overlay-on-ink check uses a separate render of the overlay alone and intersects its non-white pixels with the original's non-white pixels. The same overlay render shows typed text that never reached the output: where the original is blank, the output must equal the overlay render exactly, so a missing, faint or recoloured stamp fails. This is the five-check verifier described in the pdf-visual-verification spec.

### Stamping at the PDF object level

The filler writes a new single-page PDF at the object level (`PDFObjectWriter`): the original page's content streams and resources are copied byte for byte (decoded and deflated again; JPEG and JPEG 2000 data kept as it is; numbers written so they read back as the same values), wrapped in q/Q and clipped to the original's crop box, followed by the overlay page as a form XObject whose matrix puts its top-left corner on the page's. In page mode a4 only the page box changes: it keeps the original's top-left corner, so the renderer applies exactly the transform it applies to the original alone. The first design redrew both pages through a CoreGraphics PDF context and accepted it because a synthetic near-A4 form showed 0 differing pixels; verification round 8 showed that the redraw rewrites every coordinate, rounded to about seven significant digits, and that its A4 page box (four decimals) shifts everything by 3.6e-5 bp, so fine lines, curves and circles on ordinary forms (including Word-exported receipts) changed by up to 142 levels and the threshold-free checks failed. The risk listed below fired, and the object-level path replaced the redraw. Annotations are not page content and are not copied, and `drawPDFPage` does not draw their appearances on either side, so the verifier cannot see that loss; originals with any entry in /Annots are therefore refused, as are rotated pages. The output path may not name the original, the overlay or the .tex, including through a symbolic link, and an existing output must be a regular file: `replaceItemAt` on a directory deletes everything in it (found in verification round 2). The overlay must be unrotated, and an overlay with ink outside its page is refused before stamping, because every render clips that ink away. The two checks split the plane: the pixel check sees ink up to one page beyond each edge, and the content-stream scan reports drawing more than 0.9 of a page beyond the crop box. Ink lies within the marks (the convex hull of a path's points, an image's corners, a glyph's em box), so whatever the scan does not report lies where the pixel check sees it. The scan places every glyph from the font's widths (`/Widths` fonts and Identity-H/V CID fonts) and the text state (`Tc`, `Tw`, `Tz`, `Ts`, `Tr`), saved with the graphics state by `q`/`Q` and form XObjects, and marks an em box around each visible glyph; it marks path points only when the path is painted, image corners and shadings, and honours clips and form bounding boxes as bounding rectangles. Bounding the scan by the crop box itself (round 5) refused legitimate overlays, because glyph origins pushed left by kerning or full-width punctuation fall just outside the page while their ink is on it (found in verification round 6); the wider reach leaves those to the pixel check, and in verification round 7 it grew from half a page to 0.9 of a page so that the em box of a large glyph on the page (a full stop at 400 bp) is not refused. Fonts set by an ExtGState through `gs` are followed, and operators whose operands cannot be read are unverifiable. In round 8 a glyph's box became the font's /FontBBox (the em box only when a font gives none), so a full stop at 600 bp is not refused; Type3 fonts became unplaceable, because a Type3 glyph is a content stream that may draw anywhere whatever its /FontBBox says; text that cannot be placed is accepted under a clip within reach; a clip with no path is ignored, as CoreGraphics ignores it; and shadings are placed by their /BBox. The premise that ink lies within the marks holds for paths, images and fonts whose /FontBBox is true to their glyphs, not for every PDF. A character the overlay's fonts lack is refused from the engine's log ("Missing character"), because the engine leaves it out of the PDF and no pixel check can see it. Drawing that cannot be placed is reported separately as unverifiable.

### Exact A4 normalization by top-left translation

A4 is 210/25.4×72 by 297/25.4×72 bp. Near A4 means both dimensions within 1.5 bp. Normalization is a translation that keeps the top-left corner; before normalizing, the original's render is checked for ink in the strip that would be removed (both strips drawn as one clip, so every pixel is counted once), and normalization fails if any is found. The verification core provides the size, the classification and the strip check; the normalization itself is part of stamping.

### Skeleton from PDFKit text runs

The skeleton generator reads page 1 with PDFKit, splits its text into lines, takes each run of non-whitespace characters as a label, and uses the union of its character bounds (converted to bp with a top-left origin) for the position; font sizes come from one attributed string for the page. Each label gets an empty field macro (`\FieldA`, `\FieldB`, …) in the settings section and a commented `\at` line placed just right of the label on its baseline that uses it. The page is A4 for a near-A4 form and the form's own size otherwise, so the overlay always has the output's size. `\atbox` places a field of several lines that wraps within a given width. A blank-form path containing a backslash, a brace, `%`, `#`, `^` or a control character is refused. Alternative: emitting nodes inside detected boxes (rejected for now: requires vector path parsing; Clarity Surface row 3).

### Overlay compilation in a temporary directory

The compiler copies the source into a fresh temporary directory as `overlay.tex`, so the file name never reaches TeX's command line, and runs the engine with `-no-shell-escape -interaction=nonstopmode -halt-on-error` and `-output-directory` set to that directory, twice, with the source file's directory as the working directory so relative paths resolve. A symbolic link to the .tex is followed and its contents are copied. A run that does not finish within the timeout (120 s) is stopped with its whole process tree (frozen, then killed from the leaves up); `discard` removes only a directory recorded when this process created it, and the directory is created with mode 0700. On failure the directory is removed and the end of the log is carried in the error; on success the caller removes it after stamping. The engine defaults to `xelatex` found on PATH; an explicit path is accepted.

### Page geometry layer in the pdf-to-latex-swift comparator

`PDFComparator` gains a geometry section computed with the core's page-geometry classifier: page sizes as displayed (after /Rotate) grouped by exact size, classification (exact A4, near A4, other) and the indices of pages whose sizes are not identical between the two documents. Sizes are classified regardless of orientation, all sizes of both documents print at one precision chosen so that different sizes never look alike, mismatched pages are listed with both sizes, and the summary states the page-size verdict. The existing report fields keep their meaning; the JSON report gains a new optional field. Released as pdf-to-latex-swift 0.6.0, corrected in 0.6.1 to 0.6.3, and in 0.7.0, which also relabels the typography section's paper line; 0.7.1 tests both paper lines and 0.7.2 requires pdf-visual-diff-swift 0.6.0.

### Raw difference artifact format

diff.bin stores D as little-endian Int16 in row-major height × width × 3 order with no header; report.json carries width, height, dpi and the check results so the file can be decoded without guessing. Every artifact is written under a temporary name and renamed into place, so a symbolic link of the same name is replaced, never written through.

### Release order and audit gate

The repositories are created, hardened according to macdoc's SECURITY.md baseline and audited with macdoc's audit script before their first tag. Order: pdf-visual-diff-swift 0.1.0, then pdf-form-fill-swift 0.1.0 and pdf-to-latex-swift 0.6.0, then macdoc switches its dependencies and regenerates Package.resolved. Verification round 1 fixes ship as pdf-visual-diff-swift 0.2.0, pdf-form-fill-swift 0.2.0 and pdf-to-latex-swift 0.6.1; round 2 fixes as pdf-visual-diff-swift 0.3.0, pdf-form-fill-swift 0.3.0 and pdf-to-latex-swift 0.6.2; round 3 as 0.4.0, 0.4.0 and 0.6.3; round 4 as pdf-visual-diff-swift 0.5.0, pdf-form-fill-swift 0.5.0/0.5.1 and pdf-to-latex-swift 0.7.0; round 5 as pdf-visual-diff-swift 0.6.0, pdf-form-fill-swift 0.6.0 and pdf-to-latex-swift 0.7.1/0.7.2; round 6 as pdf-form-fill-swift 0.7.0; round 7 as pdf-visual-diff-swift 0.6.1 and pdf-form-fill-swift 0.7.1; round 8 as pdf-visual-diff-swift 0.6.2 and pdf-form-fill-swift 0.8.0 (object-level stamping). Dependencies on these 0.x packages use `.upToNextMinor(from:)`, because a 0.x minor version may break the API.

## Implementation Contract

**pdf-visual-diff-swift (library product PDFVisualDiff):**

- `PageRaster.render(page:dpi:)` and `PageRaster.render(url:pageIndex:dpi:)` return width, height, dpi and RGB bytes; deterministic; resolutions above `PageRaster.maxDPI` (2400) and bitmaps above `PageRaster.maxPixelCount` (100 million) are refused; `PageRaster(width:height:dpi:pageSize:pixels:) throws` refuses an empty or inconsistent buffer, a resolution outside 1–2400 dpi and a page size that is not positive and finite.
- `SignedDiff(original:output:)` exposes width, height, Int16 values, changed-pixel count, per-channel true minimum and maximum, `sizesMatch` (same bp page size and same raster size) and `pageSize` (the page area both documents share, in bp).
- `OverlayVerifier.verify(original:output:overlay:)` returns a report with the five counts and bands (top, bottom, left, right in bp, pixel count) and `passed`.
- `PreservedRegions.check(_:diff:) throws` takes rectangles in bp with a top-left origin and returns per-rectangle changed and unchecked pixel counts (saturating at 2^62); rectangles with a non-finite coordinate or edge are refused.
- `DiffArtifacts.fileNames` and `DiffArtifacts.paths(in:)` name the artifact destinations so callers can refuse collisions before writing.
- `PageGeometry.a4`, `PageGeometry.classify(_:)` returning exact A4, near A4 or other, `PageGeometry.inkInRemovedStrip(url:pageIndex:target:dpi:)` / `inkInRemovedStrip(page:target:dpi:)`, and `PageGeometry.inkOutsideCropBox(page:dpi:)`.
- `DiffArtifacts.write(diff:checks:preserved:identical:to:)` writes diff_signed.png, diff_abs.png, diff.bin and report.json with the results of the checks that ran, each written atomically.

**pdf-form-fill-swift (library product PDFFormFill, depends on PDFVisualDiff):**

- `FormSkeleton.generate(blankForm:reference:)` returns the skeleton text; deterministic; refuses unsafe blank-form paths.
- `OverlayCompiler(engine:).compile(tex:pageSize:timeout:)` returns the overlay PDF URL in a temporary directory that `OverlayCompiler.discard(_:)` removes; errors carry the end of the log, name the engine, report a timeout or an invalid one, or give both page sizes.
- `FormStamper.stamp(original:overlay:pageMode:output:)` writes the stamped single page; `FormStamper.targetSize(original:pageMode:)` runs the checks that do not need the overlay; errors for multi-page, rotated or annotated originals, a rotated or annotated overlay, ink in the removed strip, an overlay of the wrong size, an output that names an input, and an existing output that is not a regular file.
- `FormFiller.fill(tex:output:pageMode:dpi:engine:diffDirectory:timeout:)` checks everything it can before writing, compiles, refuses an overlay with ink outside its page, stamps, verifies and returns the report; the output is written even when verification fails.

**macdoc CLI:**

- `macdoc pdf visual-diff` (`--original`, `--reproduced`), `macdoc pdf form-skeleton` (`--pdf`, `--output`), `macdoc pdf form-fill` (`--output` names the file written, following macdoc's rule that `--output` is where a command writes); exit status 0 only when all applicable checks pass; written files reported on stderr as `已寫入: <path>`; errors in Traditional Chinese.
- `macdoc pdf compare` prints the geometry section after the existing report.
- cli-spec.yaml regenerated with the cli-spec make target; README.md and CONVERSIONS.md describe the new subcommands.

**Acceptance:** the synthetic near-A4 form example and the collision example of the specs pass as automated tests in pdf-form-fill-swift (engine-dependent tests skip with an explicit message when xelatex is missing); the core's tests cover every requirement scenario of pdf-visual-verification with synthetic PDFs created in the tests; macdoc's CLI tests cover exit statuses of the three subcommands; no test or document in the public repositories contains a real institution's form.

**In scope:** the two new packages, the comparator geometry layer, the macdoc dependencies and subcommands, regenerated cli-spec.yaml, README.md and CONVERSIONS.md.
**Out of scope:** grid-line detection, transcription figure verification, MCP tools, the docx harness, multi-page forms, releases of the macdoc binary.

## Risks / Trade-offs

- [CoreGraphics re-encoding changes rendering of the original] → fired in verification round 8 on fractional-position tables, curves and real Word-exported forms; stamping moved to the object level.
- [PDFKit merges adjacent CJK labels into one run because there is no whitespace] → labels are positional hints in comments only; users adjust coordinates; documented in the skeleton header.
- [xelatex or fonts missing on CI] → engine-dependent tests skip with a message naming the missing engine; core tests do not need TeX.
- [Public repositories leak private material] → tests generate synthetic PDFs; review checks for absolute home paths and institution names before pushing.
- [Antialiasing makes adjacent-but-not-touching glyphs share an edge pixel] → reported as overlap by design; the report gives the band so a human decides; no filtering is added.
- [A file name injects TeX through `\BlankForm`] → the skeleton refuses such paths; the engine runs without shell escape and with a timeout; reading files is not sandboxed and the .tex is documented as trusted input.

## Migration Plan

Additive. macdoc gains dependencies and subcommands. `macdoc pdf compare` changes in three ways: it prints a page-geometry section, its SUMMARY gains a page-size verdict and labels the existing paper line as a class, and its JSON report gains an optional `pageGeometry` field (older reports still decode). Rollback: revert the macdoc commits; the new packages remain available for other consumers.

`form-skeleton` writes its text to stdout when `--output` is omitted, as macdoc's CLI rules ask; then `\BlankForm` holds an absolute path, because there is no output location to make it relative to.

## Open Questions

- Whether the two Clarity Surface defaults (subcommands under the pdf group; skeleton only) are what the maintainer wants; they are recorded in the issue's Action items for confirmation.
