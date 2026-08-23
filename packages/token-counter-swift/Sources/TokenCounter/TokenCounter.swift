import CryptoKit
import Foundation
import SwiftTiktoken
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum TokenModel: String, CaseIterable, Codable, Sendable {
    case gpt4o = "gpt-4o"
    case claudeSonnet46 = "claude-sonnet-4-6"
}

public struct TokenCount: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case local
        case provider
    }

    public let model: TokenModel
    public let tokens: Int
    public let source: Source

    public init(model: TokenModel, tokens: Int, source: Source) {
        self.model = model
        self.tokens = tokens
        self.source = source
    }
}

public enum TokenCounterError: Error, Equatable, Sendable, LocalizedError {
    case invalidRequest(String)
    case providerUnavailable(TokenModel)
    case invalidTokenCount(TokenModel)
    case resourceIntegrity(expectedSHA256: String, actualSHA256: String)
    case invalidResource
    case tokenizerFailure
    case providerNotImplemented

    public var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "Invalid token-count request."
        case let .providerUnavailable(model):
            "No token-count provider is configured for \(model.rawValue)."
        case let .invalidTokenCount(model):
            "The token-count provider returned an invalid count for \(model.rawValue)."
        case .resourceIntegrity:
            "The bundled tokenizer resource failed its integrity check."
        case .invalidResource:
            "The bundled tokenizer resource is invalid."
        case .tokenizerFailure:
            "The local tokenizer failed."
        case .providerNotImplemented:
            "The token-count provider is not implemented."
        }
    }
}

protocol TokenCountingProvider: Sendable {
    var source: TokenCount.Source { get }
    func count(text: String, model: TokenModel) async throws -> Int
}

public struct TokenCounterService: Sendable {
    private let providers: [TokenModel: any TokenCountingProvider]

    public init(
        anthropicAPIKey: String? = nil,
        anthropicTransport: (any AnthropicTokenCountTransport)? = nil
    ) throws {
        try self.init(
            anthropicAPIKey: anthropicAPIKey,
            anthropicTransport: anthropicTransport,
            openAIResourceLoader: OpenAITokenCounter.bundledResourceLoader
        )
    }

    init(
        anthropicAPIKey: String?,
        anthropicTransport: (any AnthropicTokenCountTransport)?,
        openAIResourceLoader: @escaping OpenAITokenCounter.ResourceLoader
    ) throws {
        var providers: [TokenModel: any TokenCountingProvider] = [
            .gpt4o: OpenAITokenCountingProvider(resourceLoader: openAIResourceLoader),
        ]
        if let anthropicAPIKey, !anthropicAPIKey.isEmpty {
            providers[.claudeSonnet46] = AnthropicTokenCountingProvider(
                apiKey: anthropicAPIKey,
                transport: anthropicTransport ?? AnthropicHTTPTokenCountTransport(
                    loader: URLSessionAnthropicHTTPDataLoader()
                )
            )
        }
        self.providers = providers
    }

    init(providers: [TokenModel: any TokenCountingProvider]) {
        self.providers = providers
    }

    public func count(text: String, models: [TokenModel]) async throws -> [TokenCount] {
        try Task.checkCancellation()
        guard !models.isEmpty else {
            throw TokenCounterError.invalidRequest("At least one model is required.")
        }
        guard Set(models).count == models.count else {
            throw TokenCounterError.invalidRequest("Duplicate models are not allowed.")
        }

        let planned = try models.enumerated().map { index, model in
            guard let provider = providers[model] else {
                throw TokenCounterError.providerUnavailable(model)
            }
            return (index: index, model: model, provider: provider)
        }

        return try await withThrowingTaskGroup(
            of: (Int, TokenCount).self,
            returning: [TokenCount].self
        ) { group in
            for item in planned {
                group.addTask {
                    try Task.checkCancellation()
                    let tokens = try await item.provider.count(text: text, model: item.model)
                    try Task.checkCancellation()
                    guard tokens >= 0 else {
                        throw TokenCounterError.invalidTokenCount(item.model)
                    }
                    return (
                        item.index,
                        TokenCount(
                            model: item.model,
                            tokens: tokens,
                            source: item.provider.source
                        )
                    )
                }
            }

            var ordered = Array<TokenCount?>(repeating: nil, count: planned.count)
            for try await (index, result) in group {
                ordered[index] = result
            }
            return ordered.compactMap { $0 }
        }
    }
}

