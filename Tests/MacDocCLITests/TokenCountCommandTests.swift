import Foundation
import TokenCounter
import XCTest

@testable import MacDocCLI

final class TokenCountCommandTests: XCTestCase {
    func testCompiledOpenAIRouteEmitsOnlyTheOfficialCount() throws {
        let input = try temporaryFile(named: "sample.md", data: Data("hello world".utf8))
        defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }
        let isolation = try temporaryIsolationEnvironment()
        defer { try? FileManager.default.removeItem(at: isolation.root) }
        let filesBefore = try relativeRegularFilePaths(in: isolation.root)

        let result = try CLITestHelper.runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
            arguments: [
                "-p", "(version 1)(allow default)(deny network*)",
                CLITestHelper.binaryPath,
                "convert", "--to", "tokens", "--model", "gpt-4o", input.path,
            ],
            currentDirectory: CLITestHelper.repoRoot,
            timeout: 30,
            environment: isolation.environment
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(result.stdout, "2\n")
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(try relativeRegularFilePaths(in: isolation.root), filesBefore)
    }

    func testCompiledOpenAIRouteWritesExactOutputFileBytes() throws {
        let input = try temporaryFile(named: "sample.data", data: Data("hello world".utf8))
        let directory = input.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("tokens.txt")

        let result = try CLITestHelper.convert(
            to: "tokens",
            input: input.path,
            flags: ["--model", "gpt-4o", "--output", output.path]
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(result.stderr, "已寫入: \(output.path)\n")
        XCTAssertEqual(try Data(contentsOf: output), Data("2\n".utf8))
    }

    func testCompiledUnsupportedModelFailsWithExactDiagnostic() throws {
        let input = try temporaryFile(named: "sample.txt", data: Data("private".utf8))
        defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }

        let result = try CLITestHelper.convert(
            to: "tokens",
            input: input.path,
            flags: ["--model", "gpt-4.1"]
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(
            result.stderr,
            "Error: 不支援的 token model；可用值：gpt-4o、claude-sonnet-4-6\n"
        )
    }

    func testCompiledDefaultRouteRequiresExplicitNetworkConsent() throws {
        let input = try temporaryFile(named: "sample.txt", data: Data("private".utf8))
        defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }

        let result = try CLITestHelper.convert(to: "tokens", input: input.path)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(
            result.stderr,
            "Error: Claude token 計數會傳送完整輸入內容；請明確加入 --allow-network\n"
        )
    }

    func testCompiledClaudeRouteRequiresNonemptyCredentialBeforeNetwork() throws {
        let input = try temporaryFile(named: "sample.txt", data: Data("private".utf8))
        defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }

        let result = try CLITestHelper.convert(
            to: "tokens",
            input: input.path,
            flags: ["--model", "claude-sonnet-4-6", "--allow-network"],
            environment: ["ANTHROPIC_API_KEY": ""]
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(
            result.stderr,
            "Error: Claude token 計數需要非空的 ANTHROPIC_API_KEY\n"
        )
    }

    func testRunnerRendersDeterministicDualModelTable() async throws {
        let input = try temporaryFile(named: "sample.data", data: Data("完整文字".utf8))
        defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }
        let probe = CountInvocationProbe(result: [
            TokenCount(model: .gpt4o, tokens: 1_234, source: .local),
            TokenCount(model: .claudeSonnet46, tokens: 1_198, source: .provider),
        ])
        let runner = TokenCountCommandRunner(
            environment: { key in key == "ANTHROPIC_API_KEY" ? "TEST_KEY" : nil },
            count: { text, models, apiKey in
                await probe.count(text: text, models: models, apiKey: apiKey)
            }
        )

        let rendered = try await runner.render(
            inputURL: input,
            modelName: nil,
            allowNetwork: true
        )

        XCTAssertEqual(
            rendered,
            "Model\tTokens\ngpt-4o\t1234\nclaude-sonnet-4-6\t1198\n"
        )
        let invocations = await probe.invocations()
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.text, "完整文字")
        XCTAssertEqual(invocation.models, [.gpt4o, .claudeSonnet46])
        XCTAssertEqual(invocation.apiKey, "TEST_KEY")
    }

    func testRunnerAcceptsExactlyOneMillionUTF8Bytes() async throws {
        let input = try temporaryFile(
            named: "boundary.bin",
            data: Data(repeating: 0x61, count: 1_000_000)
        )
        defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }
        let probe = CountInvocationProbe(result: [
            TokenCount(model: .gpt4o, tokens: 125_000, source: .local),
        ])
        let runner = TokenCountCommandRunner(
            environment: { _ in nil },
            count: { text, models, apiKey in
                await probe.count(text: text, models: models, apiKey: apiKey)
            }
        )

        let rendered = try await runner.render(
            inputURL: input,
            modelName: "gpt-4o",
            allowNetwork: false
        )

        XCTAssertEqual(rendered, "125000\n")
        let invocations = await probe.invocations()
        XCTAssertEqual(invocations.first?.text.utf8.count, 1_000_000)
    }

    func testRunnerRejectsOneMillionAndOneBytesBeforeProvider() async throws {
        let input = try temporaryFile(
            named: "too-large.txt",
            data: Data(repeating: 0x61, count: 1_000_001)
        )
        defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }
        let probe = CountInvocationProbe(result: [])
        let runner = TokenCountCommandRunner(
            environment: { _ in nil },
            count: { text, models, apiKey in
                await probe.count(text: text, models: models, apiKey: apiKey)
            }
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await runner.render(
                inputURL: input,
                modelName: "gpt-4o",
                allowNetwork: false
            )
        }
        let invocations = await probe.invocations()
        XCTAssertTrue(invocations.isEmpty)
    }

    func testRunnerRejectsInvalidUTF8BeforeProvider() async throws {
        let input = try temporaryFile(named: "invalid.txt", data: Data([0xff, 0xfe]))
        defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }
        let probe = CountInvocationProbe(result: [])
        let runner = TokenCountCommandRunner(
            environment: { _ in nil },
            count: { text, models, apiKey in
                await probe.count(text: text, models: models, apiKey: apiKey)
            }
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await runner.render(
                inputURL: input,
                modelName: "gpt-4o",
                allowNetwork: false
            )
        }
        let invocations = await probe.invocations()
        XCTAssertTrue(invocations.isEmpty)
    }

    func testRunnerAcceptsEmptyFile() async throws {
        let input = try temporaryFile(named: "empty.anything", data: Data())
        defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }
        let probe = CountInvocationProbe(result: [
            TokenCount(model: .gpt4o, tokens: 0, source: .local),
        ])
        let runner = TokenCountCommandRunner(
            environment: { _ in nil },
            count: { text, models, apiKey in
                await probe.count(text: text, models: models, apiKey: apiKey)
            }
        )

        let rendered = try await runner.render(
            inputURL: input,
            modelName: "gpt-4o",
            allowNetwork: false
        )

        XCTAssertEqual(rendered, "0\n")
    }

    func testRunnerProviderFailureReturnsNoRenderablePartialValue() async throws {
        let input = try temporaryFile(named: "sample.txt", data: Data("private".utf8))
        defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }
        let runner = TokenCountCommandRunner(
            environment: { _ in "TEST_KEY" },
            count: { _, _, _ in throw StubCountError.failed }
        )
        var rendered: String?

        do {
            rendered = try await runner.render(
                inputURL: input,
                modelName: nil,
                allowNetwork: true
            )
            XCTFail("Expected provider failure")
        } catch {
            XCTAssertNil(rendered)
        }
    }

    func testInjectedProviderFailuresNeverWritePartialOutput() async throws {
        let localCounter = try OpenAITokenCounter()
        for failure in StubProviderFailure.allCases {
            let input = try temporaryFile(
                named: "sample-\(failure.rawValue).txt",
                data: Data("PRIVATE_SOURCE_TEXT".utf8)
            )
            let directory = input.deletingLastPathComponent()
            defer { try? FileManager.default.removeItem(at: directory) }
            let existingOutput = directory.appendingPathComponent("existing.txt")
            let absentOutput = directory.appendingPathComponent("absent.txt")
            try Data("KEEP".utf8).write(to: existingOutput)
            let probe = ProviderFailureCommandProbe(failure: failure)
            let runner = TokenCountCommandRunner(
                environment: { key in
                    key == "ANTHROPIC_API_KEY" ? "TEST_STUB_KEY_NOT_LIVE" : nil
                },
                count: { text, models, apiKey in
                    let local = try localCounter.count(text: text)
                    probe.recordLocalSuccess(local)
                    _ = try await probe.transport.countTokens(
                        request: AnthropicTokenCountRequest(
                            model: .claudeSonnet46,
                            text: text,
                            apiKey: apiKey ?? ""
                        )
                    )
                    return []
                }
            )

            for output in [existingOutput, absentOutput] {
                let result = await runner.invoke(
                    inputURL: input,
                    modelName: nil,
                    allowNetwork: true,
                    outputURL: output
                )

                XCTAssertEqual(result.exitCode, 1)
                XCTAssertEqual(result.stdout, Data())
                XCTAssertFalse(result.stderr.isEmpty)
                let diagnostic = String(decoding: result.stderr, as: UTF8.self)
                XCTAssertFalse(diagnostic.contains("TEST_STUB_KEY_NOT_LIVE"))
                XCTAssertFalse(diagnostic.contains("PRIVATE_SOURCE_TEXT"))
            }

            XCTAssertEqual(try Data(contentsOf: existingOutput), Data("KEEP".utf8))
            XCTAssertFalse(FileManager.default.fileExists(atPath: absentOutput.path))
            XCTAssertEqual(probe.localSuccessCount, 2)
            XCTAssertEqual(probe.transport.callCount, 2)
        }
    }

    func testCancellationBeforePresentationWritesNothing() async throws {
        let input = try temporaryFile(named: "cancel.txt", data: Data("private".utf8))
        let directory = input.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("cancelled-output.txt")
        let gate = NonCooperativeCountGate()
        let runner = TokenCountCommandRunner(
            environment: { _ in nil },
            count: { _, _, _ in await gate.count() }
        )

        let operation = Task {
            try await runner.execute(
                inputURL: input,
                modelName: "gpt-4o",
                allowNetwork: false,
                outputURL: output,
                stdout: { _ in XCTFail("cancelled command must not write stdout") },
                stderr: { _ in XCTFail("cancelled command must not announce output") }
            )
        }
        await gate.waitUntilStarted()
        operation.cancel()
        await gate.release([
            TokenCount(model: .gpt4o, tokens: 1, source: .local),
        ])

        do {
            try await operation.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected package/CLI cancellation contract.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testInputPathSwapAfterOpenReadsTheAlreadyAuthorizedDescriptor() throws {
        let original = try temporaryFile(named: "source.txt", data: Data("AUTHORIZED".utf8))
        let directory = original.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        let moved = directory.appendingPathComponent("opened-source.txt")
        let secret = directory.appendingPathComponent("secret.txt")
        try Data("MUST_NOT_BE_READ".utf8).write(to: secret)

        let text = try TokenCountCommandRunner.readAdmittedText(
            from: original,
            afterOpen: {
                try FileManager.default.moveItem(at: original, to: moved)
                try FileManager.default.createSymbolicLink(
                    at: original,
                    withDestinationURL: secret
                )
            }
        )

        XCTAssertEqual(text, "AUTHORIZED")
    }

    func testInputSymlinkIsRejectedBeforeProvider() async throws {
        let target = try temporaryFile(named: "target.txt", data: Data("PRIVATE".utf8))
        let directory = target.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        let link = directory.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let probe = CountInvocationProbe(result: [])
        let runner = TokenCountCommandRunner(
            environment: { _ in nil },
            count: { text, models, apiKey in
                await probe.count(text: text, models: models, apiKey: apiKey)
            }
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await runner.render(
                inputURL: link,
                modelName: "gpt-4o",
                allowNetwork: false
            )
        }

        let invocations = await probe.invocations()
        XCTAssertTrue(invocations.isEmpty)
    }

    func testRunnerMissingConsentReadsNoCredentialAndInvokesNoProvider() async throws {
        let input = try temporaryFile(named: "sample.txt", data: Data("private".utf8))
        defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }
        let environment = SynchronousEnvironmentProbe(values: [
            "ANTHROPIC_API_KEY": "MUST_NOT_BE_READ",
        ])
        let countProbe = CountInvocationProbe(result: [])
        let runner = TokenCountCommandRunner(
            environment: { environment.read($0) },
            count: { text, models, apiKey in
                await countProbe.count(text: text, models: models, apiKey: apiKey)
            }
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await runner.render(
                inputURL: input,
                modelName: "claude-sonnet-4-6",
                allowNetwork: false
            )
        }

        XCTAssertEqual(environment.requestedKeys, [])
        let invocations = await countProbe.invocations()
        XCTAssertTrue(invocations.isEmpty)
    }

    func testRunnerMissingCredentialInvokesNoProvider() async throws {
        let input = try temporaryFile(named: "sample.txt", data: Data("private".utf8))
        defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }
        let environment = SynchronousEnvironmentProbe(values: [:])
        let countProbe = CountInvocationProbe(result: [])
        let runner = TokenCountCommandRunner(
            environment: { environment.read($0) },
            count: { text, models, apiKey in
                await countProbe.count(text: text, models: models, apiKey: apiKey)
            }
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await runner.render(
                inputURL: input,
                modelName: "claude-sonnet-4-6",
                allowNetwork: true
            )
        }

        XCTAssertEqual(environment.requestedKeys, ["ANTHROPIC_API_KEY"])
        let invocations = await countProbe.invocations()
        XCTAssertTrue(invocations.isEmpty)
    }

    func testCompiledFailureLeavesExistingOutputUnchanged() throws {
        let input = try temporaryFile(named: "invalid.txt", data: Data([0xff]))
        let directory = input.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("result.txt")
        try Data("KEEP".utf8).write(to: output)

        let result = try CLITestHelper.convert(
            to: "tokens",
            input: input.path,
            flags: ["--model", "gpt-4o", "--output", output.path]
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(result.stderr, "Error: token 計數輸入必須是有效 UTF-8\n")
        XCTAssertEqual(try Data(contentsOf: output), Data("KEEP".utf8))
    }

    func testCompiledInputAboveByteLimitFailsBeforeOutput() throws {
        let input = try temporaryFile(
            named: "too-large.txt",
            data: Data(repeating: 0x61, count: 1_000_001)
        )
        defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }

        let result = try CLITestHelper.convert(
            to: "tokens",
            input: input.path,
            flags: ["--model", "gpt-4o"]
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(
            result.stderr,
            "Error: token 計數輸入不得超過 1000000 UTF-8 bytes\n"
        )
    }

    func testCompiledTokenOnlyOptionsAreRejectedOnOtherRoutes() throws {
        let input = try temporaryFile(named: "sample.md", data: Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }

        let result = try CLITestHelper.convert(
            to: "html",
            input: input.path,
            flags: ["--model", "gpt-4o"]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("tokens"), result.stderr)
    }

    func testCompiledFormatFlagsAreRejectedOnTokenRoute() throws {
        let input = try temporaryFile(named: "sample.md", data: Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }

        for flags in [
            ["--css", "minimal"],
            ["--hard-breaks"],
            ["--full"],
            ["--frontmatter"],
            ["--html-extensions"],
        ] {
            let result = try CLITestHelper.convert(
                to: "tokens",
                input: input.path,
                flags: ["--model", "gpt-4o"] + flags
            )

            XCTAssertNotEqual(result.exitCode, 0)
            XCTAssertEqual(result.stdout, "")
            XCTAssertTrue(result.stderr.contains(flags[0]), result.stderr)
        }
    }

    func testTokenDocumentationSeparatesCompiledAndPackageEvidence() throws {
        let root = CLITestHelper.repoRoot
        for name in ["README.md", "CONVERSIONS.md"] {
            let text = try String(
                contentsOf: root.appendingPathComponent(name),
                encoding: .utf8
            )
            XCTAssertTrue(text.contains("macOS 27.0（arm64）、Apple Swift 6.3.3"), name)
            XCTAssertTrue(text.contains("狀態為 `verified`"), name)
            XCTAssertTrue(text.contains("`hello world` exact-byte acceptance"), name)
            XCTAssertTrue(text.contains("五組官方 Python `tiktoken`"), name)
            XCTAssertTrue(text.contains("`implemented-not-live-verified`"), name)
            XCTAssertTrue(text.contains("`not-supported`"), name)
        }
    }
}

