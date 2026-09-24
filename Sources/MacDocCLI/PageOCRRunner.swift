import Foundation
import OCRCore
import PDFToLaTeXCore

#if canImport(PDFKit)
import PDFKit
#endif

/// 簡化 pipeline 的 page-level OCR orchestrator。
/// 取代 block segmentation + per-block AI transcription。
struct PageOCRRunner {

    enum Mode {
        case local
        case ollama(host: String)
    }

    let mode: Mode
    let withPDFKit: Bool
    let model: String

    init(mode: Mode = .local, withPDFKit: Bool = false, model: String = "mlx-community/Qwen3-VL-4B-Instruct-4bit") {
        self.mode = mode
        self.withPDFKit = withPDFKit
        self.model = model
    }

    /// #218 (Codex round-1 finding #5a): pulled out of `run()`'s backend
    /// switch so a test can confirm this factory itself passes `model`
    /// through to `OllamaBackend` rather than hardcoding it (the bug this
    /// file used to have), without needing a running Ollama server or a
    /// real OCR pipeline — `OllamaBackend`'s initializer is a plain struct
    /// init (no I/O), so this is safe to call directly.
    ///
    /// Honest limitation (Codex round-2 finding #2): a test against this
    /// factory only proves the factory itself is correct, not that `run()`
    /// below actually calls it with the resolved `model` — reverting just
    /// the one call site in `run()` back to a hardcoded literal, while
    /// leaving this factory untouched, would not be caught by that test.
    static func makeOllamaBackend(host: String, model: String) -> OllamaBackend {
        OllamaBackend(host: host, model: model)
    }

    /// Run OCR on specified pages, writing results to the manifest.
    func run(
        project: inout ResolvedProject,
        pageNumbers: [Int],
        dpi: Double = 200,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async throws -> [PageOCRResult] {
        let store = ManifestStore()
        let renderer = PageRenderer()
        let root = project.root

        // Ensure pages are rendered
        let pagesDir = root.appendingPathComponent("pages", isDirectory: true)
        let renderedPages = try renderer.renderPages(
            pdfAt: project.pdfURL, outputDirectory: pagesDir,
            dpi: dpi, firstPage: pageNumbers.min(), lastPage: pageNumbers.max()
        )
        let renderedByPage = Dictionary(uniqueKeysWithValues: renderedPages.map { ($0.pageNumber, $0.imagePath) })

        // Update manifest with rendered paths
        for i in project.manifest.pages.indices {
            if let imagePath = renderedByPage[project.manifest.pages[i].number] {
                project.manifest.pages[i].renderedImagePath = imagePath
                project.manifest.pages[i].renderedDPI = dpi
            }
        }

        // Build backend
        let backend: any OCRBackend
        switch mode {
        case .local:
            backend = try await MLXBackend.load(repo: model)
        case .ollama(let host):
            // #218: this used to hardcode "glm-ocr" regardless of `self.model`,
            // silently discarding both an explicit `--model` and (once wired)
            // `config ocr`'s default model. Use the resolved model the caller
            // already picked.
            backend = Self.makeOllamaBackend(host: host, model: model)
        }

        // Detect if vector PDF (for PDFKit cross-validation)
        let usesPDFKit: Bool
        if withPDFKit {
            usesPDFKit = true
        } else {
            let detector = PDFSourceDetector()
            let detection = detector.detect(from: project.pdfURL)
            usesPDFKit = detection.format != .scanned
        }

        // OCR each page
        var results: [PageOCRResult] = []

        for (idx, pageNum) in pageNumbers.enumerated() {
            progressHandler?(idx + 1, pageNumbers.count)

            guard let imagePath = renderedByPage[pageNum] else { continue }

            let imageData = try Data(contentsOf: URL(fileURLWithPath: imagePath))
            let ocrText = try await backend.processImage(imageData)

            // PDFKit extraction for vector PDFs
            var pdfkitText: String? = nil
            var agreement: Double? = nil
            var hasConflicts = false

            #if canImport(PDFKit)
            if usesPDFKit {
                pdfkitText = extractPDFKitText(pdfURL: project.pdfURL, pageNumber: pageNum)
                if let pt = pdfkitText {
                    agreement = computeAgreement(a: ocrText, b: pt)
                    hasConflicts = (agreement ?? 1.0) < 0.95
                }
            }
            #endif

            // Save OCR text to file
            let ocrTextPath = root
                .appendingPathComponent("pages")
                .appendingPathComponent("page-\(String(format: "%03d", pageNum))-ocr.txt")
                .path
            try ocrText.write(toFile: ocrTextPath, atomically: true, encoding: .utf8)

            let result = PageOCRResult(
                pageNumber: pageNum,
                ocrText: ocrText,
                pdfkitText: pdfkitText,
                ocrTextPath: ocrTextPath,
                agreement: agreement,
                hasConflicts: hasConflicts
            )
            results.append(result)
        }

        // Update manifest
        project.manifest.ocrResults = results
        project.manifest.schemaVersion = max(project.manifest.schemaVersion, 3)
        project.manifest.updatedAt = Support.nowISO8601()
        try store.save(project.manifest, to: project.manifestURL)

        return results
    }

    // MARK: - Private

    #if canImport(PDFKit)
    private func extractPDFKitText(pdfURL: URL, pageNumber: Int) -> String? {
        guard let doc = PDFDocument(url: pdfURL),
              let page = doc.page(at: pageNumber - 1) else { return nil }
        return page.string
    }
    #endif

    private func computeAgreement(a: String, b: String) -> Double {
        let wordsA = Set(a.split(whereSeparator: \.isWhitespace).map(String.init))
        let wordsB = Set(b.split(whereSeparator: \.isWhitespace).map(String.init))
        guard !wordsA.isEmpty || !wordsB.isEmpty else { return 1.0 }
        let intersection = wordsA.intersection(wordsB).count
        let union = wordsA.union(wordsB).count
        return Double(intersection) / Double(union)
    }
}