public struct OpenAITokenCounter: Sendable {
    public typealias ResourceLoader = @Sendable () throws -> Data

    public static let expectedVocabularySHA256 =
        "446a9538cb6c348e3516120d7c08b09f57c36495e2acfffe59a5bf8b0cfb1a2d"

    private let encoder: CoreBPE

    public init(resourceLoader: @escaping ResourceLoader = Self.bundledResourceLoader) throws {
        let data: Data
        do {
            data = try resourceLoader()
        } catch let error as TokenCounterError {
            throw error
        } catch {
            throw TokenCounterError.invalidResource
        }
        let actualSHA256 = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard actualSHA256 == Self.expectedVocabularySHA256 else {
            throw TokenCounterError.resourceIntegrity(
                expectedSHA256: Self.expectedVocabularySHA256,
                actualSHA256: actualSHA256
            )
        }

        let ranks = try Self.parseVocabulary(data)
        do {
            encoder = try CoreBPE(
                encoder: ranks,
                specialTokensEncoder: [
                    "<|endoftext|>": 199_999,
                    "<|endofprompt|>": 200_018,
                ],
                pattern: Self.o200kBasePattern
            )
        } catch {
            throw TokenCounterError.tokenizerFailure
        }
    }

    public static func bundledResourceLoader() throws -> Data {
        guard let url = Bundle.module.url(
            forResource: "o200k_base",
            withExtension: "tiktoken"
        ) else {
            throw TokenCounterError.invalidResource
        }
        // Return owned bytes: callers can inject or mutate a copy in integrity
        // tests without retaining a read-only mmap-backed Data value.
        do {
            return try Data(contentsOf: url)
        } catch {
            throw TokenCounterError.invalidResource
        }
    }

    public func count(text: String) throws -> TokenCount {
        do {
            let tokens = try encoder.encodeOrdinary(text: text)
            return TokenCount(model: .gpt4o, tokens: tokens.count, source: .local)
        } catch {
            throw TokenCounterError.tokenizerFailure
        }
    }

    private static let o200kBasePattern =
        #"[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]*[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?|[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]+[\p{Ll}\p{Lm}\p{Lo}\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?|\p{N}{1,3}| ?[^\s\p{L}\p{N}]+[\r\n/]*|\s*[\r\n]+|\s+(?!\S)|\s+"#

    private static func parseVocabulary(_ data: Data) throws -> [[UInt8]: UInt32] {
        guard let content = String(data: data, encoding: .utf8) else {
            throw TokenCounterError.invalidResource
        }

        var encoder: [[UInt8]: UInt32] = [:]
        var ranks = Set<UInt32>()
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard fields.count == 2,
                  let token = Data(base64Encoded: String(fields[0])),
                  let rank = UInt32(fields[1]),
                  encoder[Array(token)] == nil,
                  ranks.insert(rank).inserted
            else {
                throw TokenCounterError.invalidResource
            }
            encoder[Array(token)] = rank
        }

        guard !encoder.isEmpty else {
            throw TokenCounterError.invalidResource
        }
        return encoder
    }
}

public struct AnthropicTokenCountRequest: Sendable {
    public let model: TokenModel
    public let text: String
    public let apiKey: String

    public init(model: TokenModel, text: String, apiKey: String) {
        self.model = model
        self.text = text
        self.apiKey = apiKey
    }
}

public protocol AnthropicTokenCountTransport: Sendable {
    func countTokens(request: AnthropicTokenCountRequest) async throws -> Data
}

enum AnthropicRedirectPolicy: Equatable, Sendable {
    case reject
}

