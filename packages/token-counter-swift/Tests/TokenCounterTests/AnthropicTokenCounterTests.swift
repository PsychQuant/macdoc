import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import TokenCounter

@Suite("Anthropic Message Token Count transport")
struct AnthropicTokenCounterTests {
    private let apiKey = "ANTHROPIC_TEST_KEY_DO_NOT_LEAK"
    private let sourceText = "PRIVATE_SOURCE_TEXT_DO_NOT_LEAK"

    @Test("builds the fixed Anthropic request and parses input_tokens")
    func buildsFixedRequestAndParsesCount() async throws {
        let payload = Data(#"{"input_tokens":1198}"#.utf8)
        let loader = RecordingAnthropicHTTPDataLoader(
            response: response(statusCode: 200, chunks: [payload])
        )
        let subject: any AnthropicTokenCountTransport = AnthropicHTTPTokenCountTransport(
            loader: loader
        )

        let returnedBody = try await subject.countTokens(request: request())

        #expect(returnedBody == payload)
        #expect(try decodedInputTokens(from: returnedBody) == 1_198)

        let calls = await loader.recordedCalls()
        #expect(calls.count == 1)
        let call = try #require(calls.first)
        #expect(call.request.url?.absoluteString == "https://api.anthropic.com/v1/messages/count_tokens")
        #expect(call.request.httpMethod == "POST")
        #expect(call.request.timeoutInterval == 30)
        #expect(call.redirectPolicy == .reject)

        let headers = normalizedHeaders(call.request.allHTTPHeaderFields ?? [:])
        #expect(headers == [
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
            "x-api-key": apiKey,
        ])

