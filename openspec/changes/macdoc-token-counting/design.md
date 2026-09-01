## Context

`macdoc convert` currently routes document formats but has no token-counting route. Issue #20 requires OpenAI and Anthropic counts through the same CLI entry point. The two providers have materially different trust boundaries: GPT-4o can be counted locally with the published `o200k_base` vocabulary, while Anthropic exposes token counting through the authenticated Message Token Count API. The implementation therefore spans CLI parsing, a reusable Swift package, a bundled tokenizer resource, HTTP transport, deterministic rendering, tests, and user-facing privacy documentation.

The OpenAI implementation has no official Swift package. The design pins the pure-Swift `DePasqualeOrg/swift-tiktoken` implementation at revision `b4310ee520995ddff45b055de19e6605e0f8e5b6`, isolates it behind this project's API, and loads an audited bundled vocabulary instead of using the dependency's runtime downloader. The bundled `o200k_base.tiktoken` resource has SHA-256 `446a9538cb6c348e3516120d7c08b09f57c36495e2acfffe59a5bf8b0cfb1a2d` and is cross-checked against OpenAI's Python `tiktoken` reference implementation.

Anthropic counting uses `POST https://api.anthropic.com/v1/messages/count_tokens` with `x-api-key`, `anthropic-version: 2023-06-01`, the selected model, and one user text message. Anthropic describes the response as an input-token estimate that can vary when tokenizer behavior changes, so the CLI reports the provider-returned count without claiming a locally reproducible exact value.

## Goals / Non-Goals

**Goals:**

- Add deterministic token-counting behavior to `macdoc convert --to tokens`.
- Keep GPT-4o counting offline after installation, including vocabulary loading.
- Require explicit per-invocation consent before sending file contents to Anthropic.
- Provide a reusable, injectable Swift API with typed errors and no secret or content logging.
- Make single-model and dual-model output stable for shell pipelines.
- Verify the compiled CLI, tokenizer vectors, resource integrity, HTTP request shape, failure mapping, and no-partial-output behavior.

**Non-Goals:**

- Counting chat templates, system prompts, tool schemas, images, PDFs, or non-UTF-8 inputs.
- Calculating API prices, billing estimates, completion tokens, or context-window availability.
- Calling an OpenAI network API or downloading tokenizer files at runtime.
- Supporting arbitrary OpenAI or Anthropic model identifiers in the first release.
- Adding stdin input, streaming output, retries, proxy configuration, or a user-configurable Anthropic endpoint.
- Claiming byte-for-byte parity between Anthropic's evolving service result and an offline tokenizer.

## Decisions

### Use a local provider-neutral token counter package

Create `packages/token-counter-swift` with a `TokenCounter` product. Its public surface uses a model enum rather than arbitrary strings:

```swift
public enum TokenModel: String, CaseIterable, Sendable {
    case gpt4o = "gpt-4o"
    case claudeSonnet46 = "claude-sonnet-4-6"
}

public struct TokenCount: Equatable, Sendable {
    public let model: TokenModel
    public let tokens: Int
    public let source: Source
}

public protocol AnthropicTokenCountTransport: Sendable {
    func countTokens(request: AnthropicTokenCountRequest) async throws -> Data
}

public struct TokenCounterService: Sendable {
    public init(
        anthropicAPIKey: String? = nil,
        anthropicTransport: (any AnthropicTokenCountTransport)? = nil
    ) throws
    public func count(text: String, models: [TokenModel]) async throws -> [TokenCount]
}

public enum AnthropicTokenCountError: Error, Equatable, Sendable {
    case authenticationFailed, rateLimited, redirectRejected, timedOut, invalidResponse
    case providerFailure(statusCode: Int)
    case responseTooLarge(limit: Int)
}
```

`TokenCounterService` preserves model order and returns results only after every requested provider succeeds. OpenAI and Anthropic implementations remain internal details except for the public injectable Anthropic transport and package-owned typed errors used by tests and future callers. The OpenAI adapter normalizes third-party tokenizer failures to `TokenCounterError`. The Anthropic adapter independently rejects injected responses above 64 KiB and normalizes every non-package error to a redacted `AnthropicTokenCountError`, so a public extension point cannot leak credentials, source text, headers, or provider bodies through an arbitrary error description. The default GPT provider loads its resource lazily only when GPT-4o is requested. This avoids coupling CLI output or external callers to third-party package types. A CLI-only implementation was rejected because it would make transport tests and future reuse unnecessarily difficult.

### Bundle and verify the OpenAI vocabulary

The local package pins the pure-Swift BPE dependency by exact Git revision and instantiates its public `CoreBPE` using a parser owned by `TokenCounter`. The package bundles `o200k_base.tiktoken`, verifies its fixed SHA-256 before parsing, and never calls the dependency's download or cache code. GPT-4o maps only to `o200k_base`; unsupported model identifiers fail before file counting.

