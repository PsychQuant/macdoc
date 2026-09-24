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
    /// exit. stdout and stderr go to temporary files, not pipes:
    /// `CLITestHelper.runProcess` waits for the child to exit before draining
    /// its pipes, so a child writing more than one pipe buffer (the dump is
    /// ~180 KB) blocks until the timeout kills it; and a pipe's EOF also
    /// waits for any concurrently spawned test process that inherited its
    /// write end (observed as a ~30 s stall while the route probe runs in
    /// parallel). A file has neither problem: read it after the exit.
    private static func runCapturingFiles(_ binary: URL, _ arguments: [String], timeout: TimeInterval = 120) throws -> Data {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdoc-cli-spec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdoutURL = directory.appendingPathComponent("stdout")
        let stderrURL = directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.currentDirectoryURL = CLITestHelper.repoRoot
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let stdout = try Data(contentsOf: stdoutURL)
        guard process.terminationStatus == 0 else {
            let stderr = (try? Data(contentsOf: stderrURL)) ?? Data()
            throw HarnessError.commandFailed(
                arguments.joined(separator: " "), process.terminationStatus,
                String(decoding: stderr, as: UTF8.self))
        }
        return stdout
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
