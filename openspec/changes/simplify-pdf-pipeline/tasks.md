## 1. Manifest Schema Extension

- [x] 1.1 Add `PageOCRResult` struct to `pdf-to-latex-swift`: define `pageNumber: Int`, `ocrText: String`, `pdfkitText: String?`, `ocrTextPath: String?`, `agreement: Double?`, `hasConflicts: Bool` in `Sources/PDFToLaTeXCore/Models/`. Make it `Codable`.
- [x] 1.2 Add `ocrResults: [PageOCRResult]` optional field to the existing `Manifest` struct. Default to empty array. Increment `schemaVersion` when writing new-style manifests.
- [x] 1.3 Add unit test: load a manifest JSON that has no `ocrResults` field → verify it loads without error and `ocrResults` defaults to `[]`.

## 2. PDFKit Text Extractor

- [x] [P] 2.1 Create `PDFKitExtractor` in `packages/ocr-swift/Sources/OCRCore/Extractors/PDFKitExtractor.swift`. Method: `extractText(pdfURL: URL, pageNumber: Int) -> String` using `PDFDocument` + `PDFPage.string`. Return the raw extracted text for a single page.
- [x] [P] 2.2 Add unit test: extract text from a known vector PDF page, verify output is non-empty and contains expected keywords.

## 3. Page-Level OCR Pipeline

- [x] 3.1 Create `PageOCRRunner` in `packages/pdf-to-latex-swift/Sources/PDFToLaTeXCore/PageOCRRunner.swift`. This orchestrates per-page OCR:
  - Accept a `ResolvedProject`, page range, and mode (local/ollama)
  - For each page: render PNG (reuse `PageRenderer`), run `OCRPipeline.processImage()`
  - If vector PDF (detected via `PDFSourceDetector`): also run `PDFKitExtractor.extractText()`
  - Compute word-level agreement ratio between PDFKit and GLM-OCR (reuse `difflib`-equivalent in Swift, or simple word split + set intersection)
  - Write `PageOCRResult` entries to manifest
  - Save OCR text to `pages/page-NNN-ocr.txt` files
- [ ] 3.2 Add integration test: run `PageOCRRunner` on a 1-page test PDF, verify manifest has `ocrResults` with correct `pageNumber` and non-empty `ocrText`.

## 4. CLI Subcommand

- [x] 4.1 Add `MacDoc.PDF.OCRPages` subcommand in `Sources/MacDocCLI/MacDoc+PDF.swift`:
  - Command name: `ocr`
  - Options: `--project`, `--mode local|ollama` (default: local), `--with-pdfkit` (auto-detect), `--first-page`, `--last-page`, `--model` (default: GLM-OCR repo)
  - Implementation: call `PageOCRRunner`
  - Output to stderr: progress per page ("正在 OCR 第 N/M 頁...")
- [x] 4.2 Add deprecation notices to existing subcommands (`Blocks`, `Transcribe`, `TranscribePages`, `Resume`): print "⚠ 此命令已棄用，請改用 `macdoc pdf ocr`。" to stderr before executing.

## 5. Ollama Backend

- [x] [P] 5.1 Create `OllamaOCR` in `packages/ocr-swift/Sources/OCRCore/Backends/OllamaOCR.swift`. Method: `processImage(image: CGImage, host: String, model: String) async throws -> String`. Send base64-encoded PNG to `http://<host>/api/generate` with `stream: false`, return response text. Use `Foundation.URLSession`.
- [x] [P] 5.2 Add integration test: send a test image to a mock HTTP endpoint, verify response parsing.

## 6. Documentation Update

- [x] [P] 6.1 Update `docs/ensemble-ocr-design.md`: replace 3-source and 2-source architectures with new simplified architecture (向量 PDF: PDFKit + GLM-OCR, 掃描 PDF: GLM-OCR only). Remove Qwen2.5-VL as ensemble partner. Update milestones.
- [x] [P] 6.2 Update `CLAUDE.md` Development Commands section: add `macdoc pdf ocr` usage examples, mark old transcribe commands as deprecated.

## 7. Verification

- [ ] 7.1 Build the full project: `swift build -c release` passes without error.
- [ ] 7.2 End-to-end test: run `macdoc pdf ocr --project /tmp/test-project` on a known PDF, verify manifest contains `ocrResults` and per-page text files exist.
- [ ] 7.3 Verify deprecated commands still work: run `macdoc pdf blocks --project /tmp/test-project`, confirm deprecation notice is printed and command executes.
