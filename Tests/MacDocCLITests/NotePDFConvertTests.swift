import XCTest
import PDFKit

/// Smoke coverage for `macdoc convert --to pdf file.note`.
///
/// Guards against the "#78 refactor passed with zero tests exercising
/// NoteToPDF" gap flagged by #81. Uses the on-disk `test-files/*.note`
/// fixture (Option B per #81 diagnosis); skips cleanly when absent so
/// CI / clean-clone builds are not broken by the missing binary blob.
final class NotePDFConvertTests: XCTestCase {

    private let pdfMagic: [UInt8] = [0x25, 0x50, 0x44, 0x46]  // "%PDF"

    /// Issue body's Expected section requires "Producer string matches expected".
    /// note-to-pdf-swift renders via CoreGraphics → macOS Quartz PDFContext, so the
    /// Producer line SHALL contain this substring. Stronger than magic-bytes alone:
    /// rules out "any 4-byte %PDF stub" and distinguishes macdoc output from an
    /// arbitrary PDF that happened to land at the output path.
    private let expectedProducerSubstring = "Quartz PDFContext"

    func testNoteToPDFSmoke() throws {
        let fixture = try CLITestHelper.noteFixture()

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdoc-note-pdf-smoke-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let result = try CLITestHelper.convert(
            to: "pdf",
            input: fixture.path,
            flags: ["--output", outputURL.path]
        )

        XCTAssertEqual(
            result.exitCode, 0,
            "macdoc convert --to pdf SHALL exit 0\nstderr: \(result.stderr)"
        )

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outputURL.path),
            "output SHALL exist at \(outputURL.path)"
        )

        let data = try Data(contentsOf: outputURL)
        XCTAssertGreaterThanOrEqual(data.count, 4, "output SHALL be non-trivial")
        XCTAssertEqual(
            Array(data.prefix(4)), pdfMagic,
            "output SHALL start with %PDF magic bytes"
        )

        // Producer assertion — issue body Expected section requirement.
        guard let pdf = PDFDocument(url: outputURL) else {
            return XCTFail("output SHALL be a well-formed PDF readable by PDFKit")
        }
        let producer = pdf.documentAttributes?[PDFDocumentAttribute.producerAttribute] as? String ?? ""
        XCTAssertTrue(
            producer.contains(expectedProducerSubstring),
            "Producer string SHALL contain '\(expectedProducerSubstring)' (got: '\(producer)')"
        )

        // Page count floor — guards against the #77 logicalPageHeight regression class
        // (a single-paragraph .note should produce ≥ 1 rendered page, not zero).
        XCTAssertGreaterThanOrEqual(
            pdf.pageCount, 1,
            "rendered PDF SHALL contain at least one page"
        )
    }
}
