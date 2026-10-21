## Purpose

Fill a blank PDF form by typesetting only the typed text in TeX and stamping it 1:1 onto an untouched copy of the original page, then prove with pixel verification that the original was not altered. It exists because placing the form inside TeX rescales it and visual checks miss small collisions.

## ADDED Requirements

### Requirement: Overlay skeleton from a blank form

The form-fill library SHALL read page 1 of a blank PDF form with PDFKit and write a .tex skeleton with zero margins and a paper size equal to the output's page size: A4 when the form is within 1.5 bp of A4, the form's own size in bp otherwise. The skeleton SHALL define a `\BlankForm` macro holding the blank form's path; a settings section with one empty field macro per detected text label (`\FieldA`, `\FieldB`, … continuing with `\FieldAA` after `\FieldZ`), each commented with its label text; an `\at{x}{y}{size}` placement macro and an `\atbox{x}{y}{width}{size}` macro for text that wraps within a width, both in bp with a top-left origin; and one commented placement line per label that uses that label's field macro and gives the label text and its position in bp rounded to 0.1. Labels SHALL be the text runs of each line as extracted by PDFKit, in reading order. The same input SHALL always produce byte-identical output. The skeleton SHALL compile with xelatex without edits. A blank-form path containing a backslash, a brace, `%`, `#`, `^`, a control character or a line or paragraph separator SHALL be refused with an error naming the path, because TeX would misread it. Control characters and line or paragraph separators in label text and in the header's file name SHALL be replaced, since both sit in TeX comments, where the other characters are inert.

#### Scenario: Labels appear with their positions

- **GIVEN** a synthetic blank form with the labels 甲, 乙 and 丙 drawn at known positions
- **WHEN** a skeleton is generated
- **THEN** the skeleton contains one commented placement line per label whose coordinates are within 0.5 bp of the drawn positions

#### Scenario: Each label has a field macro used by its placement line

- **GIVEN** a synthetic blank form with the labels 標題, 甲, 乙 and 丙
- **WHEN** a skeleton is generated
- **THEN** the settings section declares `\FieldA` to `\FieldD` with those labels as comments, and the placement line of 甲 uses `\FieldB`

#### Scenario: Skeleton compiles unmodified

- **WHEN** a freshly generated skeleton is compiled with xelatex
- **THEN** compilation succeeds and produces one page of the output's size

#### Scenario: A form larger than A4 gets its own page size

- **GIVEN** a synthetic 620×900 bp blank form
- **WHEN** a skeleton is generated
- **THEN** the geometry line sets paperwidth=620.0000bp and paperheight=900.0000bp

#### Scenario: A multi-line field wraps within its width

- **GIVEN** a skeleton for an A4 form with `\atbox{100}{400}{120}{12}{…}` holding 24 CJK characters
- **WHEN** the form is filled
- **THEN** every check passes and the typed text spans more than 24 bp vertically and no further right than its width

#### Scenario: A path TeX would misread is refused

- **WHEN** a skeleton is requested with a blank-form path containing `%`
- **THEN** the call fails with an error naming that path

### Requirement: Overlay compilation

The library SHALL compile the overlay .tex (following a symbolic link to the file itself) by copying its contents under a fixed name into a fresh temporary directory and running xelatex twice there with shell escape disabled, using the source file's directory as the working directory, so that no build artifacts are written next to the source file and the file name never reaches TeX's command line. It SHALL stop a run that does not finish within a timeout (default 120 seconds), together with the engine's process group and the descendants still attached to it, and report the timeout; a timeout that is not a positive finite number SHALL be refused. The temporary directory SHALL be readable by its owner only. Removing a compiled overlay's directory SHALL touch only a directory the compiler created in the same process, as recorded when it was created; an unreadable source SHALL be reported as such. It SHALL fail with an error carrying the end of the log when compilation fails, with an error naming the engine when the engine cannot be found, and with an error stating both sizes when the compiled overlay page does not have the required size within 0.01 bp. On failure the temporary directory SHALL be removed; on success the caller SHALL be able to remove it.

#### Scenario: Missing engine is reported, not skipped silently

- **WHEN** compilation is requested with an engine path that does not exist
- **THEN** the call fails with an error that names that path

#### Scenario: No build artifacts next to the source

- **WHEN** an overlay is compiled successfully
- **THEN** the directory containing the source .tex gains no new files

#### Scenario: A .tex reached through a relative symbolic link compiles

- **GIVEN** a symbolic link in another directory pointing to a filled .tex with a relative path
- **WHEN** the form is filled through the link
- **THEN** it compiles and every check passes

#### Scenario: A compile that never ends is stopped

- **WHEN** a .tex that loops forever is compiled with a 2 second timeout
- **THEN** the call fails with a timeout error after about 2 seconds

### Requirement: One-to-one stamping with A4 normalization

The library SHALL stamp the compiled overlay onto a copy of the original page so that both pages are placed with translation only, each clipped to its own crop box, and neither is scaled; the page content SHALL be redrawn as vector content, not rasterized. The overlay page SHALL be unrotated and have the output's page size within 0.01 bp. With page mode `a4` (default) a near-A4 original SHALL be normalized to exact A4 by keeping its top-left corner; with page mode `original` the original page size SHALL be kept. Before anything is written, originals with more than one page, a rotated page, or any annotation SHALL be rejected with an error stating the page count, the rotation or the annotation count, and an overlay with any annotation SHALL be rejected with an error stating the count, because stamping drops it. The output SHALL NOT be the original, the overlay or the .tex source, including through a symbolic link, and when it exists it SHALL be a regular file, not a directory or a symbolic link; such a path SHALL be rejected before anything is written. The output SHALL be moved into place in one atomic rename that can never replace a directory, keeping the permissions of an output it replaces. The original file SHALL never be modified.

