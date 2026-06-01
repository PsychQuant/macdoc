// NoteFixtureGeneratorTests — covers PsychQuant/macdoc#100 Plan-tier delivery.
//
// RED→GREEN tests for the synthetic .note generator. Verifies:
// - Output parses through NoteCore.NoteParser (proves Notability format compliance)
// - Synthetic content carries zero personal data (privacy audit)
// - Generator is deterministic across calls (regeneration safety)

import XCTest
import NoteCore  // re-exported via the test target's transitive deps

final class NoteFixtureGeneratorTests: XCTestCase {

    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("note-fixture-test-\(UUID().uuidString).note")
    }

    func testGeneratorProducesParseableNote() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try NoteFixtureGenerator.generate(at: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
            "Generator should write a .note file at the target URL")

        // The key assertion: NoteCore.NoteParser accepts our synthetic output.
        let parsed = try NoteParser().parse(input: url)
        XCTAssertGreaterThanOrEqual(parsed.pageCount, 1,
            "Synthetic note should have at least one page")
    }

    func testGeneratorOutputHasZeroPII() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try NoteFixtureGenerator.generate(at: url)

        // Read the entire .note ZIP bytes + search for any PII markers we can
        // think of. Synthetic content should be obviously test-only.
        let bytes = try Data(contentsOf: url)
        let asString = String(data: bytes, encoding: .utf8) ?? ""

        // Markers that would indicate real personal data leaked in.
        let piiMarkers = [
            "@gmail.com", "@yahoo.com", "@hotmail.com",
            "kiki830621",  // any author handle that might creep in
        ]
        for marker in piiMarkers {
            XCTAssertFalse(asString.contains(marker),
                "Synthetic .note should not contain PII marker '\(marker)'")
        }

        // Positive assertion: synthetic content marker is recognizable.
        // (We check the parsed title since the binary plist may not surface
        // strings as UTF-8 visible.)
        let parsed = try NoteParser().parse(input: url)
        XCTAssertTrue(parsed.title.contains("macdoc") || parsed.title.contains("fixture"),
            "Synthetic title should be recognizable as a test fixture, got: \(parsed.title)")
    }

    func testGeneratorIsDeterministic() throws {
        let urlA = makeTempURL()
        let urlB = makeTempURL()
        defer {
            try? FileManager.default.removeItem(at: urlA)
            try? FileManager.default.removeItem(at: urlB)
        }

        try NoteFixtureGenerator.generate(at: urlA)
        try NoteFixtureGenerator.generate(at: urlB)

        // Parse both and assert structural-field equality.
        let parsedA = try NoteParser().parse(input: urlA)
        let parsedB = try NoteParser().parse(input: urlB)

        XCTAssertEqual(parsedA.pageCount, parsedB.pageCount)
        XCTAssertEqual(parsedA.pageWidth, parsedB.pageWidth)
        XCTAssertEqual(parsedA.title, parsedB.title)
    }

    func testGeneratorOutputSizeIsSmall() throws {
        // Per Plan: target ≤ 5 KB. Assert this so the fixture stays minimal.
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try NoteFixtureGenerator.generate(at: url)
        let size = try Data(contentsOf: url).count
        XCTAssertLessThan(size, 5 * 1024,
            "Generated .note should be under 5 KB, got \(size) bytes")
    }
}
