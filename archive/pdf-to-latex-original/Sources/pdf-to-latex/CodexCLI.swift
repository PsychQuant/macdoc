import Foundation

struct CodexTranscriptionResult: Codable, Sendable {
    var latex: String
    var confidence: Double?
    var needsFallback: Bool
    var notes: String?
}

enum CodexCLIError: LocalizedError {
    case executableNotFound
    case failed(Int32, String)
    case invalidResponse(String)
    case timedOut(Double)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "找不到 codex CLI。請先確認 `codex` 已安裝且可在 PATH 中使用。"
        case .failed(let code, let output):
            return "codex exec 失敗，exit code \(code): \(output)"
        case .invalidResponse(let output):
            return "codex exec 回傳內容無法解析: \(output)"
        case .timedOut(let seconds):
            return "codex exec 超時，超過 \(Int(seconds)) 秒仍未完成。"
        }
    }
}

struct CodexCLI: Sendable {
    func transcribeBlock(
        projectRoot: URL,
        block: BlockRecord,
        model: String,
        prompt: String,
        schemaURL: URL,
        outputURL: URL,
        timeoutSeconds: Double
    ) throws -> CodexTranscriptionResult {
        guard let imagePath = block.imagePath else {
            throw CodexCLIError.invalidResponse("block 沒有 imagePath: \(block.id)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "codex",
            "exec",
            "-C", projectRoot.path,
            "--skip-git-repo-check",
            "--color", "never",
            "--json",
            "-s", "read-only",
            "-c", "model_reasoning_effort=\"low\"",
            "-m", model,
            "-i", imagePath,
            "--output-schema", schemaURL.path,
            "-o", outputURL.path,
            "-"
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        do {
            try process.run()
        } catch {
            throw CodexCLIError.executableNotFound
        }

        if let promptData = prompt.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(promptData)
        }
        try? stdinPipe.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }

        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.5)
            throw CodexCLIError.timedOut(timeoutSeconds)
        }

        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let combinedOutput = ([stdout, stderr].filter { !$0.isEmpty }).joined(separator: "\n")

        guard process.terminationStatus == 0 else {
            throw CodexCLIError.failed(process.terminationStatus, combinedOutput)
        }

        let data = try Data(contentsOf: outputURL)
        do {
            return try JSONDecoder().decode(CodexTranscriptionResult.self, from: data)
        } catch {
            throw CodexCLIError.invalidResponse(String(data: data, encoding: .utf8) ?? combinedOutput)
        }
    }

    func writeSchema(to url: URL) throws {
        let schema = """
        {
          "type": "object",
          "properties": {
            "latex": { "type": "string" },
            "confidence": { "type": ["number", "null"] },
            "needsFallback": { "type": "boolean" },
            "notes": { "type": ["string", "null"] }
          },
          "required": ["latex", "confidence", "needsFallback", "notes"],
          "additionalProperties": false
        }
        """
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try schema.write(to: url, atomically: true, encoding: .utf8)
    }
}
