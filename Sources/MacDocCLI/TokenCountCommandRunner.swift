import Darwin
import Foundation
import TokenCounter

enum TokenCountCommandError: Error, LocalizedError, Sendable {
    case unsupportedModel(String)
    case networkConsentRequired
    case missingAnthropicAPIKey
    case inputIsNotRegularFile
    case inputTooLarge(limit: Int)
    case invalidUTF8
    case invalidProviderResult

    var errorDescription: String? {
        switch self {
        case .unsupportedModel:
            "不支援的 token model；可用值：gpt-4o、claude-sonnet-4-6"
        case .networkConsentRequired:
            "Claude token 計數會傳送完整輸入內容；請明確加入 --allow-network"
        case .missingAnthropicAPIKey:
            "Claude token 計數需要非空的 ANTHROPIC_API_KEY"
        case .inputIsNotRegularFile:
            "token 計數只接受一般檔案"
        case let .inputTooLarge(limit):
            "token 計數輸入不得超過 \(limit) UTF-8 bytes"
        case .invalidUTF8:
            "token 計數輸入必須是有效 UTF-8"
        case .invalidProviderResult:
            "token provider 回傳的 model、順序或數值無效"
        }
    }
}

struct TokenCountCommandRunner: Sendable {
    typealias EnvironmentReader = @Sendable (String) -> String?
    typealias CountOperation = @Sendable (
        _ text: String,
        _ models: [TokenModel],
        _ anthropicAPIKey: String?
    ) async throws -> [TokenCount]

    static let inputByteLimit = 1_000_000

    static let live = TokenCountCommandRunner(
        environment: { ProcessInfo.processInfo.environment[$0] },
        count: { text, models, apiKey in
            let service = try TokenCounterService(anthropicAPIKey: apiKey)
            return try await service.count(text: text, models: models)
        }
    )

    private let environment: EnvironmentReader
    private let count: CountOperation

    struct InvocationResult: Equatable, Sendable {
        let exitCode: Int32
        let stdout: Data
        let stderr: Data
    }

    init(
        environment: @escaping EnvironmentReader,
        count: @escaping CountOperation
    ) {
        self.environment = environment
        self.count = count
    }

    func render(
        inputURL: URL,
        modelName: String?,
        allowNetwork: Bool
    ) async throws -> String {
        let models: [TokenModel]
        if let modelName {
            guard let model = TokenModel(rawValue: modelName) else {
                throw TokenCountCommandError.unsupportedModel(modelName)
            }
            models = [model]
        } else {
            models = [.gpt4o, .claudeSonnet46]
        }

        let includesAnthropic = models.contains(.claudeSonnet46)
        var apiKey: String?
        if includesAnthropic {
            guard allowNetwork else {
                throw TokenCountCommandError.networkConsentRequired
            }
            let configured = environment("ANTHROPIC_API_KEY")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let configured, !configured.isEmpty else {
                throw TokenCountCommandError.missingAnthropicAPIKey
            }
            apiKey = configured
        }

        let text = try Self.readAdmittedText(from: inputURL)
        let results = try await count(text, models, apiKey)
        try Task.checkCancellation()
        guard results.count == models.count,
              results.map(\.model) == models,
              results.allSatisfy({ $0.tokens >= 0 })
        else {
            throw TokenCountCommandError.invalidProviderResult
        }

        if results.count == 1, let result = results.first {
            return "\(result.tokens)\n"
        }

        var output = "Model\tTokens\n"
        for result in results {
            output += "\(result.model.rawValue)\t\(result.tokens)\n"
        }
        return output
    }

    func execute(
        inputURL: URL,
        modelName: String?,
        allowNetwork: Bool,
        outputURL: URL?,
        stdout: (Data) throws -> Void,
        stderr: (Data) throws -> Void
    ) async throws {
        let rendered = try await render(
            inputURL: inputURL,
            modelName: modelName,
            allowNetwork: allowNetwork
        )
        try Task.checkCancellation()
        let data = Data(rendered.utf8)
        if let outputURL {
            try data.write(to: outputURL, options: .atomic)
            try stderr(Data("已寫入: \(outputURL.path)\n".utf8))
        } else {
            try stdout(data)
        }
    }

    func invoke(
        inputURL: URL,
        modelName: String?,
        allowNetwork: Bool,
        outputURL: URL?
    ) async -> InvocationResult {
        let output = SynchronizedDataBuffer()
        let diagnostics = SynchronizedDataBuffer()
        do {
            try await execute(
                inputURL: inputURL,
                modelName: modelName,
                allowNetwork: allowNetwork,
                outputURL: outputURL,
                stdout: { output.append($0) },
                stderr: { diagnostics.append($0) }
            )
            return InvocationResult(
                exitCode: 0,
                stdout: output.snapshot,
                stderr: diagnostics.snapshot
            )
        } catch {
            let description = (error as? LocalizedError)?.errorDescription
                ?? String(describing: error)
            diagnostics.append(Data("Error: \(description)\n".utf8))
            return InvocationResult(
                exitCode: 1,
                stdout: output.snapshot,
                stderr: diagnostics.snapshot
            )
        }
    }

    static func readAdmittedText(
        from url: URL,
        afterOpen: () throws -> Void = {}
    ) throws -> String {
        // Open first and keep this descriptor as the single identity for
        // validation and reading. O_NOFOLLOW prevents a final-entry symlink;
        // O_NONBLOCK prevents a FIFO from blocking before fstat rejects it.
        let descriptor = Darwin.open(
            url.path,
            O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            throw TokenCountCommandError.inputIsNotRegularFile
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }

        try afterOpen()

        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG
        else {
            throw TokenCountCommandError.inputIsNotRegularFile
        }
        if metadata.st_size > inputByteLimit {
            throw TokenCountCommandError.inputTooLarge(limit: inputByteLimit)
        }

        var data = Data()
        while data.count <= inputByteLimit {
            let remaining = inputByteLimit + 1 - data.count
            guard let chunk = try handle.read(upToCount: min(65_536, remaining)),
                  !chunk.isEmpty
            else {
                break
            }
            data.append(chunk)
        }
        guard data.count <= inputByteLimit else {
            throw TokenCountCommandError.inputTooLarge(limit: inputByteLimit)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw TokenCountCommandError.invalidUTF8
        }
        return text
    }
}

private final class SynchronizedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.withLock { data.append(chunk) }
    }

    var snapshot: Data {
        lock.withLock { data }
    }
}
