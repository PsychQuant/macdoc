## Context

A Python prototype (in a private repository) filled PDF forms and was verified by subtracting renders of the result from renders of the original PDF. What drove this design: placing the form under a TeX overlay with pdfpages rescaled it slightly, so lines across the whole page moved; setting the TeX page size equal to the form still left a few edge pixels different because of a 0.001 bp rounding offset; stamping the overlay onto an untouched copy gave 0 pixels outside the overlay. PDFs exported through Acrobat PDFMaker are A4 quantized to a 600 dpi dot grid (4960.63 × 7015.75 dots rounded to 4961 × 7016, that is 595.32 × 841.92 bp); fitting such a page into A4 by scaling moved the whole page while a top-left 1:1 placement changed nothing. A verification pass that only compared a binarized or filtered image hid real collisions that the threshold-free check then found in a template that had passed visual review.

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
- Multi-page forms.
- Cross-renderer comparison: both sides are always rendered by CoreGraphics.

## Decisions

### Separate public packages consumed by URL dependency

pdf-visual-diff-swift and pdf-form-fill-swift are new public repositories under PsychQuant, consumed by macdoc with `.package(url:from:)`. Alternatives: keeping them as in-tree path packages (rejected: three consumers outside the macdoc CLI) or adding them as git submodules (rejected: SwiftPM already pins versions in Package.resolved; a submodule pointer would be a second source of truth). The verification core is a separate package from form filling because pdf-to-latex-swift needs only the core and must not depend on form filling.

### CoreGraphics rasterization as the single renderer

Rendering uses `CGContext` with an sRGB color space, 8 bits per component, premultiplied-last RGBA converted to RGB, filled white, scaled by dpi/72 and translated so the page's top-left corner is at the buffer origin. Buffer size is the ceiling of page size × scale. Alternatives: PDFKit thumbnails (rejected: size and interpolation are not under caller control) or MuPDF (rejected: non-native dependency). Results are only compared within one renderer.

### Signed difference without filtering and overlap from the overlay-only render

D is computed per channel as Int16 with no thresholds or morphology. Overlap cannot be read from D because ink on ink leaves D near 0, so the overlay-on-ink check uses a separate render of the overlay alone and intersects its non-white pixels with the original's non-white pixels. This is the four-check verifier described in the pdf-visual-verification spec.

### Stamping through a CoreGraphics PDF context with an object-level fallback

The filler creates a new single-page PDF with a CoreGraphics PDF context whose media box is the target size, draws the original page translated so its top-left corner lands on the target's top-left corner, then draws the overlay page translated the same way, never scaled. The verifier is the acceptance test: on the synthetic near-A4 form the difference outside the overlay must be 0. If CoreGraphics re-encoding were to produce non-zero difference, the fallback is to rewrite only the MediaBox and append a content stream at the object level; the fallback is not implemented unless the acceptance test fails. Annotations and form fields of the original are not carried over; blank forms are flat pages.

### Exact A4 normalization by top-left translation

A4 is 210/25.4×72 by 297/25.4×72 bp. Near A4 means both dimensions within 1.5 bp. Normalization is a translation that keeps the top-left corner; before normalizing, the original's render is checked for ink in the strip that would be removed, and normalization fails if any is found.

### Skeleton from PDFKit text runs

The skeleton generator reads page 1 with PDFKit, splits its text into lines, takes each run of non-whitespace characters as a label, and uses the union of its character bounds (converted to bp with a top-left origin) for the position. Each label becomes a commented `\at` line placed just right of the label on its baseline, plus the settings section and helper macros. Alternative: emitting nodes inside detected boxes (rejected for now: requires vector path parsing; Clarity Surface row 3).

### Overlay compilation in a temporary directory

The compiler copies nothing; it runs the engine with `-output-directory` set to a temporary directory and `-interaction=nonstopmode -halt-on-error`, twice, with the source file's directory as the working directory so relative `\BlankForm` and font paths resolve. The engine defaults to `xelatex` found on PATH; an explicit path is accepted.

### Page geometry layer in the pdf-to-latex-swift comparator

`PDFComparator` gains a geometry section computed with the core's page-geometry classifier: page sizes grouped by size, classification (exact A4, near A4, other) and the indices of pages whose sizes differ between the two documents. The existing report fields keep their meaning; the JSON report gains a new optional field. Released as pdf-to-latex-swift 0.6.0.