Reference tests compare empty, ASCII, Traditional Chinese, mixed-script, and emoji strings with token IDs or counts generated by the official Python `tiktoken` package. Resource-corruption tests use an injected resource loader so the production resource remains immutable. Vendoring a second BPE algorithm was rejected because it would duplicate security-sensitive parsing and merge logic; downloading the vocabulary was rejected because it would violate the offline requirement.

### Require explicit consent for Anthropic disclosure

Any requested model set containing `claude-sonnet-4-6` requires both `--allow-network` and a non-empty `ANTHROPIC_API_KEY`. Validation happens before the Anthropic transport is constructed or called. The endpoint is fixed, redirects are rejected, request and resource timeouts are 30 seconds, and the response body limit is 64 KiB. The production loader uses a `URLSessionDataDelegate` rather than `AsyncBytes` or an independently producing stream. At each callback it copies at most the remaining limit plus one overflow-detection byte into package-owned storage and cancels immediately after the first overflow. Foundation controls callback chunk size and may transiently deliver a chunk larger than the retained bound; the contract therefore bounds package-owned retained bytes to 65,537 rather than making an impossible claim about Foundation's internal/network buffering. Non-success responses are cancelled after their status is known without retaining the body. The client performs no automatic retry.

The JSON request is `{ "model": "claude-sonnet-4-6", "messages": [{ "role": "user", "content": <file text> }] }`. The client accepts only a successful 2xx response containing a non-negative integer `input_tokens`. It maps 401 and 403 to authentication failure, 429 to rate limiting, other non-2xx responses to a provider failure, timeout to a transport timeout, and invalid or oversized JSON to an invalid-response error. Errors omit API keys, request headers, request bodies, and source text. A hidden or environment-only consent mechanism was rejected because possession of an API key is not consent to disclose the current file.

### Validate the complete input before counting

The CLI opens the final input pathname once with `O_NOFOLLOW`, validates the opened object with `fstat`, and reads through that same descriptor. It accepts only a regular file with a maximum size of 1,000,000 bytes, then decodes it strictly as UTF-8. A pathname swap after open cannot redirect the read, and a final-entry symlink is rejected. Directories, invalid UTF-8, and larger files fail before any provider call. Empty UTF-8 files are valid: the local result is zero and the Anthropic result is whatever non-negative count the endpoint returns.

The byte limit gives both providers the same deterministic admission rule and remains below the local BPE implementation's one-million-character ceiling. Truncation was rejected because a plausible-looking partial count is unsafe for automation.

### Render stable all-or-nothing CLI output

The CLI adds `--model` and `--allow-network` to `convert`. These options are valid only when `--to tokens` is selected. Supported model values are exactly `gpt-4o` and `claude-sonnet-4-6`. With `--model`, success writes one base-10 integer and a trailing newline. Without `--model`, the ordered model set is GPT-4o followed by Claude Sonnet 4.6 and success writes:

```text
Model\tTokens
gpt-4o\t1234
claude-sonnet-4-6\t1198
```

Numbers use ASCII digits without locale grouping. The command completes all requested counts in memory before writing stdout or `--output`, so provider failure produces no partial table or partial output file. Existing global error handling writes a concise diagnostic to stderr and returns non-zero. The token route ignores input filename extensions because it operates on UTF-8 text; format-specific flags such as `--css`, `--full`, and `--frontmatter` are rejected rather than silently ignored.

### Test providers and the compiled command without live services

Library tests use reference vectors, an injected vocabulary loader, and a stub Anthropic transport. They assert exact request headers and JSON, success parsing, authentication and rate-limit mapping, timeout, redirect rejection, response-size enforcement, malformed JSON, secret redaction, preserved model order, and all-or-nothing results.

CLI tests invoke the compiled executable for local GPT-4o success, stable numeric and table rendering, `--output`, invalid options, invalid UTF-8, the size boundary, missing consent, and missing key. Provider-failure tests use the same command execution/output seam as production: local GPT succeeds first, an injected Anthropic transport produces each typed failure, and the returned command result must be non-zero with empty stdout and an absent or byte-unchanged destination. Cancellation is checked before and after provider work and again before presentation, so a cancelled operation cannot publish a buffered success. Descriptor swap and symlink tests cover input admission. End-to-end acceptance includes one offline compiled GPT-4o invocation with networking unavailable; the five official tiktoken reference vectors run in the package suite.

### Document provider and platform boundaries