struct AnthropicHTTPResponse: @unchecked Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: AsyncThrowingStream<Data, Error>

    init(
        statusCode: Int,
        headers: [String: String],
        body: AsyncThrowingStream<Data, Error>
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

protocol AnthropicHTTPDataLoader: Sendable {
    func load(
        _ request: URLRequest,
        redirectPolicy: AnthropicRedirectPolicy,
        bodyByteLimit: Int
    ) async throws -> AnthropicHTTPResponse
}

public enum AnthropicTokenCountError: Error, Equatable, Sendable, LocalizedError {
    case authenticationFailed
    case rateLimited
    case providerFailure(statusCode: Int)
    case redirectRejected
    case timedOut
    case responseTooLarge(limit: Int)
    case invalidResponse
    case notImplemented

    public var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            "Anthropic authentication failed."
        case .rateLimited:
            "Anthropic token counting is rate limited."
        case let .providerFailure(statusCode):
            "Anthropic token counting failed with HTTP status \(statusCode)."
        case .redirectRejected:
            "Anthropic token counting rejected an HTTP redirect."
        case .timedOut:
            "Anthropic token counting timed out."
        case let .responseTooLarge(limit):
            "Anthropic returned more than \(limit) response bytes."
        case .invalidResponse:
            "Anthropic returned an invalid token-count response."
        case .notImplemented:
            "Anthropic token counting is not implemented."
        }
    }
}

struct AnthropicHTTPTokenCountTransport: AnthropicTokenCountTransport {
    static let endpoint = URL(
        string: "https://api.anthropic.com/v1/messages/count_tokens"
    )!
    static let responseByteLimit = 65_536
    static let requestTimeout: TimeInterval = 30

    private let loader: any AnthropicHTTPDataLoader

    init(loader: any AnthropicHTTPDataLoader) {
        self.loader = loader
    }