        let expectedBody = Data(
            #"{"model":"claude-sonnet-4-6","messages":[{"role":"user","content":"PRIVATE_SOURCE_TEXT_DO_NOT_LEAK"}]}"#.utf8
        )
        #expect(call.request.httpBody == expectedBody)
        #expect(call.request.url?.absoluteString.contains(apiKey) == false)
        #expect(call.request.httpBody?.contains(Data(apiKey.utf8)) == false)
        #expect(headers.filter { $0.value.contains(apiKey) }.map(\.key) == ["x-api-key"])
    }

    @Test("maps 401 and 403 to authentication failure", arguments: [401, 403])
    func mapsAuthenticationFailure(statusCode: Int) async {
        let providerBody = Data("AUTH_PROVIDER_BODY_DO_NOT_LEAK".utf8)
        let loader = RecordingAnthropicHTTPDataLoader(
            response: response(statusCode: statusCode, chunks: [providerBody])
        )
        let subject = AnthropicHTTPTokenCountTransport(loader: loader)

        let error = await capturedError(from: subject, request: request())

        #expect(error == .authenticationFailed)
        assertRedacted(error, additionalForbiddenValues: [String(decoding: providerBody, as: UTF8.self)])
        #expect(await loader.callCount() == 1)
    }

    @Test("maps 429 to rate limiting without retrying")
    func mapsRateLimitWithoutRetry() async {
        let providerBody = Data("RATE_LIMIT_BODY_DO_NOT_LEAK".utf8)
        let loader = RecordingAnthropicHTTPDataLoader(
            response: response(statusCode: 429, chunks: [providerBody])
        )
        let subject = AnthropicHTTPTokenCountTransport(loader: loader)

        let error = await capturedError(from: subject, request: request())

        #expect(error == .rateLimited)
        assertRedacted(error, additionalForbiddenValues: [String(decoding: providerBody, as: UTF8.self)])
        #expect(await loader.callCount() == 1)
    }

    @Test("maps other non-2xx statuses to provider failure", arguments: [400, 500, 503])
    func mapsOtherProviderFailures(statusCode: Int) async {
        let providerBody = Data("PROVIDER_FAILURE_BODY_DO_NOT_LEAK".utf8)
        let loader = RecordingAnthropicHTTPDataLoader(
            response: response(statusCode: statusCode, chunks: [providerBody])
        )
        let subject = AnthropicHTTPTokenCountTransport(loader: loader)

        let error = await capturedError(from: subject, request: request())

        #expect(error == .providerFailure(statusCode: statusCode))
        assertRedacted(error, additionalForbiddenValues: [String(decoding: providerBody, as: UTF8.self)])
        #expect(await loader.callCount() == 1)
    }

    @Test("rejects redirects without following or retrying", arguments: [301, 302, 307, 308])
    func rejectsRedirects(statusCode: Int) async {
        let loader = RecordingAnthropicHTTPDataLoader(
            response: response(
                statusCode: statusCode,
                headers: ["Location": "https://redirect.invalid/PRIVATE_REDIRECT_DO_NOT_LEAK"],
                chunks: []
            )
        )
        let subject = AnthropicHTTPTokenCountTransport(loader: loader)

        let error = await capturedError(from: subject, request: request())

        #expect(error == .redirectRejected)
        assertRedacted(error, additionalForbiddenValues: ["PRIVATE_REDIRECT_DO_NOT_LEAK"])
        let calls = await loader.recordedCalls()
        #expect(calls.count == 1)
        #expect(calls.first?.redirectPolicy == .reject)
    }

    @Test("maps a 30-second request timeout without retrying")
    func mapsTimeoutWithoutRetry() async {
        let loader = RecordingAnthropicHTTPDataLoader(error: URLError(.timedOut))
        let subject = AnthropicHTTPTokenCountTransport(loader: loader)

        let error = await capturedError(from: subject, request: request())

        #expect(error == .timedOut)
        assertRedacted(error)
        let calls = await loader.recordedCalls()
        #expect(calls.count == 1)
        #expect(calls.first?.request.timeoutInterval == 30)
    }

    @Test("accepts a response body at exactly the 64-KiB limit")
    func acceptsExactResponseLimit() async throws {
        let payload = paddedSuccessPayload(byteCount: 65_536)
        let loader = RecordingAnthropicHTTPDataLoader(
            response: response(
                statusCode: 200,
                chunks: [Data(payload.prefix(32_768)), Data(payload.dropFirst(32_768))]
            )
        )
        let subject = AnthropicHTTPTokenCountTransport(loader: loader)

        let returnedBody = try await subject.countTokens(request: request())

        #expect(returnedBody.count == 65_536)
        #expect(try decodedInputTokens(from: returnedBody) == 1_198)
        #expect(await loader.callCount() == 1)
    }

    @Test("stops streaming immediately after the 64-KiB response cap")
    func stopsAtStreamingResponseLimit() async {
        let probe = ResponseChunkProbe(chunks: [
            Data(repeating: 0x41, count: 65_536),
            Data([0x42]),
            Data("UNREAD_RESPONSE_CONTENT_DO_NOT_LEAK".utf8),
        ])
        let loader = RecordingAnthropicHTTPDataLoader(
            response: AnthropicHTTPResponse(
                statusCode: 200,
                headers: [:],
                body: AsyncThrowingStream(unfolding: { await probe.next() })
            )
        )
        let subject = AnthropicHTTPTokenCountTransport(loader: loader)

        let error = await capturedError(from: subject, request: request())

        #expect(error == .responseTooLarge(limit: 65_536))
        assertRedacted(error, additionalForbiddenValues: ["UNREAD_RESPONSE_CONTENT_DO_NOT_LEAK"])
        #expect(await probe.readCount() == 2)
        #expect(await loader.callCount() == 1)
    }

    @Test("rejects malformed, missing, negative, and non-integer input_tokens")
    func rejectsInvalidTokenCounts() async {
        let invalidPayloads: [(name: String, data: Data)] = [
            ("malformed JSON", Data("not-json".utf8)),
            ("missing input_tokens", Data("{}".utf8)),
            ("negative integer", Data(#"{"input_tokens":-1}"#.utf8)),
            ("fraction", Data(#"{"input_tokens":1198.5}"#.utf8)),
            ("numeric string", Data(#"{"input_tokens":"1198"}"#.utf8)),
            ("boolean", Data(#"{"input_tokens":true}"#.utf8)),
            ("null", Data(#"{"input_tokens":null}"#.utf8)),
        ]

        for invalidPayload in invalidPayloads {
            let loader = RecordingAnthropicHTTPDataLoader(
                response: response(statusCode: 200, chunks: [invalidPayload.data])
            )
            let subject = AnthropicHTTPTokenCountTransport(loader: loader)

            let error = await capturedError(from: subject, request: request())

            #expect(error == .invalidResponse, "Expected invalid response for \(invalidPayload.name)")
            assertRedacted(error, additionalForbiddenValues: [String(decoding: invalidPayload.data, as: UTF8.self)])
            #expect(await loader.callCount() == 1)
        }
    }

    @Test("never exposes the API key, source, headers, request body, or full response body")
    func redactsEverySensitiveRequestValue() async {
        let responseBody = "FULL_PROVIDER_RESPONSE_BODY_DO_NOT_LEAK"
        let loader = RecordingAnthropicHTTPDataLoader(
            response: response(statusCode: 500, chunks: [Data(responseBody.utf8)])
        )
        let subject = AnthropicHTTPTokenCountTransport(loader: loader)

        let error = await capturedError(from: subject, request: request())

        #expect(error == .providerFailure(statusCode: 500))
        assertRedacted(error, additionalForbiddenValues: [
            responseBody,
            "x-api-key",
            "anthropic-version",
            "content-type",
            #"{"model":"claude-sonnet-4-6","messages":[{"role":"user","content":"PRIVATE_SOURCE_TEXT_DO_NOT_LEAK"}]}"#,
        ])
    }

    private func request() -> AnthropicTokenCountRequest {
        AnthropicTokenCountRequest(
            model: .claudeSonnet46,
            text: sourceText,
            apiKey: apiKey
        )
    }

    private func capturedError(
        from transport: some AnthropicTokenCountTransport,
        request: AnthropicTokenCountRequest
    ) async -> AnthropicTokenCountError? {
        do {
            _ = try await transport.countTokens(request: request)
            Issue.record("Expected Anthropic token counting to fail")
            return nil
        } catch let error as AnthropicTokenCountError {
            return error
        } catch {
            Issue.record("Expected a typed AnthropicTokenCountError")
            return nil
        }
    }

    private func assertRedacted(
        _ error: AnthropicTokenCountError?,
        additionalForbiddenValues: [String] = []
    ) {
        guard let error else {
            return
        }
        let renderedError = [
            String(describing: error),
            String(reflecting: error),
            (error as NSError).localizedDescription,
        ].joined(separator: "\n")
        let forbiddenValues = [apiKey, sourceText] + additionalForbiddenValues

        for forbiddenValue in forbiddenValues where !forbiddenValue.isEmpty {
            #expect(!renderedError.contains(forbiddenValue))
        }
    }
}

private actor RecordingAnthropicHTTPDataLoader: AnthropicHTTPDataLoader {
    struct Call: @unchecked Sendable {
        let request: URLRequest
        let redirectPolicy: AnthropicRedirectPolicy
    }

    private enum Outcome: @unchecked Sendable {
        case response(AnthropicHTTPResponse)
        case failure(URLError)
    }

    private let outcome: Outcome
    private var calls: [Call] = []

    init(response: AnthropicHTTPResponse) {
        outcome = .response(response)
    }

    init(error: URLError) {
        outcome = .failure(error)
    }

    func load(
        _ request: URLRequest,
        redirectPolicy: AnthropicRedirectPolicy
    ) async throws -> AnthropicHTTPResponse {
        calls.append(Call(request: request, redirectPolicy: redirectPolicy))
        switch outcome {
        case let .response(response):
            return response
        case let .failure(error):
            throw error
        }
    }

    func recordedCalls() -> [Call] {
        calls
    }

    func callCount() -> Int {
        calls.count
    }
}

private actor ResponseChunkProbe {
    private var chunks: [Data]
    private var reads = 0

    init(chunks: [Data]) {
        self.chunks = chunks
    }

    func next() -> Data? {
        guard !chunks.isEmpty else {
            return nil
        }
        reads += 1
        return chunks.removeFirst()
    }

    func readCount() -> Int {
        reads
    }
}

private func response(
    statusCode: Int,
    headers: [String: String] = [:],
    chunks: [Data]
) -> AnthropicHTTPResponse {
    AnthropicHTTPResponse(
        statusCode: statusCode,
        headers: headers,
        body: AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    )
}

private func normalizedHeaders(_ headers: [String: String]) -> [String: String] {
    Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
}

private func decodedInputTokens(from data: Data) throws -> Int {
    struct Envelope: Decodable {
        let inputTokens: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
        }
    }

    return try JSONDecoder().decode(Envelope.self, from: data).inputTokens
}

private func paddedSuccessPayload(byteCount: Int) -> Data {
    let prefix = Data(#"{"input_tokens":1198,"padding":""#.utf8)
    let suffix = Data([0x22, 0x7D])
    precondition(byteCount >= prefix.count + suffix.count)

    var data = prefix
    data.append(Data(repeating: 0x41, count: byteCount - prefix.count - suffix.count))
    data.append(suffix)
    return data
}
