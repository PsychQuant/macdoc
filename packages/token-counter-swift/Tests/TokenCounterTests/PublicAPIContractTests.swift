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

private struct PublicFailingAnthropicTransport: AnthropicTokenCountTransport {
    func countTokens(request _: AnthropicTokenCountRequest) async throws -> Data {
        throw AnthropicTokenCountError.rateLimited
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
