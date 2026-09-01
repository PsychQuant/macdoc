import Foundation
import Testing
import TokenCounter

@Test("Public callers can inject an Anthropic transport and catch package-owned errors")
func publicTransportInjectionAndTypedErrorsAreAvailable() async throws {
    let transport = PublicStubAnthropicTransport(
        response: Data(#"{"input_tokens":17}"#.utf8)
    )
    let service = try TokenCounterService(
        anthropicAPIKey: "PUBLIC_STUB_KEY",
        anthropicTransport: transport
    )

    let counts = try await service.count(
        text: "公開 API",
        models: [.claudeSonnet46]
    )

    #expect(counts == [
        TokenCount(model: .claudeSonnet46, tokens: 17, source: .provider),
    ])
    #expect(await transport.callCount() == 1)

    let typedError: AnthropicTokenCountError = .rateLimited
    #expect(typedError.errorDescription == "Anthropic token counting is rate limited.")

    let failingService = try TokenCounterService(
        anthropicAPIKey: "PUBLIC_STUB_KEY",
        anthropicTransport: PublicFailingAnthropicTransport()
    )
    do {
        _ = try await failingService.count(
            text: "公開 typed failure",
            models: [.claudeSonnet46]
        )
        Issue.record("Expected the public service to propagate a typed provider error")
    } catch let error as AnthropicTokenCountError {
        #expect(error == .rateLimited)
    } catch {
        Issue.record("Expected AnthropicTokenCountError, got \(error)")
    }
}

@Test("Arbitrary injected transport errors are normalized and redacted")
func arbitraryInjectedTransportErrorsAreRedacted() async throws {
    let forbidden = [
        "SYNTHETIC_KEY_MUST_NOT_ESCAPE",
        "SYNTHETIC_SOURCE_MUST_NOT_ESCAPE",
        "x-api-key",
        "SYNTHETIC_BODY_MUST_NOT_ESCAPE",
    ]
    let service = try TokenCounterService(
        anthropicAPIKey: "PUBLIC_STUB_KEY",
        anthropicTransport: PublicSensitiveFailingTransport(message: forbidden.joined(separator: "|"))
    )

    do {
        _ = try await service.count(
            text: "public injected error",
            models: [.claudeSonnet46]
        )
        Issue.record("Expected an injected transport error")
    } catch let error as AnthropicTokenCountError {
        #expect(error == .providerFailure(statusCode: 0))
        let rendered = String(reflecting: error) + (error.errorDescription ?? "")
        for marker in forbidden {
            #expect(!rendered.contains(marker))
        }
    } catch {
        Issue.record("Expected a normalized AnthropicTokenCountError, got \(error)")
    }
}

@Test("Injected transport responses are independently size bounded")
func injectedTransportResponsesAreBounded() async throws {
    let prefix = Data(#"{"input_tokens":17,"padding":""#.utf8)
    let suffix = Data(#""}"#.utf8)
    var response = prefix
    response.append(Data(repeating: 0x41, count: 65_537 - prefix.count - suffix.count))
    response.append(suffix)
    #expect(response.count == 65_537)

    let service = try TokenCounterService(
        anthropicAPIKey: "PUBLIC_STUB_KEY",
        anthropicTransport: PublicStubAnthropicTransport(response: response)
    )
    do {
        _ = try await service.count(
            text: "oversized injected response",
            models: [.claudeSonnet46]
        )
        Issue.record("Expected an oversized injected response to fail")
    } catch let error as AnthropicTokenCountError {
        #expect(error == .responseTooLarge(limit: 65_536))
    } catch {
        Issue.record("Expected AnthropicTokenCountError, got \(error)")
    }
}

private struct PublicFailingAnthropicTransport: AnthropicTokenCountTransport {
    func countTokens(request _: AnthropicTokenCountRequest) async throws -> Data {
        throw AnthropicTokenCountError.rateLimited
    }
}

private struct PublicSensitiveFailingTransport: AnthropicTokenCountTransport {
    struct SensitiveError: Error, CustomStringConvertible {
        let description: String
    }

    let message: String

    func countTokens(request _: AnthropicTokenCountRequest) async throws -> Data {
        throw SensitiveError(description: message)
    }
}

@Test("OpenAI dependency failures are normalized to a package-owned error")
func openAIDependencyErrorsDoNotEscapeThePublicAPI() throws {
    let counter = try OpenAITokenCounter()

    do {
        _ = try counter.count(text: String(repeating: "a", count: 1_000_001))
        Issue.record("Expected the tokenizer input bound to fail")
    } catch let error as TokenCounterError {
        #expect(error == .tokenizerFailure)
    } catch {
        Issue.record("Expected TokenCounterError, got \(error)")
    }
}

private actor PublicStubAnthropicTransport: AnthropicTokenCountTransport {
    private let response: Data
    private var calls = 0

    init(response: Data) {
        self.response = response
    }

    func countTokens(request _: AnthropicTokenCountRequest) async throws -> Data {
        calls += 1
        return response
    }

    func callCount() -> Int {
        calls
    }
}