private enum StubCountError: Error {
    case failed
}

private enum StubProviderFailure: String, Error, CaseIterable, Sendable {
    case authentication
    case rateLimit
    case timeout
    case redirect
    case oversizedResponse
    case malformedResponse
}

private final class ProviderFailureCommandProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let failure: StubProviderFailure
    private var localSuccesses = 0
    private var transportCalls = 0

    var transport: FailingAnthropicTransport {
        FailingAnthropicTransport(failure: failure, probe: self)
    }

    init(failure: StubProviderFailure) {
        self.failure = failure
    }

    func recordLocalSuccess(_ count: TokenCount) {
        guard count.model == .gpt4o, count.source == .local else {
            return
        }
        lock.withLock { localSuccesses += 1 }
    }

    var localSuccessCount: Int {
        lock.withLock { localSuccesses }
    }

    func recordTransportCall() {
        lock.withLock { transportCalls += 1 }
    }

    var transportCallCount: Int {
        lock.withLock { transportCalls }
    }
}

private struct FailingAnthropicTransport: AnthropicTokenCountTransport {
    let failure: StubProviderFailure
    let probe: ProviderFailureCommandProbe

    func countTokens(request _: AnthropicTokenCountRequest) async throws -> Data {
        probe.recordTransportCall()
        throw failure.typedError
    }

