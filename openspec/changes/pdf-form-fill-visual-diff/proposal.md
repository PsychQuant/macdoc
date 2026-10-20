## Why

Blank PDF forms often have to be filled repeatedly, and macdoc has no way to produce a filled form whose original layout is provably untouched. A prototype showed that the usual approach (placing the blank PDF under a TeX overlay with pdfpages) slightly rescales a near-A4 page and shifts every line, and that visual inspection misses one- or two-pixel collisions between typed text and the printed form. Issue PsychQuant/macdoc#240 asks for a generator plus a verification contract that compares every pixel of the result against the original PDF without thresholds.

## What Changes

- New public Swift package PsychQuant/pdf-visual-diff-swift: deterministic page rasterization (CoreGraphics, sRGB, white background, top-left aligned, fixed DPI), signed per-pixel per-channel RGB difference D = output − original, five overlay checks (difference outside the overlay, original made lighter, overlay ink on original ink, ink in a cropped strip, overlay missing from the output), a preserved-region check (D must be 0 inside given rectangles), exact A4 page geometry (210×297 mm) with near-A4 detection, and diff artifacts (two PNG views, raw D, JSON report).
- New public Swift package PsychQuant/pdf-form-fill-swift: blank form → .tex overlay skeleton (bp units, top-left origin, one empty field macro and one commented placement line per printed label, a single-line `\at` and a wrapping multi-line `\atbox` macro, page size equal to the output's), overlay compilation with xelatex (twice), 1:1 stamping of the overlay onto a copy of the original page with optional top-left A4 normalization (translation only, never scaling), and built-in verification through pdf-visual-diff-swift.
- PsychQuant/pdf-to-latex-swift: the PDF comparator gains a page-geometry layer (exact page sizes, A4 compliance, size mismatches) built on pdf-visual-diff-swift; released as a new minor version.
- macdoc depends on the three packages by URL and version, and adds three subcommands under the existing pdf command group: form-skeleton, form-fill and visual-diff. The existing compare subcommand prints the page-geometry layer. cli-spec.yaml, README.md and CONVERSIONS.md are regenerated or updated accordingly.

Documented assumptions (unattended run, to be challenged in review):
- The subcommands live under the existing pdf command group, beside compare (Clarity Surface row 1, default).
- The first version only emits a skeleton; automatic grid-line detection is out of scope (Clarity Surface row 3, default).
- Stamping uses a CoreGraphics PDF context that redraws the page content as vector content with a translation only; it was verified at 0 differing pixels, so the object-level MediaBox alternative was not built. Originals whose annotations a redraw would drop are refused.

## Non-Goals

- Automatic detection of table grid lines or field boxes (Clarity Surface row 3); tracked as a follow-up issue.
- Multi-page forms, rotated pages, and originals carrying annotations or form fields (refused with a named error).
- Fields printed on shaded cells or scanned forms, where every typed pixel lands on non-white original pixels and the overlap check cannot pass; tracked as a follow-up issue.
- A read sandbox for TeX: the overlay .tex is trusted input. The engine runs without shell escape and with a timeout, and the generated skeleton refuses blank-form paths that TeX would misread.
- MCP tools (PsychQuant/che-pdf-mcp#6), the docx harness (PsychQuant/che-word-mcp#295) and transcription figure checks (PsychQuant/pdf-to-latex-swift#13).

## Capabilities

### New Capabilities

- `pdf-visual-verification`: threshold-free pixel verification of a PDF produced from another PDF — rendering, signed RGB difference, the five overlay checks, preserved regions, exact A4 geometry, diff artifacts, and the macdoc visual-diff subcommand and compare page-geometry output.
- `pdf-form-fill`: blank-form skeleton generation, overlay compilation, 1:1 stamping with A4 normalization, and the macdoc form-skeleton and form-fill subcommands.

### Modified Capabilities

(none)

## Impact

- Affected specs: new `pdf-visual-verification`, new `pdf-form-fill`. The `cli-spec` requirements are unchanged; only the generated cli-spec.yaml is regenerated.
- Affected code:
  - New: Sources/MacDocCLI/MacDoc+PDFForm.swift, Tests/MacDocCLITests/PDFFormCommandTests.swift
  - Modified: Package.swift, Package.resolved, Sources/MacDocCLI/MacDoc+PDF.swift, cli-spec.yaml, README.md, CONVERSIONS.md
  - Removed: (none)
- External repositories: two new public repositories under PsychQuant (pdf-visual-diff-swift, pdf-form-fill-swift), each passing the macdoc security audit script before its first tag; a minor release of pdf-to-latex-swift.
- Runtime dependency: form-fill requires xelatex on PATH (or an explicit engine path); tests that need it skip with an explicit message when it is absent.
