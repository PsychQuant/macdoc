import Foundation

enum TexCompilerError: LocalizedError {
    case latexmkFailed(Int32, String)

    var errorDescription: String? {
        switch self {
        case .latexmkFailed(let code, let output):
            return "latexmk 編譯失敗，exit code \(code): \(output)"
        }
    }
}

struct TexCompiler {
    func compile(mainTexURL: URL) throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = mainTexURL.deletingLastPathComponent()
        process.arguments = [
            "latexmk",
            "-pdf",
            "-interaction=nonstopmode",
            "-halt-on-error",
            "-file-line-error",
            "-outdir=build",
            mainTexURL.lastPathComponent,
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let combined = ([stdout, stderr].filter { !$0.isEmpty }).joined(separator: "\n")

        guard process.terminationStatus == 0 else {
            throw TexCompilerError.latexmkFailed(process.terminationStatus, combined)
        }

        return mainTexURL
            .deletingLastPathComponent()
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent(mainTexURL.deletingPathExtension().lastPathComponent + ".pdf")
    }
}
