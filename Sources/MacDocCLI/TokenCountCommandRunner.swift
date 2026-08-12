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

    private static func readAdmittedText(from url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileSizeKey,
        ])
        guard values.isRegularFile == true else {
            throw TokenCountCommandError.inputIsNotRegularFile
        }
        if let fileSize = values.fileSize, fileSize > inputByteLimit {
            throw TokenCountCommandError.inputTooLarge(limit: inputByteLimit)
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
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