#### Scenario: Near-A4 original becomes exact A4 without moving the form

- **GIVEN** a synthetic 596×843 bp blank form and a compiled overlay
- **WHEN** the overlay is stamped with page mode `a4`
- **THEN** the output page is 595.2756×841.8898 bp and the difference-outside-overlay, original-made-lighter and ink-in-cropped-strip checks all report 0

#### Scenario: Multi-page original is rejected

- **WHEN** stamping is requested on a two-page original
- **THEN** the call fails with an error stating that the original has 2 pages

#### Scenario: An output path that is the blank form is rejected

- **GIVEN** a .tex whose `\BlankForm` is form.pdf
- **WHEN** the form is filled with form.pdf as the output, directly or through a symbolic link
- **THEN** the call fails with an error naming the blank form and form.pdf is byte-identical to before

#### Scenario: A directory given as the output is rejected

- **WHEN** the form is filled with the .tex's own directory, or any other existing directory, as the output
- **THEN** the call fails with an error naming that path and nothing in the directory changes

#### Scenario: An annotated original is rejected

- **WHEN** stamping is requested on an original that carries one link annotation
- **THEN** the call fails with an error stating 1 annotation

#### Scenario: The overlay must have the output's size

- **WHEN** an A4 overlay is stamped onto a 596×843 bp original in page mode `original`
- **THEN** the call fails with an error stating both sizes

### Requirement: Built-in verification after filling

The library SHALL check the resolution, the timeout, the output path and the original before compiling, render the original before writing the output, compile the overlay at the output's page size, refuse an overlay that draws outside its page (ink up to one page beyond each edge found pixel by pixel; from the overlay's content stream, at any distance, an em box around any visible glyph placed by the font's widths and the text state, a point of a painted path, an image corner or a shading lying more than half a page beyond the crop box, unless a clip keeps it within that reach), refuse as unverifiable an overlay whose drawing cannot be placed (text in a font without width data, an unresolvable XObject, a content stream that fails to parse, a form XObject that cannot be read to the end through a cycle, nesting deeper than 16, more than 2000 distinct forms or more than 100000 form invocations), stamp it, and run the five overlay checks of the pdf-visual-verification capability against the original PDF, the output and the overlay page. It SHALL return the report and treat the fill as failed when any check is non-zero. The output file SHALL still be written so that the user can inspect it. The overlay's temporary directory SHALL be removed when filling ends.

#### Scenario: Collision fails the fill and names the place

- **GIVEN** an overlay that places text over a printed label
- **WHEN** the form is filled
- **THEN** the output file exists, the overlay-on-ink check is non-zero, and its band lies inside the label's bounding box

#### Scenario: Text running past the page edge is refused

- **GIVEN** an overlay with WWWWWWWW at (580,400) bp on an A4 page
- **WHEN** the form is filled
- **THEN** the call fails with an error stating the inked pixels outside the page, and no output is written

#### Scenario: Text beyond A4 on a larger form passes in page mode original

- **GIVEN** a skeleton for a 620×900 bp form with 42 placed at (120,860) bp
- **WHEN** the form is filled with page mode `original`
- **THEN** every check passes and the output is 620×900 bp

#### Scenario: A rotated original fails before compiling

- **WHEN** a form whose page has a 90° rotation is filled with an engine that does not exist
- **THEN** the call fails with a rotation error rather than an engine error

### Requirement: macdoc form subcommands

macdoc SHALL provide `macdoc pdf form-skeleton --pdf <blank.pdf> [--output <file.tex>]`, which writes the skeleton to stdout with an absolute blank-form path when `--output` is omitted; with `--output` it refuses to overwrite an existing file even when it appears while the skeleton is generated, and on success reports the written file on stderr and prints nothing else there; and `macdoc pdf form-fill <file.tex>` with `--output` (a file; default: the .tex path with a .pdf extension), `--page a4|original` (default a4), `--dpi` (default 144), `--engine` (default xelatex) and `--diff-dir`. form-fill SHALL read the blank form path from the `\BlankForm` macro, resolving a relative path against the .tex file's directory, report each written file on stderr, print the output size and each check result, and exit with status 0 only when every check passes. Errors SHALL be reported in Traditional Chinese on stderr. When the output would be the blank form or the .tex, or names an existing directory, or a diff artifact would replace the output, the blank form or the .tex, it SHALL print an error and exit with a non-zero status without writing.

#### Scenario: form-fill reports and exits cleanly on a clean overlay

- **WHEN** `macdoc pdf form-fill` runs on a skeleton whose filled fields do not touch the form
- **THEN** it reports the output path on stderr, prints 0 for each of the five checks and exits with status 0

#### Scenario: form-skeleton does not overwrite

- **WHEN** `macdoc pdf form-skeleton` targets an existing file
- **THEN** it fails without changing that file

#### Scenario: The default output never replaces the blank form

- **GIVEN** form.tex whose `\BlankForm` is form.pdf in the same directory
- **WHEN** `macdoc pdf form-fill form.tex` runs without `--output`
- **THEN** it reports that it refuses to write over the blank form, exits with a non-zero status, and form.pdf is unchanged
