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

    /// Per-page ink-density smoke assertion. Catches the round-2 heuristic
    /// regression class documented in #77 where a stroke cut at a page break
    /// would cause one page to appear near-empty while the neighbour carried
    /// both pages' content. With gutter-gap detection + bounding-box allocation
    /// (#77 round 3), every page of a multi-page `.note` should retain ink.
    ///
    /// Skips when the fixture `.note` is absent or produces only 1 page.
    func testNoteToPDFPerPageHasContent() throws {
        let fixture = try CLITestHelper.noteFixture()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdoc-note-pdf-density-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let result = try CLITestHelper.convert(
            to: "pdf",
            input: fixture.path,
            flags: ["--output", outputURL.path]
        )
        XCTAssertEqual(result.exitCode, 0)

        guard let pdf = PDFDocument(url: outputURL), pdf.pageCount >= 2 else {
            throw XCTSkip(
                "Fixture produced \(PDFDocument(url: outputURL)?.pageCount ?? 0) pages; " +
                "per-page density check needs ≥2 pages. Skip rather than misinterpret."
            )
        }

        // Render each page to low-res bitmap and count non-white pixels as a
        // rough proxy for ink. Threshold is deliberately low (≥ 50 dark pixels)
        // so a genuinely-sparse page with just a formula or short word still
        // counts as "has content".
        for pageIdx in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIdx) else {
                return XCTFail("PDF page \(pageIdx) SHALL be accessible")
            }
            let inkPixels = countInkPixels(page: page, scale: 1.0)
            XCTAssertGreaterThanOrEqual(
                inkPixels, 50,
                "page \(pageIdx + 1) of \(pdf.pageCount) SHALL contain visible " +
                "ink (counted \(inkPixels) dark pixels); near-zero suggests strokes " +
                "were allocated to the wrong page — the #77 regression class"
            )
        }
    }

    /// Count non-white pixels in a rendered page thumbnail.
    /// Very rough proxy — threshold R<180 in grayscale. Good enough for
    /// "does this page have ANY content" smoke checks; not suitable for
    /// finer-grained comparisons.
    private func countInkPixels(page: PDFPage, scale: CGFloat) -> Int {
        let pageBounds = page.bounds(for: .mediaBox)
        let width = Int(pageBounds.width * scale)
        let height = Int(pageBounds.height * scale)
        guard width > 0, height > 0 else { return 0 }
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = width
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }
        context.setFillColor(gray: 1.0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        guard let data = context.data else { return 0 }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height)
        var darkCount = 0
        for i in 0..<(width * height) {
            if buffer[i] < 180 {
                darkCount += 1
            }
        }
        return darkCount
    }
}
