import Foundation
import XCTest

/// CLI 執行結果
struct CLIResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
}

/// CLI 測試輔助工具
enum CLITestHelper {

    /// macdoc binary 路徑
    static var binaryPath: String {
        // 先找 release，再找 debug
        let releaseURL = repoRoot.appendingPathComponent(".build/release/macdoc")
        if FileManager.default.fileExists(atPath: releaseURL.path) {
            return releaseURL.path
        }
        return repoRoot.appendingPathComponent(".build/debug/macdoc").path
    }

    /// repo 根目錄（從 Tests/MacDocCLITests/ 往上兩層）
    static var repoRoot: URL {
        // #file 在 Tests/MacDocCLITests/CLITestHelper.swift
        // 往上 3 層 = repo root
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // MacDocCLITests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repo root
    }

    /// 執行 macdoc 指令
    static func run(
        _ arguments: [String],
        timeout: TimeInterval = 30,
        environment: [String: String]? = nil
    ) throws -> CLIResult {
        try runProcess(
            executableURL: URL(fileURLWithPath: binaryPath),
            arguments: arguments,
            currentDirectory: repoRoot,
            timeout: timeout,
            environment: environment)
    }

    /// Runs an arbitrary executable with a timeout, returning its captured
    /// output. Extracted from `run` so the timeout path is testable against a
    /// deterministically-slow command (macdoc#133).
    static func runProcess(
        executableURL: URL,
        arguments: [String],
        currentDirectory: URL?,
        timeout: TimeInterval,
        environment: [String: String]? = nil
    ) throws -> CLIResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(
                environment,
                uniquingKeysWith: { _, override in override }
            )
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Timeout 保護
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }

        // Drain the pipes first (readDataToEndOfFile blocks until the write
        // ends close on process death), THEN reap the child. Draining before
        // waitUntilExit avoids the classic deadlock where the child blocks on
        // a full pipe while we block on wait — though it is not absolute: a
        // child that ignores SIGTERM, or grandchildren inheriting the pipe
        // FDs, can still keep it open (a general pipe-capture limitation, not
        // specific to the timeout path).
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        // macdoc#133: terminate() only sends SIGTERM (async). Reading
        // terminationStatus before the process is reaped throws
        // NSInvalidArgumentException ("task still running") and crashes the
        // whole test process. waitUntilExit() reaps it — safe on both the
        // normal-exit and the timeout-terminate paths.
        process.waitUntilExit()

        return CLIResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    /// 執行 macdoc convert 指令
    static func convert(
        to format: String,
        input: String,
        flags: [String] = [],
        environment: [String: String]? = nil
    ) throws -> CLIResult {
        var args = ["convert", "--to", format] + flags + [input]
        return try run(args, environment: environment)
    }

    /// 取得 .note 測試 fixture 的絕對路徑。若 repo 內無可用樣本則 XCTSkip。
    ///
    /// Resolution order (per PsychQuant/macdoc#100 verify fix 2026-06-01):
    /// 1. Tests/MacDocCLITests/Fixtures/mini.note (curated committable)
    /// 2. test-files/*.note (rich developer fixture — preferred when present
    ///    so strict NoteHTMLConvertTests assertions exercise real content)
    /// 3. Freshly synthesized via NoteFixtureGenerator (synthetic content;
    ///    regenerated every call — no cache, since stale-cache bugs were the
    ///    #100 verify P1 finding)
    /// 4. XCTSkip (only if all of the above fail — should be rare)
    ///
    /// Why prefer test-files over synthetic: the strict assertions in
    /// `NoteHTMLConvertTests.testNoteToHTMLSmoke` (`>750KB index.html` +
    /// `media/ >= 1 asset`) calibrated against rich content per #81 only
    /// fire when the fixture has actual recordings/images. Cache + synthetic
    /// silently masked test-files in the initial #100 implementation; this
    /// order prevents that regression. Synthetic remains the CI fallback so
    /// repos without a local fixture still run the smoke tests (with
    /// fixture-type-aware structural assertions).
    static func noteFixture(file: StaticString = #filePath, line: UInt = #line) throws -> URL {
        // 1. Pre-generated committable fixture (if present)
        let committedFixture = repoRoot.appendingPathComponent(
            "Tests/MacDocCLITests/Fixtures/mini.note"
        )
        if FileManager.default.fileExists(atPath: committedFixture.path) {
            return committedFixture
        }

        // 2. Rich developer fixture — gitignored local samples per #81.
        //    Prefer this over synthetic so strict assertions exercise real
        //    content when a developer has it locally.
        let candidates = [
            "test-files/筆記 2026-03-20 15_25_20.note",
        ]
        for relativePath in candidates {
            let url = repoRoot.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        let fallbackDir = repoRoot.appendingPathComponent("test-files")
        if FileManager.default.fileExists(atPath: fallbackDir.path) {
            let contents = try FileManager.default.contentsOfDirectory(
                at: fallbackDir, includingPropertiesForKeys: nil
            )
            let noteFiles = contents
                .filter { $0.pathExtension.lowercased() == "note" }
                .sorted(by: { $0.path < $1.path })
            if let found = noteFiles.first {
                return found
            }
        }

        // 3. Freshly synthesized — regenerate every call. Generator is fast
        //    (~ms), so the no-cache strategy avoids the stale-cache bugs
        //    flagged in #100's first-round verify (P1). The output URL uses
        //    a UUID per invocation so concurrent test processes don't race.
        let freshURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdoc-synthetic-fixture-\(UUID().uuidString).note")
        do {
            try NoteFixtureGenerator.generate(at: freshURL)
            return freshURL
        } catch {
            // Generator failure is unexpected — surface clearly. Don't silently
            // skip; raise via XCTSkip with the underlying error in the message.
            throw XCTSkip(
                "NoteFixtureGenerator failed: \(error). No .note fixture available. See PsychQuant/macdoc#100.",
                file: file, line: line
            )
        }
    }
}
