import Foundation
import CLISpec

/// Test-side entry point to `CLISpecGenerator` (PsychQuant/macdoc#72): runs the
/// built `macdoc` binary for its `--experimental-dump-help` JSON and its
/// `--version` string, then calls the one shared transform in the `CLISpec`
/// target. The drift test uses it to compare with — or, in record mode, to
/// rewrite — the committed `cli-spec.yaml`; `make cli-spec` is that test in
/// record mode. There is no second copy of the transform anywhere.
enum CLISpecHarness {

    /// The committed specification at the repository root.
    static var specURL: URL {
        CLITestHelper.repoRoot.appendingPathComponent("cli-spec.yaml")
    }

    /// Set only by `make cli-spec`, for that one `swift test` invocation. It
    /// is not a documented switch: recording is done with `make cli-spec`.
    static let recordEnvironmentKey = "MACDOC_RECORD_CLI_SPEC"

    enum RecordDecision: Equatable, Sendable {
        /// Compare the committed file with a fresh generation.
        case compare
        /// Rewrite the committed file (`make cli-spec`).
        case record
        /// Record mode was requested under CI, where a rewrite would turn the
        /// drift check into a silent pass.
        case refusedUnderCI
    }

    /// Record mode requires the exact value `1`, and is refused whenever the
    /// `CI` variable is present (with any value) so that an inherited
    /// `MACDOC_RECORD_CLI_SPEC=1` cannot disable the drift check in CI.
    static func recordDecision(_ environment: [String: String]) -> RecordDecision {
        guard environment[recordEnvironmentKey] == "1" else { return .compare }
        return environment["CI"] == nil ? .record : .refusedUnderCI
    }

    static let ciRefusalMessage = """
    MACDOC_RECORD_CLI_SPEC=1 在 CI 環境（CI 已設定）中被拒絕：CI 只做漂移比對，不得改寫 cli-spec.yaml。\
    請在本機執行 make cli-spec 重新產生並提交；若是從外層環境繼承了 MACDOC_RECORD_CLI_SPEC，請移除它。
    """

    struct Inputs {
        let dumpHelpJSON: Data
        let versionOutput: String
    }

    /// Reads both inputs from the binary once per test process.
    static func inputs() throws -> Inputs {
        try cachedInputs.get()
    }

    private static let cachedInputs = Result<Inputs, Error> {
        let binary = URL(fileURLWithPath: try CLITestHelper.binaryPath)
        let dump = try runCapturingFiles(binary, ["--experimental-dump-help"])
        let version = try runCapturingFiles(binary, ["--version"])
        return Inputs(dumpHelpJSON: dump, versionOutput: String(decoding: version, as: UTF8.self))
    }

    /// Runs the binary and returns its stdout bytes, failing on a non-zero
    /// exit.
    ///
    /// This used to go through temporary files instead of `CLITestHelper
    /// .runProcess`, for two reasons; neither still applies. `runProcess`
    /// used to wait for the child to exit before draining its pipes, so a
    /// child writing more than one pipe buffer (the dump is ~180 KB)
    /// blocked until the timeout killed it — fixed as of macdoc#219 (pipes
    /// are now drained concurrently while the process runs). And a pipe's
    /// EOF used to also wait for any concurrently spawned test process that
    /// inherited its write end (observed as a ~30s stall while the route
    /// probe ran in parallel) — fixed as of macdoc#224 (`runProcess` now
    /// creates its pipes `FD_CLOEXEC` under a lock spanning pipe creation
    /// through `process.run()`, so no concurrently spawned process can pick
    /// them up). Both reasons this harness avoided `runProcess` are gone,
    /// so it now shares the one drain/timeout/FD-safety implementation
    /// instead of carrying a second, narrower one.
    private static func runCapturingFiles(_ binary: URL, _ arguments: [String], timeout: TimeInterval = 120) throws -> Data {
        let result = try CLITestHelper.runProcess(
            executableURL: binary,
            arguments: arguments,
            currentDirectory: CLITestHelper.repoRoot,
            timeout: timeout)
        guard result.exitCode == 0 else {
            throw HarnessError.commandFailed(
                arguments.joined(separator: " "), result.exitCode, result.stderr)
        }
        // `runProcess` decodes stdout as UTF-8 (empty string on failure)
        // rather than handing back raw bytes; `--experimental-dump-help`'s
        // JSON and `--version`'s text are always valid UTF-8, so this
        // round-trip is lossless for this harness's actual inputs.
        return Data(result.stdout.utf8)
    }

    /// The full `cli-spec.yaml` text for the current binary and overlay.
    static func generate() throws -> String {
        let inputs = try inputs()
        return try CLISpecGenerator.generate(
            dumpHelpJSON: inputs.dumpHelpJSON,
            versionOutput: inputs.versionOutput,
            metadata: MacDocCLIMetadata.overlay
        )
    }

    /// The document model behind `generate()`, for structural assertions.
    static func document() throws -> CLISpecDocument {
        let inputs = try inputs()
        return try CLISpecBuilder.build(
            dumpHelpJSON: inputs.dumpHelpJSON,
            versionOutput: inputs.versionOutput,
            metadata: MacDocCLIMetadata.overlay
        )
    }

    /// `nil` when the bytes are equal; otherwise a report naming the first
    /// differing line (1-based), both line contents, and the fix.
    static func driftReport(committed: Data, generated: Data) -> String? {
        guard committed != generated else { return nil }
        let committedLines = String(decoding: committed, as: UTF8.self).components(separatedBy: "\n")
        let generatedLines = String(decoding: generated, as: UTF8.self).components(separatedBy: "\n")
        var lineNumber = 0
        for index in 0..<max(committedLines.count, generatedLines.count) {
            let lhs = index < committedLines.count ? Array(committedLines[index].utf8) : nil
            let rhs = index < generatedLines.count ? Array(generatedLines[index].utf8) : nil
            if lhs != rhs {
                lineNumber = index + 1
                break
            }
        }
        guard lineNumber > 0 else {
            // Only reachable when invalid UTF-8 decodes to identical lines.
            return "cli-spec.yaml 與目前程式碼產生的結果位元組不同（逐行解碼後相同，可能含無效 UTF-8）。請執行 make cli-spec 重新產生 cli-spec.yaml 並提交。"
        }
        func show(_ lines: [String]) -> String {
            lineNumber - 1 < lines.count ? lines[lineNumber - 1] : "(檔案結束)"
        }
        return """
        cli-spec.yaml 與目前程式碼產生的結果不一致：第 \(lineNumber) 行（line \(lineNumber)）不同。
          committed: \(show(committedLines))
          generated: \(show(generatedLines))
        請執行 make cli-spec 重新產生 cli-spec.yaml 並提交。
        """
    }

    enum HarnessError: Error, CustomStringConvertible {
        case commandFailed(String, Int32, String)

        var description: String {
            switch self {
            case .commandFailed(let arguments, let status, let stderr):
                return "macdoc \(arguments) 失敗（exit \(status)）：\(stderr)"
            }
        }
    }
}
