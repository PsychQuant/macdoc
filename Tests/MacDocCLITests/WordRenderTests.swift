// WordRenderTests.swift
// Spectra change `script-pipeline-surface` tasks 2.1–2.5 —
// `mdocx-grammar` «Render command rebuilds a document from a script».
//
// `macdoc word render` is the CLI half of the script pipeline. Before this
// change the CLI could produce a script (`word reverse`) but not replay
// one; execute existed only on the MCP face. Both faces now call the same
// shared entry point in OOXMLSwift.

import XCTest
import Foundation
import OOXMLSwift

final class WordRenderTests: XCTestCase {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wrender-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func makeSyntheticDocx(at url: URL, text: String = "第一段落。") throws {
        var doc = WordDocument.emptyAuthoringDocument()
        try doc.apply(operations: [
            .appendParagraph(in: nil, paragraph: ParagraphPayload(
                text: text, styleId: "Body", paraId: "P1")),
            .appendParagraph(in: nil, paragraph: ParagraphPayload(
                text: "第二段落。", paraId: "P2")),
        ])
        try doc.writeAuthoringPackage(to: url)
    }

    /// reverse → render with the source as reference is the round trip the
    /// whole pipeline exists to guarantee.
    func testRoundTripFromReverseToRenderIsByteEqual() throws {
        let dir = try makeTempDir()
        let docx = dir.appendingPathComponent("sample.docx")
        try makeSyntheticDocx(at: docx)

        let script = dir.appendingPathComponent("sample.mdocx.swift")
        let reversed = try CLITestHelper.run(
            ["word", "reverse", docx.path, "--to-mdocx", script.path])
        XCTAssertEqual(reversed.exitCode, 0, "reverse must succeed: \(reversed.stderr)")

        let rebuilt = dir.appendingPathComponent("rebuilt.docx")
        let result = try CLITestHelper.run(
            ["word", "render", script.path,
             "--to-docx", rebuilt.path,
             "--verify-against", docx.path])

        XCTAssertEqual(result.exitCode, 0, "verified round trip must exit 0: \(result.stderr)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rebuilt.path))

        // Independent confirmation — do not take the exit code's word for it.
        let reference = try RawPartChannel.readAllParts(from: docx)
        let produced = try RawPartChannel.readAllParts(from: rebuilt)
        let broken = PartFidelity.compareParts(reference: reference, rebuilt: produced)
            .filter { !$0.isEqual }
        XCTAssertTrue(broken.isEmpty, "parts differed: \(broken.map(\.partPath))")
    }

    /// The bare `.mdocx` filename form must dispatch identically — the
    /// existing dual-extension requirement in `mdocx-grammar` says so.
    func testBareMdocxExtensionIsAccepted() throws {
        let dir = try makeTempDir()
        let docx = dir.appendingPathComponent("sample.docx")
        try makeSyntheticDocx(at: docx)

        let dual = dir.appendingPathComponent("sample.mdocx.swift")
        _ = try CLITestHelper.run(["word", "reverse", docx.path, "--to-mdocx", dual.path])
        let bare = dir.appendingPathComponent("sample.mdocx")
        try FileManager.default.copyItem(at: dual, to: bare)

        let fromDual = dir.appendingPathComponent("from-dual.docx")
        let fromBare = dir.appendingPathComponent("from-bare.docx")
        let a = try CLITestHelper.run(["word", "render", dual.path, "--to-docx", fromDual.path])
        let b = try CLITestHelper.run(["word", "render", bare.path, "--to-docx", fromBare.path])

        XCTAssertEqual(a.exitCode, 0, "dual-extension form must render: \(a.stderr)")
        XCTAssertEqual(b.exitCode, 0, "bare .mdocx form must render: \(b.stderr)")
        XCTAssertEqual(try RawPartChannel.readAllParts(from: fromDual),
                       try RawPartChannel.readAllParts(from: fromBare),
                       "both filename forms must produce the same document")
    }

    /// Verification is opt-in. With no reference the command must not report
    /// any verdict — silence must never be readable as a pass.
    func testRenderWithoutReferenceReportsNoVerdict() throws {
        let dir = try makeTempDir()
        let docx = dir.appendingPathComponent("sample.docx")
        try makeSyntheticDocx(at: docx)
        let script = dir.appendingPathComponent("sample.mdocx.swift")
        _ = try CLITestHelper.run(["word", "reverse", docx.path, "--to-mdocx", script.path])

        let rebuilt = dir.appendingPathComponent("rebuilt.docx")
        let result = try CLITestHelper.run(
            ["word", "render", script.path, "--to-docx", rebuilt.path])

        XCTAssertEqual(result.exitCode, 0, "unverified render still succeeds: \(result.stderr)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rebuilt.path))
        let combined = result.stdout + result.stderr
        XCTAssertFalse(combined.contains("驗證"),
                       "no verification wording may appear when none ran: \(combined)")
    }

    /// A reference that does not match must fail loudly and name what broke.
    func testVerificationMismatchExitsNonZeroAndNamesParts() throws {
        let dir = try makeTempDir()
        let source = dir.appendingPathComponent("source.docx")
        let other = dir.appendingPathComponent("other.docx")
        try makeSyntheticDocx(at: source, text: "原始內容。")
        try makeSyntheticDocx(at: other, text: "完全不同的內容。")

        let script = dir.appendingPathComponent("source.mdocx.swift")
        _ = try CLITestHelper.run(["word", "reverse", source.path, "--to-mdocx", script.path])

        let rebuilt = dir.appendingPathComponent("rebuilt.docx")
        let result = try CLITestHelper.run(
            ["word", "render", script.path,
             "--to-docx", rebuilt.path,
             "--verify-against", other.path])

        XCTAssertNotEqual(result.exitCode, 0, "a mismatch must not exit 0")
        XCTAssertTrue(result.stderr.contains("document.xml"),
                      "the differing part must be named: \(result.stderr)")
    }

    /// Missing inputs are refused before anything is written.
    func testMissingScriptIsRefusedBeforeAnyWrite() throws {
        let dir = try makeTempDir()
        let rebuilt = dir.appendingPathComponent("rebuilt.docx")
        let result = try CLITestHelper.run(
            ["word", "render", dir.appendingPathComponent("nope.mdocx.swift").path,
             "--to-docx", rebuilt.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("找不到輸入檔案"),
                      "error must be the shared Chinese message: \(result.stderr)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: rebuilt.path),
                       "nothing may be written when the script is missing")
    }

    func testMissingReferenceIsRefusedBeforeAnyWrite() throws {
        let dir = try makeTempDir()
        let docx = dir.appendingPathComponent("sample.docx")
        try makeSyntheticDocx(at: docx)
        let script = dir.appendingPathComponent("sample.mdocx.swift")
        _ = try CLITestHelper.run(["word", "reverse", docx.path, "--to-mdocx", script.path])

        let rebuilt = dir.appendingPathComponent("rebuilt.docx")
        let result = try CLITestHelper.run(
            ["word", "render", script.path,
             "--to-docx", rebuilt.path,
             "--verify-against", dir.appendingPathComponent("nope.docx").path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: rebuilt.path),
                       "nothing may be written when the reference is missing")
    }

    /// An existing output is protected unless overwrite is requested,
    /// matching how `word reverse` guards its own output.
    func testExistingOutputIsProtectedWithoutForce() throws {
        let dir = try makeTempDir()
        let docx = dir.appendingPathComponent("sample.docx")
        try makeSyntheticDocx(at: docx)
        let script = dir.appendingPathComponent("sample.mdocx.swift")
        _ = try CLITestHelper.run(["word", "reverse", docx.path, "--to-mdocx", script.path])

        let rebuilt = dir.appendingPathComponent("rebuilt.docx")
        let sentinel = Data("do not clobber".utf8)
        try sentinel.write(to: rebuilt)

        let refused = try CLITestHelper.run(
            ["word", "render", script.path, "--to-docx", rebuilt.path])
        XCTAssertNotEqual(refused.exitCode, 0, "existing output must be refused")
        XCTAssertEqual(try Data(contentsOf: rebuilt), sentinel,
                       "the existing file must be left untouched")

        let forced = try CLITestHelper.run(
            ["word", "render", script.path, "--to-docx", rebuilt.path, "--force"])
        XCTAssertEqual(forced.exitCode, 0, "--force must overwrite: \(forced.stderr)")
        XCTAssertNotEqual(try Data(contentsOf: rebuilt), sentinel)
    }

    /// Task 1.4 — the CLI face must not deviate from the shared entry point.
    ///
    /// Scope note: a single suite cannot drive both binaries, so this pins
    /// the CLI half — `word render` agrees with `scriptPipelineExecute`
    /// called directly, on both the passing and the failing verdict. The MCP
    /// half is pinned by che-word-mcp's own ScriptPipelineParityTests, which
    /// call the same shared entry point. Together the two ends meet in the
    /// middle at the one implementation.
    func testCLIAgreesWithSharedEntryPointOnBothVerdicts() throws {
        let dir = try makeTempDir()
        let source = dir.appendingPathComponent("source.docx")
        let other = dir.appendingPathComponent("other.docx")
        try makeSyntheticDocx(at: source, text: "原始內容。")
        try makeSyntheticDocx(at: other, text: "完全不同的內容。")
        let script = dir.appendingPathComponent("source.mdocx.swift")
        _ = try CLITestHelper.run(["word", "reverse", source.path, "--to-mdocx", script.path])

        // Matching reference: shared API says verified, CLI must exit 0.
        let direct = try scriptPipelineExecute(
            scriptPath: script.path,
            outputPath: dir.appendingPathComponent("direct.docx").path,
            verifyAgainst: source.path)
        let viaCLI = try CLITestHelper.run(
            ["word", "render", script.path,
             "--to-docx", dir.appendingPathComponent("cli.docx").path,
             "--verify-against", source.path])
        XCTAssertEqual(direct.verified, true)
        XCTAssertEqual(viaCLI.exitCode, 0, "CLI must agree with the shared verdict")

        // Diverging reference: shared API names broken parts, CLI must fail
        // and name the same parts.
        let directBad = try scriptPipelineExecute(
            scriptPath: script.path,
            outputPath: dir.appendingPathComponent("direct-bad.docx").path,
            verifyAgainst: other.path)
        let viaCLIBad = try CLITestHelper.run(
            ["word", "render", script.path,
             "--to-docx", dir.appendingPathComponent("cli-bad.docx").path,
             "--verify-against", other.path])
        XCTAssertEqual(directBad.verified, false)
        XCTAssertNotEqual(viaCLIBad.exitCode, 0, "CLI must agree with the failing verdict")
        XCTAssertFalse(directBad.brokenParts.isEmpty)
        for part in directBad.brokenParts {
            XCTAssertTrue(viaCLIBad.stderr.contains(part),
                          "CLI must name the same broken part '\(part)': \(viaCLIBad.stderr)")
        }
    }

    // MARK: - Failed verification publishes nothing (change
    // `script-pipeline-failure-contract`, task 4.2; che-word-mcp#181)

    /// A failing verdict must leave a pre-existing output file untouched AND
    /// must not announce a write. The old command wrote to the output path
    /// first, printed "已寫入", and only then reported the failure — so the
    /// operator was told a document had been written over one that was, in
    /// fact, destroyed.
    func testFailedVerificationLeavesExistingOutputUnmodifiedAndAnnouncesNoWrite() throws {
        let dir = try makeTempDir()
        let source = dir.appendingPathComponent("source.docx")
        let other = dir.appendingPathComponent("other.docx")
        try makeSyntheticDocx(at: source, text: "原始內容。")
        try makeSyntheticDocx(at: other, text: "完全不同的內容。")
        let script = dir.appendingPathComponent("source.mdocx.swift")
        _ = try CLITestHelper.run(["word", "reverse", source.path, "--to-mdocx", script.path])

        // A document already sitting at the output path.
        let output = dir.appendingPathComponent("out.docx")
        try makeSyntheticDocx(at: output, text: "先前就在輸出路徑上的文件。")
        let before = try Data(contentsOf: output)

        let result = try CLITestHelper.run(
            ["word", "render", script.path,
             "--to-docx", output.path,
             "--verify-against", other.path,
             "--force"])

        XCTAssertNotEqual(result.exitCode, 0, "a mismatch must not exit 0")
        XCTAssertEqual(try Data(contentsOf: output), before,
                       "a failed verification must leave the existing file untouched")
        XCTAssertFalse(result.stderr.contains("已寫入"),
                       "no write may be announced when none happened: \(result.stderr)")
    }

    /// A failing verdict must not create a file where none existed.
    func testFailedVerificationCreatesNoOutputFile() throws {
        let dir = try makeTempDir()
        let source = dir.appendingPathComponent("source.docx")
        let other = dir.appendingPathComponent("other.docx")
        try makeSyntheticDocx(at: source, text: "原始內容。")
        try makeSyntheticDocx(at: other, text: "完全不同的內容。")
        let script = dir.appendingPathComponent("source.mdocx.swift")
        _ = try CLITestHelper.run(["word", "reverse", source.path, "--to-mdocx", script.path])
        let output = dir.appendingPathComponent("out.docx")

        let result = try CLITestHelper.run(
            ["word", "render", script.path,
             "--to-docx", output.path,
             "--verify-against", other.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path),
                       "a failed verification must publish nothing")
    }

    /// The announced path is the path, not a debug rendering of an Optional.
    /// `written` became optional in the shared entry point; interpolating it
    /// directly still COMPILES and prints `Optional("…")`, so only a test on
    /// the actual output catches the regression.
    func testAnnouncedWritePathIsNotAnOptionalDescription() throws {
        let dir = try makeTempDir()
        let source = dir.appendingPathComponent("source.docx")
        try makeSyntheticDocx(at: source)
        let script = dir.appendingPathComponent("source.mdocx.swift")
        _ = try CLITestHelper.run(["word", "reverse", source.path, "--to-mdocx", script.path])
        let output = dir.appendingPathComponent("out.docx")

        let result = try CLITestHelper.run(
            ["word", "render", script.path, "--to-docx", output.path])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertFalse(result.stderr.contains("Optional("),
                       "the written path must be unwrapped: \(result.stderr)")
        XCTAssertTrue(result.stderr.contains(output.path),
                      "the announced path must be the output path: \(result.stderr)")
    }

    /// Task 2.5 — the raw-channel case. A table-bearing real form reports
    /// 0.0% DSL coverage, so the byte-equal floor rests entirely on the raw
    /// channel. If raw replay ever regressed, this is what would catch it.
    func testRawChannelDocumentStillRoundTripsByteEqual() throws {
        guard let fixture = Self.tableFixture() else {
            throw XCTSkip("no table-bearing .docx fixture available")
        }
        let dir = try makeTempDir()
        let script = dir.appendingPathComponent("form.mdocx.swift")
        let reversed = try CLITestHelper.run(
            ["word", "reverse", fixture.path, "--to-mdocx", script.path, "--coverage"])
        XCTAssertEqual(reversed.exitCode, 0, "reverse must succeed: \(reversed.stderr)")
        XCTAssertTrue(reversed.stderr.contains("0.0% DSL") || reversed.stdout.contains("0.0% DSL"),
                      "fixture is expected to be a raw-channel document")

        let rebuilt = dir.appendingPathComponent("rebuilt.docx")
        let result = try CLITestHelper.run(
            ["word", "render", script.path,
             "--to-docx", rebuilt.path,
             "--verify-against", fixture.path])
        XCTAssertEqual(result.exitCode, 0,
                       "a fully raw script must still replay byte-equally: \(result.stderr)")
    }

    /// Mirrors the fixture-detection pattern used by the `.note` smoke tests:
    /// skip rather than fail when the fixture is absent, so a clean clone is
    /// not broken by a file that is deliberately not in version control.
    private static func tableFixture() -> URL? {
        let candidates = [
            CLITestHelper.repoRoot.appendingPathComponent("test-files"),
        ]
        for dir in candidates {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { continue }
            for item in items where item.pathExtension.lowercased() == "docx" {
                if let parts = try? RawPartChannel.readAllParts(from: item),
                   let doc = parts["word/document.xml"],
                   String(decoding: doc, as: UTF8.self).contains("<w:tbl>") {
                    return item
                }
            }
        }
        return nil
    }
}