    func countTokens(request: AnthropicTokenCountRequest) async throws -> Data {
        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = Self.requestTimeout
        urlRequest.setValue(request.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = Self.requestBody(for: request)

        let response: AnthropicHTTPResponse
        do {
            response = try await loader.load(
                urlRequest,
                redirectPolicy: .reject,
                bodyByteLimit: Self.responseByteLimit
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw AnthropicTokenCountError.timedOut
        } catch let error as AnthropicTokenCountError {
            throw error
        } catch {
            throw AnthropicTokenCountError.providerFailure(statusCode: 0)
        }

        switch response.statusCode {
        case 200 ..< 300:
            break
        case 301, 302, 303, 307, 308:
            throw AnthropicTokenCountError.redirectRejected
        case 401, 403:
            throw AnthropicTokenCountError.authenticationFailed
        case 429:
            throw AnthropicTokenCountError.rateLimited
        default:
            throw AnthropicTokenCountError.providerFailure(statusCode: response.statusCode)
        }

        var data = Data()
        do {
            for try await chunk in response.body {
                guard chunk.count <= Self.responseByteLimit - data.count else {
                    throw AnthropicTokenCountError.responseTooLarge(
                        limit: Self.responseByteLimit
                    )
                }
                data.append(chunk)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AnthropicTokenCountError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw AnthropicTokenCountError.timedOut
        } catch {
            throw AnthropicTokenCountError.providerFailure(statusCode: response.statusCode)
        }

        struct ResponseEnvelope: Decodable {
            let inputTokens: Int

            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
            }
        }

        guard let envelope = try? JSONDecoder().decode(ResponseEnvelope.self, from: data),
              envelope.inputTokens >= 0
        else {
            throw AnthropicTokenCountError.invalidResponse
        }
        return data
    }

    private static func requestBody(for request: AnthropicTokenCountRequest) -> Data {
        func literal(_ value: String) -> Data {
            // Encoding a standalone String provides correct JSON escaping without
            // allowing source text to alter the request envelope.
            (try? JSONEncoder().encode(value)) ?? Data(#""""#.utf8)
        }

        var body = Data("{\"model\":".utf8)
        body.append(literal(request.model.rawValue))
        body.append(Data(",\"messages\":[{\"role\":\"user\",\"content\":".utf8))
        body.append(literal(request.text))
        body.append(Data("}]}".utf8))
        return body
    }
}

private actor OpenAITokenCountingProvider: TokenCountingProvider {
    nonisolated let source: TokenCount.Source = .local
    private let resourceLoader: OpenAITokenCounter.ResourceLoader
    private var counter: OpenAITokenCounter?

    init(resourceLoader: @escaping OpenAITokenCounter.ResourceLoader) {
        self.resourceLoader = resourceLoader
    }

    func count(text: String, model: TokenModel) async throws -> Int {
        guard model == .gpt4o else {
            throw TokenCounterError.invalidRequest("OpenAI provider received the wrong model.")
        }
        if counter == nil {
            counter = try OpenAITokenCounter(resourceLoader: resourceLoader)
        }
        guard let counter else {
            throw TokenCounterError.tokenizerFailure
        }
        return try counter.count(text: text).tokens
    }
}

private struct AnthropicTokenCountingProvider: TokenCountingProvider {
    let source: TokenCount.Source = .provider
    private let apiKey: String
    private let transport: any AnthropicTokenCountTransport

    init(apiKey: String, transport: any AnthropicTokenCountTransport) {
        self.apiKey = apiKey
        self.transport = transport
    }

    func count(text: String, model: TokenModel) async throws -> Int {
        guard model == .claudeSonnet46 else {
            throw TokenCounterError.invalidRequest("Anthropic provider received the wrong model.")
        }
        try Task.checkCancellation()
        let data: Data
        do {
            data = try await transport.countTokens(
                request: AnthropicTokenCountRequest(
                    model: model,
                    text: text,
                    apiKey: apiKey
                )
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AnthropicTokenCountError {
            throw error
        } catch {
            // Public transports are untrusted extension points. Never allow an
            // arbitrary error description to carry credentials, source text,
            // headers, or provider bodies across the package boundary.
            throw AnthropicTokenCountError.providerFailure(statusCode: 0)
        }
        try Task.checkCancellation()
        guard data.count <= AnthropicHTTPTokenCountTransport.responseByteLimit else {
            throw AnthropicTokenCountError.responseTooLarge(
                limit: AnthropicHTTPTokenCountTransport.responseByteLimit
            )
        }

        struct Envelope: Decodable {
            let inputTokens: Int

            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
            }
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.inputTokens >= 0
        else {
            throw AnthropicTokenCountError.invalidResponse
        }
        return envelope.inputTokens
    }
}

struct URLSessionAnthropicHTTPDataLoader: AnthropicHTTPDataLoader, @unchecked Sendable {
    typealias BodyObservation = @Sendable (
        _ callbackByteCount: Int,
        _ retainedByteCount: Int
    ) -> Void

    private let configuration: URLSessionConfiguration
    private let bodyObservation: BodyObservation?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = AnthropicHTTPTokenCountTransport.requestTimeout
        configuration.timeoutIntervalForResource = AnthropicHTTPTokenCountTransport.requestTimeout
        self.configuration = configuration
        bodyObservation = nil
    }

    init(session: URLSession, bodyObservation: BodyObservation? = nil) {
        configuration = session.configuration
        self.bodyObservation = bodyObservation
    }

    func load(
        _ request: URLRequest,
        redirectPolicy: AnthropicRedirectPolicy,
        bodyByteLimit: Int
    ) async throws -> AnthropicHTTPResponse {
        let delegate = BoundedAnthropicSessionDelegate(
            redirectPolicy: redirectPolicy,
            bodyByteLimit: bodyByteLimit,
            bodyObservation: bodyObservation
        )
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }
        return try await delegate.load(request, using: session)
    }

    static func readBoundedBody<Bytes: AsyncSequence>(
        from bytes: Bytes,
        limit: Int,
        cancel: @Sendable () -> Void
    ) async throws -> Data where Bytes.Element == UInt8 {
        var body = Data()
        body.reserveCapacity(min(limit, 16_384))
        do {
            for try await byte in bytes {
                guard body.count < limit else {
                    throw AnthropicTokenCountError.responseTooLarge(limit: limit)
                }
                body.append(byte)
            }
            return body
        } catch {
            cancel()
            throw error
        }
    }
}

private final class BoundedAnthropicSessionDelegate: NSObject,
    URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable
{
    private let redirectPolicy: AnthropicRedirectPolicy
    private let bodyByteLimit: Int
    private let bodyObservation: URLSessionAnthropicHTTPDataLoader.BodyObservation?
    private let lock = NSLock()
    private var continuation: CheckedContinuation<AnthropicHTTPResponse, Error>?
    private var task: URLSessionDataTask?
    private var response: HTTPURLResponse?
    private var body = Data()
    private var completed = false
    private var cancelledByCaller = false

    init(
        redirectPolicy: AnthropicRedirectPolicy,
        bodyByteLimit: Int,
        bodyObservation: URLSessionAnthropicHTTPDataLoader.BodyObservation?
    ) {
        self.redirectPolicy = redirectPolicy
        self.bodyByteLimit = bodyByteLimit
        self.bodyObservation = bodyObservation
        body.reserveCapacity(min(bodyByteLimit + 1, 16_384))
    }

    func load(
        _ request: URLRequest,
        using session: URLSession
    ) async throws -> AnthropicHTTPResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request)
                let start = lock.withLock { () -> Bool in
                    guard !cancelledByCaller else { return false }
                    self.continuation = continuation
                    self.task = task
                    return true
                }
                if start {
                    task.resume()
                } else {
                    task.cancel()
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            cancelFromCaller()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        switch redirectPolicy {
        case .reject:
            completionHandler(nil)
            task.cancel()
            finish(.failure(AnthropicTokenCountError.redirectRejected))
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let response = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(.failure(AnthropicTokenCountError.invalidResponse))
            return
        }

        lock.withLock { self.response = response }
        guard (200 ..< 300).contains(response.statusCode) else {
            completionHandler(.cancel)
            finish(.success(makeResponse(response: response, bodyData: Data())))
            return
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        let result = lock.withLock { () -> (overflowed: Bool, retained: Int) in
            guard !completed else { return (false, body.count) }
            let retainedCapacity = max(0, bodyByteLimit + 1 - body.count)
            if retainedCapacity > 0 {
                body.append(data.prefix(retainedCapacity))
            }
            return (body.count > bodyByteLimit, body.count)
        }
        bodyObservation?(data.count, result.retained)
        guard result.overflowed else { return }
        dataTask.cancel()
        finish(.failure(
            AnthropicTokenCountError.responseTooLarge(limit: bodyByteLimit)
        ))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            let callerCancelled = lock.withLock { cancelledByCaller }
            finish(.failure(callerCancelled ? CancellationError() : error))
            return
        }

        let snapshot = lock.withLock { (response, body) }
        guard let response = snapshot.0 else {
            finish(.failure(AnthropicTokenCountError.invalidResponse))
            return
        }
        finish(.success(makeResponse(response: response, bodyData: snapshot.1)))
    }

    private func cancelFromCaller() {
        let task = lock.withLock { () -> URLSessionDataTask? in
            cancelledByCaller = true
            return self.task
        }
        task?.cancel()
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<AnthropicHTTPResponse, Error>) {
        let continuation = lock.withLock {
            guard !completed else { return nil as CheckedContinuation<AnthropicHTTPResponse, Error>? }
            completed = true
            let continuation = self.continuation
            self.continuation = nil
            self.task = nil
            return continuation
        }
        continuation?.resume(with: result)
    }

    private func makeResponse(
        response: HTTPURLResponse,
        bodyData: Data
    ) -> AnthropicHTTPResponse {
        let headers = response.allHeaderFields.reduce(into: [String: String]()) {
            result, item in
            guard let key = item.key as? String else { return }
            result[key] = String(describing: item.value)
        }
        let body = AsyncThrowingStream<Data, Error> { continuation in
            if !bodyData.isEmpty {
                continuation.yield(bodyData)
            }
            continuation.finish()
        }
        return AnthropicHTTPResponse(
            statusCode: response.statusCode,
            headers: headers,
            body: body
        )
    }
}
