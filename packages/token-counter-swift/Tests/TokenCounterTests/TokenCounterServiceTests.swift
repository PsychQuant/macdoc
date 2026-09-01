import Foundation
import Testing
@testable import TokenCounter

@Test("TokenModel raw values are the exact public allow-list")
func tokenModelRawValuesAreExact() {
    #expect(TokenModel.gpt4o.rawValue == "gpt-4o")
    #expect(TokenModel.claudeSonnet46.rawValue == "claude-sonnet-4-6")
    #expect(TokenModel.allCases == [.gpt4o, .claudeSonnet46])

    #expect(TokenModel(rawValue: "gpt-4.1") == nil)
    #expect(TokenModel(rawValue: "GPT-4O") == nil)
}

@Test("Service preserves [Claude, GPT] request order and provider source")
func servicePreservesRequestedOrderAndSource() async throws {
    let service = TokenCounterService(providers: [
        .claudeSonnet46: StubTokenCountingProvider(
            source: .provider,
            outcome: .success(1_198),
            delay: .milliseconds(20)
        ),
        .gpt4o: StubTokenCountingProvider(
            source: .local,
            outcome: .success(1_234)
        ),
    ])

    let results = try await service.count(
        text: "完整文字",
        models: [.claudeSonnet46, .gpt4o]
    )

    #expect(results.count == 2)
    #expect(results.map(\.model) == [.claudeSonnet46, .gpt4o])
    #expect(results.map(\.tokens) == [1_198, 1_234])
    #expect(results.map(\.source) == [.provider, .local])
}

@Test("Multi-provider failure throws without returning a partial array")
func multiProviderFailureIsAtomic() async {
    let calls = ProviderCallLog()
    let service = TokenCounterService(providers: [
        .gpt4o: StubTokenCountingProvider(
            source: .local,
            outcome: .success(1_234),
            calls: calls
        ),
        .claudeSonnet46: StubTokenCountingProvider(
            source: .provider,
            outcome: .failure(.providerUnavailable),
            delay: .milliseconds(20),
            calls: calls
        ),
    ])

    var returnedResults: [TokenCount]?
    do {
        returnedResults = try await service.count(
            text: "must not leak a partial result",
            models: [.gpt4o, .claudeSonnet46]
        )
        Issue.record("Expected the multi-provider request to throw")
    } catch {
        // Throwing is the public all-or-nothing result; no partial array is exposed.
    }

    #expect(returnedResults == nil)
    let invokedModels = await calls.snapshot()
    #expect(invokedModels.contains(.gpt4o))
    #expect(invokedModels.contains(.claudeSonnet46))
}

@Test("Duplicate models fail loudly as an invalid request before provider work")
func duplicateModelsAreAnInvalidRequest() async {
    let calls = ProviderCallLog()
    let service = TokenCounterService(providers: [
        .gpt4o: StubTokenCountingProvider(
            source: .local,
            outcome: .success(1_234),
            calls: calls
        ),
    ])

    do {
        _ = try await service.count(
            text: "duplicate model",
            models: [.gpt4o, .gpt4o]
        )
        Issue.record("Expected duplicate models to throw TokenCounterError.invalidRequest")
    } catch let error as TokenCounterError {
        switch error {
        case .invalidRequest:
            break
        default:
            Issue.record("Expected invalidRequest, got \(error)")
        }
    } catch {
        Issue.record("Expected TokenCounterError.invalidRequest, got \(error)")
    }

    let invokedModels = await calls.snapshot()
    #expect(invokedModels.isEmpty)
}

@Test("Claude-only requests do not load the GPT vocabulary")
func claudeOnlyRequestDoesNotConstructOpenAIProvider() async throws {
    let resourceProbe = SynchronousResourceProbe()
    let transport = SuccessfulAnthropicTransport()
    let service = try TokenCounterService(
        anthropicAPIKey: "STUB_KEY",
        anthropicTransport: transport,
        openAIResourceLoader: {
            resourceProbe.recordCall()
            throw TokenCounterError.invalidResource
        }
    )

    let counts = try await service.count(
        text: "Claude only",
        models: [.claudeSonnet46]
    )

    #expect(counts == [
        TokenCount(model: .claudeSonnet46, tokens: 9, source: .provider),
    ])
    #expect(resourceProbe.callCount == 0)
}

@Test("Service cancellation wins over a non-cooperative injected transport")
func serviceCancellationIsPreserved() async throws {
    let gate = NonCooperativeTransportGate()
    let service = try TokenCounterService(
        anthropicAPIKey: "STUB_KEY",
        anthropicTransport: NonCooperativeAnthropicTransport(gate: gate)
    )
    let operation = Task {
        try await service.count(
            text: "cancelled provider request",
            models: [.claudeSonnet46]
        )
    }

    await gate.waitUntilStarted()
    operation.cancel()
    await gate.release(Data(#"{"input_tokens":9}"#.utf8))

    do {
        _ = try await operation.value
        Issue.record("Expected service cancellation")
    } catch is CancellationError {
        // Expected.
    } catch {
        Issue.record("Expected CancellationError, got \(error)")
    }
}

private enum ServiceStubError: Error, Sendable {
    case providerUnavailable
}

private enum StubOutcome: Sendable {
    case success(Int)
    case failure(ServiceStubError)
}

private struct StubTokenCountingProvider: TokenCountingProvider {
    let source: TokenCount.Source
    let outcome: StubOutcome
    var delay: Duration = .zero
    var calls: ProviderCallLog? = nil

    func count(text: String, model: TokenModel) async throws -> Int {
        if let calls {
            await calls.record(model)
        }
        if delay != .zero {
            try await Task.sleep(for: delay)
        }

        switch outcome {
        case .success(let tokens):
            return tokens
        case .failure(let error):
            throw error
        }
    }
}

private actor ProviderCallLog {
    private var models: [TokenModel] = []

    func record(_ model: TokenModel) {
        models.append(model)
    }

    func snapshot() -> [TokenModel] {
        models
    }
}

private struct SuccessfulAnthropicTransport: AnthropicTokenCountTransport {
    func countTokens(request _: AnthropicTokenCountRequest) async throws -> Data {
        Data(#"{"input_tokens":9}"#.utf8)
    }
}

private struct NonCooperativeAnthropicTransport: AnthropicTokenCountTransport {
    let gate: NonCooperativeTransportGate

    func countTokens(request _: AnthropicTokenCountRequest) async throws -> Data {
        await gate.response()
    }
}

private actor NonCooperativeTransportGate {
    private var started = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var responseContinuation: CheckedContinuation<Data, Never>?

    func response() async -> Data {
        started = true
        let waiters = startedWaiters
        startedWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return await withCheckedContinuation { continuation in
            responseContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startedWaiters.append(continuation)
        }
    }

    func release(_ data: Data) {
        responseContinuation?.resume(returning: data)
        responseContinuation = nil
    }
}

private final class SynchronousResourceProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    func recordCall() {
        lock.withLock { calls += 1 }
    }

    var callCount: Int {
        lock.withLock { calls }
    }
}
