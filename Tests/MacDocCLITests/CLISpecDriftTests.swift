import Testing
import Foundation
import CLISpec

/// Drift contract for the committed `cli-spec.yaml` (Spectra change
/// `cli-spec-yaml`, requirement "Drift contract for the committed
/// specification"; PsychQuant/macdoc#72).
///
/// Compares the committed file byte-for-byte with a fresh generation from the
/// built binary. With `MACDOC_RECORD_CLI_SPEC=1` it rewrites the file instead
/// — that is exactly what `make cli-spec` runs.
struct CLISpecDriftTests {

    @Test("committed cli-spec.yaml equals a fresh generation (record mode rewrites it)")
    func committedSpecIsFresh() throws {
        let generated = Data(try CLISpecHarness.generate().utf8)
        let url = CLISpecHarness.specURL

        if CLISpecHarness.isRecordMode(ProcessInfo.processInfo.environment) {
            try generated.write(to: url, options: .atomic)
            print("[cli-spec] recorded \(url.path) (\(generated.count) bytes)")
            return
        }

        let committed = try #require(
            FileManager.default.contents(atPath: url.path),
            "找不到 \(url.path)；請執行 make cli-spec 產生並提交。"
        )
        let report = CLISpecHarness.driftReport(committed: committed, generated: generated)
        #expect(report == nil, Comment(rawValue: report ?? ""))
    }

    @Test("record mode is on only for the exact value 1", arguments: [
        ([String: String](), false),
        (["MACDOC_RECORD_CLI_SPEC": "1"], true),
        (["MACDOC_RECORD_CLI_SPEC": "true"], false),
        (["MACDOC_RECORD_CLI_SPEC": "0"], false),
    ])
    func recordModeSwitch(environment: [String: String], expected: Bool) {
        #expect(CLISpecHarness.isRecordMode(environment) == expected)
    }

    @Test("a stale line is reported with its number, both contents and the fix")
    func driftReportNamesTheLine() throws {
        let committed = Data("a\nb\nold help\nd\n".utf8)
        let generated = Data("a\nb\nnew help\nd\n".utf8)
        let report = try #require(CLISpecHarness.driftReport(committed: committed, generated: generated))
        #expect(report.contains("第 3 行"))
        #expect(report.contains("old help"))
        #expect(report.contains("new help"))
        #expect(report.contains("make cli-spec"))
        #expect(CLISpecHarness.driftReport(committed: committed, generated: committed) == nil)
    }

    @Test("a missing trailing line and a Unicode-normalization-only change are drift")
    func driftReportEdgeCases() throws {
        let short = try #require(CLISpecHarness.driftReport(
            committed: Data("a\nb\n".utf8), generated: Data("a\nb\nc\n".utf8)))
        #expect(short.contains("第 3 行"))
        // "é" precomposed vs decomposed: equal as Swift Strings, different bytes.
        let composed = Data("caf\u{E9}\n".utf8)
        let decomposed = Data("cafe\u{301}\n".utf8)
        let normalization = try #require(CLISpecHarness.driftReport(committed: composed, generated: decomposed))
        #expect(normalization.contains("第 1 行"))
    }
}
