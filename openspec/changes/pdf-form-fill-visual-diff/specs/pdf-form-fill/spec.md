## Purpose

Fill a blank PDF form by typesetting only the typed text in TeX and stamping it 1:1 onto an untouched copy of the original page, then prove with pixel verification that the original was not altered. It exists because placing the form inside TeX rescales it and visual checks miss small collisions.

## ADDED Requirements

### Requirement: Overlay skeleton from a blank form

The form-fill library SHALL read page 1 of a blank PDF form with PDFKit and write a .tex skeleton that sets an A4 paper size with zero margins, defines a `\BlankForm` macro holding the blank form's path, contains a settings section of empty field macros, defines an `\at{x}{y}{size}` placement macro in bp with a top-left origin, and contains one commented placement line per detected text label giving the label text and its position in bp rounded to 0.1. Labels SHALL be the text runs of each line as extracted by PDFKit, in reading order. The same input SHALL always produce byte-identical output. The skeleton SHALL compile with xelatex without edits.

#### Scenario: Labels appear with their positions

- **GIVEN** a synthetic blank form with the labels 甲, 乙 and 丙 drawn at known positions
- **WHEN** a skeleton is generated
- **THEN** the skeleton contains one commented placement line per label whose coordinates are within 0.5 bp of the drawn positions

#### Scenario: Skeleton compiles unmodified

- **WHEN** a freshly generated skeleton is compiled with xelatex
- **THEN** compilation succeeds and produces one A4 page

### Requirement: Overlay compilation

The library SHALL compile the overlay .tex by running xelatex twice in a temporary directory, so that no build artifacts are written next to the source file. It SHALL fail with an error naming the log file when compilation fails, with an error naming the engine when the engine cannot be found, and with an error stating both sizes when the compiled overlay page is not A4 within 0.01 bp.

#### Scenario: Missing engine is reported, not skipped silently

- **WHEN** compilation is requested with an engine path that does not exist
- **THEN** the call fails with an error that names that path

#### Scenario: No build artifacts next to the source

- **WHEN** an overlay is compiled successfully
- **THEN** the directory containing the source .tex gains no new files

### Requirement: One-to-one stamping with A4 normalization

The library SHALL stamp the compiled overlay onto a copy of the original page so that the overlay is placed with translation only, using the overlay page's own size as the target box, and the original content is never scaled. With page mode `a4` (default) a near-A4 original SHALL be normalized to exact A4 by keeping its top-left corner; with page mode `original` the original page size SHALL be kept. Originals with more than one page SHALL be rejected with an error stating the page count. The original file SHALL never be modified.

#### Scenario: Near-A4 original becomes exact A4 without moving the form

- **GIVEN** a synthetic 596×843 bp blank form and a compiled overlay
- **WHEN** the overlay is stamped with page mode `a4`
- **THEN** the output page is 595.2756×841.8898 bp and the difference-outside-overlay, original-made-lighter and ink-in-cropped-strip checks all report 0

#### Scenario: Multi-page original is rejected

- **WHEN** stamping is requested on a two-page original
- **THEN** the call fails with an error stating that the original has 2 pages

### Requirement: Built-in verification after filling

After stamping, the library SHALL run the four overlay checks of the pdf-visual-verification capability against the original PDF, the output and the overlay page, return the report, and treat the fill as failed when any check is non-zero. The output file SHALL still be written so that the user can inspect it.

#### Scenario: Collision fails the fill and names the place

- **GIVEN** an overlay that places text over a printed label
- **WHEN** the form is filled
- **THEN** the output file exists, the overlay-on-ink check is non-zero, and its band lies inside the label's bounding box

### Requirement: macdoc form subcommands

macdoc SHALL provide `macdoc pdf form-skeleton --pdf <blank.pdf> --output <file.tex>`, which refuses to overwrite an existing output file, and `macdoc pdf form-fill <file.tex>` with `--out` (default: the .tex path with a .pdf extension), `--page a4|original` (default a4), `--dpi` (default 144), `--engine` (default xelatex) and `--diff-dir`. form-fill SHALL read the blank form path from the `\BlankForm` macro, resolving a relative path against the .tex file's directory, print the output path and size and each check result, and exit with status 0 only when every check passes.

#### Scenario: form-fill reports and exits cleanly on a clean overlay

- **WHEN** `macdoc pdf form-fill` runs on a skeleton whose filled fields do not touch the form
- **THEN** it prints the output path, prints 0 for each of the four checks and exits with status 0

#### Scenario: form-skeleton does not overwrite

- **WHEN** `macdoc pdf form-skeleton` targets an existing file
- **THEN** it fails without changing that file
