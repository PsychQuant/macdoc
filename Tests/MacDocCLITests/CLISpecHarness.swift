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

    static let recordEnvironmentKey = "MACDOC_RECORD_CLI_SPEC"

    /// Record mode is on only for the exact value `1`.
    static func isRecordMode(_ environment: [String: String]) -> Bool {
        environment[recordEnvironmentKey] == "1"
    }

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
        let dump = try runDraining(binary, ["--experimental-dump-help"])
        let version = try runDraining(binary, ["--version"])
        return Inputs(dumpHelpJSON: dump, versionOutput: String(decoding: version, as: UTF8.self))
    }

    /// Runs the binary and returns its stdout bytes, failing on a non-zero
    /// exit. Unlike `CLITestHelper.runProcess` — which waits for the child to
    /// exit before draining its pipes, so a child writing more than one pipe
    /// buffer (the dump is ~180 KB) blocks until the timeout kills it — this
    /// drains stdout and stderr while the child runs.
    private static func runDraining(_ binary: URL, _ arguments: [String], timeout: TimeInterval = 120) throws -> Data {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.currentDirectoryURL = CLITestHelper.repoRoot
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()

        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        let stderrBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            stderrBox.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationStatus == 0 else {
            throw HarnessError.commandFailed(
                arguments.joined(separator: " "), process.terminationStatus,
                String(decoding: stderrBox.data, as: UTF8.self))
        }
        return stdout
    }

    private final class DataBox: @unchecked Sendable {
        var data = Data()
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
