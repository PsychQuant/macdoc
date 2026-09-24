import XCTest
import PDFToLaTeXCore
import OCRCore
@testable import MacDocCLI

/// PsychQuant/macdoc#225: `PageOCRRunnerBackendTests.testOllamaBackendUsesTheGivenModelNotAHardcodedOne`
/// (in `PDFOCRConfigTests.swift`) proves `PageOCRRunner.makeOllamaBackend`
/// itself passes `model` through correctly, but only that. Reverting the
/// single call site in `run()` back to a hardcoded literal — the exact #218
/// bug shape — would not have been caught by that test, because nothing
/// exercises `run()` itself against the factory.
///
/// This test does: it runs the *actual* `run()` body (real project
/// resolution + real page rendering, via a synthetic PDF fixture and the
/// real `PDFToLaTeXCore` pipeline — pure PDFKit/CoreGraphics, no external
/// tools) with an injected recording `backendFactory`, and asserts the
/// `mode`/`model` it was called with. No MLX model download, no reachable
/// Ollama server: the injected factory returns a stub `OCRBackend` that
/// never does any I/O.
final class PageOCRRunnerBackendInjectionTests: XCTestCase {

    /// Records nothing interesting itself — the factory closure does the
    /// recording — this only has to conform to `OCRBackend` cheaply.
    private struct StubOCRBackend: OCRBackend {
        func processImage(_ imageData: Data) async throws -> String {
            "stub ocr text"
        }
    }

    private final class FactoryCallRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [(mode: PageOCRRunner.Mode, model: String)] = []

        func record(mode: PageOCRRunner.Mode, model: String) {
            lock.lock()
            defer { lock.unlock() }
            storage.append((mode, model))
        }

        var calls: [(mode: PageOCRRunner.Mode, model: String)] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    /// Builds a one-page project via the real resolver/pipeline — exactly
    /// what `MacDoc+PDF.swift`'s `OCRPages.run()` does before constructing
    /// `PageOCRRunner` — from a synthetic PDF (`FixtureManager
    /// .createMinimalPDF`, pure CoreGraphics/CoreText, already used
    /// elsewhere in this test target for the same reason: no external tool
    /// dependency).
    private func makeOnePageProject() throws -> (project: ResolvedProject, pageNumbers: [Int], cleanup: () -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdoc-pageocr-inject-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let pdfURL = dir.appendingPathComponent("input.pdf")
        FixtureManager.createMinimalPDF(at: pdfURL)
        let projectRoot = dir.appendingPathComponent("project", isDirectory: true)

        var project = try ProjectResolver().resolve(
            project: nil, pdf: pdfURL.path, output: projectRoot.path, cwd: dir)
        try BlockSegmentationPipeline().ensurePageRecords(in: &project)
        let pageNumbers = try BlockSegmentationPipeline().resolvePageNumbers(
            total: project.manifest.pages.count, firstPage: nil, lastPage: nil)

        return (project, pageNumbers, { try? FileManager.default.removeItem(at: dir) })
    }

    /// The core #225 regression: `run()` must call `backendFactory` with
    /// the exact `mode`/`model` `PageOCRRunner` was constructed with — the
    /// values `MacDoc+PDF.swift`'s `resolveRunSettings` already resolves as
    /// flag > config > built-in default (covered separately, without I/O,
    /// by `PDFOCRHostModelResolutionTests` in `PDFOCRConfigTests.swift`).
    /// This test's job is specifically the missing link between that
    /// resolution and the backend actually built from it.
    func testRunPassesResolvedModeAndModelToInjectedBackendFactory() async throws {
        var (project, pageNumbers, cleanup) = try makeOnePageProject()
        defer { cleanup() }
        XCTAssertFalse(pageNumbers.isEmpty, "synthetic fixture should produce at least one page")

        let recorder = FactoryCallRecorder()
        let runner = PageOCRRunner(
            mode: .ollama(host: "10.0.0.5:11435"),
            withPDFKit: false,
            model: "my-custom-tag",
            backendFactory: { mode, model in
                recorder.record(mode: mode, model: model)
                return StubOCRBackend()
            })

        _ = try await runner.run(project: &project, pageNumbers: pageNumbers)

        // Built once per `run()` call (not once per page) — see `run()`'s
        // "Build backend" comment; reused across the page loop via
        // `backend.processImage(...)`.
        XCTAssertEqual(recorder.calls.count, 1, "backendFactory should be called exactly once per run()")
        guard let call = recorder.calls.first else { return }
        XCTAssertEqual(call.model, "my-custom-tag", "must not silently fall back to a hardcoded model")
        XCTAssertEqual(call.mode, .ollama(host: "10.0.0.5:11435"), "must pass through the resolved host, not a hardcoded one")
    }

    /// Same property for `.local` mode, whose `model` is a HuggingFace repo
    /// id rather than an Ollama tag — the two modes' defaults are resolved
    /// differently (see `resolveModel`'s doc comment in `MacDoc+PDF.swift`),
    /// so both call shapes are worth pinning independently.
    func testRunPassesLocalModeAndModelToInjectedBackendFactory() async throws {
        var (project, pageNumbers, cleanup) = try makeOnePageProject()
        defer { cleanup() }

        let recorder = FactoryCallRecorder()
        let runner = PageOCRRunner(
            mode: .local,
            withPDFKit: false,
            model: "mlx-community/some-other-repo",
            backendFactory: { mode, model in
                recorder.record(mode: mode, model: model)
                return StubOCRBackend()
            })

        _ = try await runner.run(project: &project, pageNumbers: pageNumbers)

        XCTAssertEqual(recorder.calls.count, 1)
        guard let call = recorder.calls.first else { return }
        XCTAssertEqual(call.model, "mlx-community/some-other-repo")
        XCTAssertEqual(call.mode, .local)
    }
}
