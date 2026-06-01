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
    static func run(_ arguments: [String], timeout: TimeInterval = 30) throws -> CLIResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments
        process.currentDirectoryURL = repoRoot

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

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return CLIResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    /// 執行 macdoc convert 指令
    static func convert(to format: String, input: String, flags: [String] = []) throws -> CLIResult {
        var args = ["convert", "--to", format] + flags + [input]
        return try run(args)
    }

    /// 取得 .note 測試 fixture 的絕對路徑。若 repo 內無可用樣本則 XCTSkip。
    ///
    /// Resolution order (per PsychQuant/macdoc#100 Plan-tier delivery):
    /// 1. Tests/MacDocCLITests/Fixtures/mini.note (if committed pre-generated)
    /// 2. Synthesized via NoteFixtureGenerator (synthetic content, zero PII)
    /// 3. test-files/*.note (gitignored local samples — Phase 1 #81 path)
    /// 4. XCTSkip (only if all of the above fail)
    static func noteFixture(file: StaticString = #filePath, line: UInt = #line) throws -> URL {
        // 1. Pre-generated committable fixture (if present)
        let committedFixture = repoRoot.appendingPathComponent(
            "Tests/MacDocCLITests/Fixtures/mini.note"
        )
        if FileManager.default.fileExists(atPath: committedFixture.path) {
            return committedFixture
        }

        // 2. Synthesized via NoteFixtureGenerator — synthetic content, no PII.
        //    Cached in temp dir so repeated calls within a test run reuse the
        //    same generated file. The temp dir is cleaned up by macOS on reboot.
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdoc-note-fixture-cache")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let cachedFixture = cacheDir.appendingPathComponent("synthetic-fixture.note")
        if !FileManager.default.fileExists(atPath: cachedFixture.path) {
            do {
                try NoteFixtureGenerator.generate(at: cachedFixture)
            } catch {
                // Fall through to legacy path if generator fails.
                // Errors logged so CI surfaces the failure without skipping tests outright.
                FileHandle.standardError.write(Data(
                    "[CLITestHelper] NoteFixtureGenerator failed: \(error); falling back to test-files/*.note\n".utf8
                ))
            }
        }
        if FileManager.default.fileExists(atPath: cachedFixture.path) {
            return cachedFixture
        }

        // 3. Legacy path: test-files/*.note (gitignored local samples per #81).
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

        // 4. Genuine XCTSkip — generator + legacy paths both failed.
        throw XCTSkip(
            "No .note fixture available (generator + test-files both failed). See PsychQuant/macdoc#100.",
            file: file, line: line
        )
    }
}