    var callCount: Int {
        probe.transportCallCount
    }
}

private extension StubProviderFailure {
    var typedError: AnthropicTokenCountError {
        switch self {
        case .authentication:
            .authenticationFailed
        case .rateLimit:
            .rateLimited
        case .timeout:
            .timedOut
        case .redirect:
            .redirectRejected
        case .oversizedResponse:
            .responseTooLarge(limit: 65_536)
        case .malformedResponse:
            .invalidResponse
        }
    }
}

private actor CountInvocationProbe {
    struct Invocation: Sendable {
        let text: String
        let models: [TokenModel]
        let apiKey: String?
    }

    private let result: [TokenCount]
    private var recorded: [Invocation] = []

    init(result: [TokenCount]) {
        self.result = result
    }

    func count(text: String, models: [TokenModel], apiKey: String?) -> [TokenCount] {
        recorded.append(Invocation(text: text, models: models, apiKey: apiKey))
        return result
    }

    func invocations() -> [Invocation] {
        recorded
    }
}

private actor NonCooperativeCountGate {
    private var started = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var resultContinuation: CheckedContinuation<[TokenCount], Never>?

    func count() async -> [TokenCount] {
        started = true
        let waiters = startedWaiters
        startedWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startedWaiters.append(continuation)
        }
    }

    func release(_ result: [TokenCount]) {
        resultContinuation?.resume(returning: result)
        resultContinuation = nil
    }
}