`README.md` and `CONVERSIONS.md` describe accepted models, output formats, the 1,000,000-byte UTF-8 limit, `ANTHROPIC_API_KEY`, `--allow-network`, disclosure of the entire file to Anthropic, Anthropic's estimate semantics, and GPT-4o's offline resource. Each document carries an explicit platform, toolchain, state, and evidence block: compiled and tested behavior receives `verified`, the stub-only Anthropic layer remains `implemented-not-live-verified`, and platforms without a compatible manifest remain `not-supported`. The compiled `hello world` acceptance and the five package-level official reference vectors are reported separately rather than combined into one claim.

## Implementation Contract

### Behavior and interfaces

- `macdoc convert --to tokens <file> --model gpt-4o` counts the complete UTF-8 file locally and emits exactly `<integer>\n`.
- `macdoc convert --to tokens <file> --model claude-sonnet-4-6 --allow-network` sends the complete file as one Anthropic user text message and emits exactly the returned non-negative `input_tokens` followed by a newline.
- `macdoc convert --to tokens <file> --allow-network` requests models in the fixed order `gpt-4o`, `claude-sonnet-4-6` and emits the fixed tab-separated header and two rows.
- Anthropic requests require a non-empty `ANTHROPIC_API_KEY`; the key is supplied only through the `x-api-key` header.
- `TokenCounterService.count(text:models:)` returns one `TokenCount` per requested model in input order or throws without returning a partial array.
- Output destinations use the existing `--output` behavior, but bytes are written only after all counts succeed.

### Failure modes

- Unsupported models, token-only flags on other routes, unrelated conversion flags on the token route, non-files, oversized input, and invalid UTF-8 fail locally before counting or network activity.
- Missing network consent and missing Anthropic credentials have distinct actionable errors.
- Authentication, rate limiting, timeout, redirect, oversized response, malformed response, and other provider status errors remain distinct typed library errors and concise CLI diagnostics.
- No error includes the API key, source text, full provider response body, or request headers.
- Any dual-provider failure leaves stdout empty and leaves a requested output path absent or unchanged.

### Acceptance criteria

- Reference-vector tests match official Python `tiktoken` results for the bundled resource, whose SHA-256 is verified in production loading.
- A compiled-binary GPT-4o test passes with networking disabled and without cache or home-directory writes.
- Stub-transport tests prove Anthropic request shape, fixed endpoint, consent preflight, error mapping, body limit, and redaction.
- CLI tests prove exact output bytes, model ordering, validation boundaries, and no partial stdout or file output.
- Package and repository test suites pass without a live Anthropic credential.
- Documentation states the network disclosure and platform evidence without representing Anthropic estimates as offline-exact values.

### Scope boundaries

Only UTF-8 file text, `gpt-4o`, and `claude-sonnet-4-6` are in scope. Chat-template overhead, additional models, completion-token prediction, cost calculation, stdin, streaming, runtime vocabulary downloads, configurable endpoints, and live-provider tests are excluded.

## Risks / Trade-offs

- [Risk] The pinned pure-Swift tokenizer is a young third-party dependency. → Mitigation: pin the exact revision, isolate it behind local types, verify the resource digest, cross-check official reference vectors, and retain the option to replace the adapter without changing CLI behavior.
- [Risk] Anthropic tokenizer behavior can change for the same public model name. → Mitigation: label the value as provider-reported input tokens, test only response handling locally, and avoid freezing a fabricated local equivalence.
- [Risk] Default dual-model mode discloses the file if consent is given. → Mitigation: require `--allow-network` on every invocation containing Claude, validate before network activity, and document the full-file disclosure next to usage examples.
- [Risk] Dual-model requests add latency and can fail after local counting completes. → Mitigation: buffer every result and emit nothing until all providers succeed.
- [Risk] The bundled vocabulary increases repository and binary size. → Mitigation: include only `o200k_base`, record its digest and provenance, and reject runtime downloads.
- [Risk] Foundation owns callback chunk allocation, so no URLSession API can cap transient framework buffering to one byte beyond the body limit. → Mitigation: use the data-delegate callback directly, retain at most 65,537 package-owned bytes, cancel on the first overflow callback, avoid an independently producing bridge, and state this boundary precisely.
- [Risk] A public injected transport could return oversized bytes or throw a sensitive arbitrary error. → Mitigation: independently size-check its returned `Data` and normalize every non-package error before it crosses the public service boundary.

## Migration Plan

1. Add and test the isolated token-counter package and pinned dependency.
2. Integrate the package into the root executable and add the CLI route behind the new target value.
3. Add compiled-binary and provider-stub acceptance tests before documenting the route as available.
4. Update route documentation and platform evidence in the same release.
5. Roll back by removing the token route and package dependency; existing conversion routes and file formats remain unchanged because the feature adds no persistent data migration.

## Open Questions

None. Additional models require a separate proposal with tokenizer mapping, provider semantics, and new reference evidence.