### Raw difference artifact format

diff.bin stores D as little-endian Int16 in row-major height × width × 3 order with no header; report.json carries width, height, dpi and the check results so the file can be decoded without guessing.

### Release order and audit gate

The repositories are created, hardened according to macdoc's SECURITY.md baseline and audited with macdoc's audit script before their first tag. Order: pdf-visual-diff-swift 0.1.0, then pdf-form-fill-swift 0.1.0 and pdf-to-latex-swift 0.6.0, then macdoc switches its dependencies and regenerates Package.resolved.

## Implementation Contract

**pdf-visual-diff-swift (library product PDFVisualDiff):**

- `PageRaster.render(page:dpi:)` and `PageRaster.render(url:pageIndex:dpi:)` return width, height, dpi and RGB bytes; deterministic.
- `SignedDiff(original:output:)` exposes width, height, Int16 values, changed-pixel count and per-channel minimum and maximum.
- `OverlayVerifier.verify(original:output:overlay:)` returns a report with the four counts and bands (top, bottom, left, right in bp, pixel count) and `passed`.
- `PreservedRegions.check(_:diff:)` takes rectangles in bp with a top-left origin and returns per-rectangle differing-pixel counts.
- `PageGeometry.a4`, `PageGeometry.classify(_:)` returning exact A4, near A4 or other, and `PageGeometry.inkInRemovedStrip(original:target:dpi:)`.
- `DiffArtifacts.write(diff:report:to:)` writes diff_signed.png, diff_abs.png, diff.bin and report.json.

**pdf-form-fill-swift (library product PDFFormFill, depends on PDFVisualDiff):**

- `FormSkeleton.generate(blankForm:)` returns the skeleton text; deterministic.
- `OverlayCompiler(engine:).compile(tex:)` returns the overlay PDF URL in a temporary directory; errors name the log, the engine, or both page sizes.
- `FormStamper.stamp(original:overlay:pageMode:output:)` writes the stamped single page; errors for multi-page originals and for ink in the removed strip.
- `FormFiller.fill(tex:output:pageMode:dpi:engine:diffDirectory:)` compiles, stamps, verifies and returns the report; the output is written even when verification fails.

**macdoc CLI:**

- `macdoc pdf visual-diff`, `macdoc pdf form-skeleton`, `macdoc pdf form-fill` with the options in the specs; exit status 0 only when all applicable checks pass.
- `macdoc pdf compare` prints the geometry section after the existing report.
- cli-spec.yaml regenerated with the cli-spec make target; README.md and CONVERSIONS.md describe the new subcommands.

**Acceptance:** the synthetic near-A4 form example and the collision example of the specs pass as automated tests in pdf-form-fill-swift (engine-dependent tests skip with an explicit message when xelatex is missing); the core's tests cover every requirement scenario of pdf-visual-verification with synthetic PDFs created in the tests; macdoc's CLI tests cover exit statuses of the three subcommands; no test or document in the public repositories contains a real institution's form.

**In scope:** the two new packages, the comparator geometry layer, the macdoc dependencies and subcommands, regenerated cli-spec.yaml, README.md and CONVERSIONS.md.
**Out of scope:** grid-line detection, transcription figure verification, MCP tools, the docx harness, multi-page forms, releases of the macdoc binary.

## Risks / Trade-offs

- [CoreGraphics re-encoding changes rendering of the original] → the near-A4 acceptance test fails loudly; switch to the object-level MediaBox fallback.
- [PDFKit merges adjacent CJK labels into one run because there is no whitespace] → labels are positional hints in comments only; users adjust coordinates; documented in the skeleton header.
- [xelatex or fonts missing on CI] → engine-dependent tests skip with a message naming the missing engine; core tests do not need TeX.
- [Public repositories leak private material] → tests generate synthetic PDFs; review checks for absolute home paths and institution names before pushing.
- [Antialiasing makes adjacent-but-not-touching glyphs share an edge pixel] → reported as overlap by design; the report gives the band so a human decides; no filtering is added.

## Migration Plan

Additive. macdoc gains dependencies and subcommands; no existing command changes behavior except that compare prints an extra section. Rollback: revert the macdoc commits; the new packages remain available for other consumers.

## Open Questions

- Whether the two Clarity Surface defaults (subcommands under the pdf group; skeleton only) are what the maintainer wants; they are recorded in the issue's Action items for confirmation.
