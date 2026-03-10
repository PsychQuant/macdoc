import Foundation

struct TranscriptionOutcome: Sendable {
    var blockID: String
    var status: BlockStatus
    var snippetPath: String?
    var notes: String?
}

enum TranscriptionWorker {
    static func run(
        block: BlockRecord,
        projectRoot: URL,
        model: String,
        timeoutSeconds: Double,
        schemaURL: URL
    ) -> TranscriptionOutcome {
        let prompt = TranscriptionPromptBuilder.build(for: block)
        let responseURL = projectRoot
            .appendingPathComponent("tmp/codex-responses", isDirectory: true)
            .appendingPathComponent("\(block.id).json")
        let snippetURL = projectRoot
            .appendingPathComponent("snippets", isDirectory: true)
            .appendingPathComponent(String(format: "page-%04d", block.page), isDirectory: true)
            .appendingPathComponent("\(block.id).tex")

        do {
            let result = try CodexCLI().transcribeBlock(
                projectRoot: projectRoot,
                block: block,
                model: model,
                prompt: prompt,
                schemaURL: schemaURL,
                outputURL: responseURL,
                timeoutSeconds: timeoutSeconds
            )
            try FileManager.default.createDirectory(at: snippetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try result.latex.write(to: snippetURL, atomically: true, encoding: .utf8)

            return TranscriptionOutcome(
                blockID: block.id,
                status: result.needsFallback ? .fallbackImage : .transcribed,
                snippetPath: snippetURL.path,
                notes: result.notes
            )
        } catch {
            return TranscriptionOutcome(
                blockID: block.id,
                status: .failed,
                snippetPath: nil,
                notes: error.localizedDescription
            )
        }
    }
}
