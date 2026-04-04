## ADDED Requirements

### Requirement: Page-level OCR via GLM-OCR

The system SHALL provide page-level OCR using GLM-OCR (MLX inference) as the primary text extraction method for the pdf-to-latex pipeline, replacing block-level segmentation and per-block AI transcription.

#### Scenario: OCR a vector PDF page with PDFKit cross-validation

- **WHEN** the user runs `macdoc pdf ocr --project <dir>` on a vector PDF
- **THEN** the system renders each page to PNG at the configured DPI
- **AND** extracts text via PDFKit for each page
- **AND** runs GLM-OCR on each rendered page image
- **AND** stores both results in the manifest as `PageOCRResult`
- **AND** computes agreement ratio between PDFKit and GLM-OCR outputs

#### Scenario: OCR a scanned PDF page (no PDFKit)

- **WHEN** the user runs `macdoc pdf ocr --project <dir>` on a scanned PDF
- **THEN** the system renders each page to PNG
- **AND** runs GLM-OCR on each rendered page image
- **AND** stores the GLM-OCR result in the manifest (pdfkitText is nil)

#### Scenario: OCR with Ollama mode

- **WHEN** the user runs `macdoc pdf ocr --project <dir> --mode ollama`
- **THEN** the system sends each rendered page image to the configured Ollama host via HTTP API
- **AND** uses the `glm-ocr` model on Ollama
- **AND** stores results in the same `PageOCRResult` format

#### Scenario: OCR specific page range

- **WHEN** the user specifies `--first-page 5 --last-page 10`
- **THEN** only pages 5 through 10 are rendered and OCR'd
- **AND** existing results for other pages in the manifest are preserved

### Requirement: Automatic source detection for OCR strategy

The system SHALL automatically detect whether a PDF is vector or scanned using `PDFSourceDetector`, and apply the appropriate OCR strategy without user intervention.

#### Scenario: Vector PDF detected

- **WHEN** `detect-source` identifies the PDF as LaTeX, Word, or Typst origin
- **THEN** the OCR pipeline uses both PDFKit and GLM-OCR (two-source comparison)

#### Scenario: Scanned PDF detected

- **WHEN** `detect-source` identifies the PDF as scanned
- **THEN** the OCR pipeline uses GLM-OCR only (single source)

### Requirement: Backward-compatible CLI

The system SHALL introduce `macdoc pdf ocr` as the new OCR subcommand while preserving existing subcommands as deprecated.

#### Scenario: New OCR subcommand

- **WHEN** the user runs `macdoc pdf ocr --project <dir>`
- **THEN** the system performs page-level OCR using the simplified pipeline
- **AND** writes results to the project manifest

#### Scenario: Deprecated subcommands still work

- **WHEN** the user runs `macdoc pdf blocks`, `macdoc pdf transcribe`, `macdoc pdf transcribe-pages`, or `macdoc pdf resume`
- **THEN** the subcommand executes as before (no behavior change)
- **AND** a deprecation notice is printed to stderr

### Requirement: Manifest schema extension

The system SHALL extend the project manifest to support page-level OCR results alongside the existing block-level structure.

#### Scenario: Manifest stores page OCR results

- **WHEN** page-level OCR completes for a page
- **THEN** the manifest contains a `PageOCRResult` entry with `pageNumber`, `ocrText`, optional `pdfkitText`, optional `agreement` ratio, and `hasConflicts` flag
- **AND** the manifest `schemaVersion` is incremented

#### Scenario: Old manifests remain readable

- **WHEN** the system opens a manifest with only `blocks` and no `ocrResults`
- **THEN** the manifest loads without error
- **AND** the old block-based pipeline commands still function
