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
    /// Phase 1 走 Option B（per #81 diagnosis）：使用 `test-files/*.note` 樣本。
    /// Clean clone 或 CI 上若無該檔案，測試會被跳過而非失敗 —
    /// 未來 follow-up 會改成 committable 小 fixture。
    static func noteFixture(file: StaticString = #filePath, line: UInt = #line) throws -> URL {
        let candidates = [
            "test-files/筆記 2026-03-20 15_25_20.note",
        ]

        for relativePath in candidates {
            let url = repoRoot.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        // Fallback: any .note under test-files/. Sort by path to make the pick
        // deterministic across machines (per logic-review P1: contentsOfDirectory
        // has undefined order). Distinguish "directory missing" from real I/O
        // errors so XCTSkip only fires when the directory genuinely isn't there.
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

        throw XCTSkip(
            "No .note fixture found under test-files/. Place a sample .note there to enable Note → PDF/HTML smoke tests. See issue #79 for a committable-fixture follow-up.",
            file: file, line: line
        )
    }
}