private final class SynchronousEnvironmentProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let values: [String: String]
    private var keys: [String] = []

    init(values: [String: String]) {
        self.values = values
    }

    var requestedKeys: [String] {
        lock.withLock { keys }
    }

    func read(_ key: String) -> String? {
        lock.withLock { keys.append(key) }
        return values[key]
    }
}

private func temporaryFile(named name: String, data: Data) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("TokenCountCommandTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent(name)
    try data.write(to: file)
    return file
}

private func temporaryIsolationEnvironment() throws -> (
    root: URL,
    environment: [String: String]
) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("TokenCountIsolation-\(UUID().uuidString)", isDirectory: true)
    let home = root.appendingPathComponent("home", isDirectory: true)
    let cache = root.appendingPathComponent("cache", isDirectory: true)
    let temporary = root.appendingPathComponent("tmp", isDirectory: true)
    for directory in [home, cache, temporary] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    return (
        root,
        [
            "HOME": home.path,
            "CFFIXED_USER_HOME": home.path,
            "XDG_CACHE_HOME": cache.path,
            "TMPDIR": temporary.path,
            "TIKTOKEN_CACHE_DIR": cache.appendingPathComponent("tiktoken").path,
            "DATA_GYM_CACHE_DIR": cache.appendingPathComponent("data-gym").path,
            "ANTHROPIC_API_KEY": "",
        ]
    )
}

private func relativeRegularFilePaths(in root: URL) throws -> [String] {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey]
    ) else {
        return []
    }
    return try enumerator.compactMap { item in
        guard let url = item as? URL,
              try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        else {
            return nil
        }
        return String(url.path.dropFirst(root.path.count + 1))
    }.sorted()
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        // Expected.
    }
}
