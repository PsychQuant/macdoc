## 1. Package Contract and Red Tests

- [x] 1.1 Create the importable `TokenCounter` product in `packages/token-counter-swift`, pin `DePasqualeOrg/swift-tiktoken` at revision `b4310ee520995ddff45b055de19e6605e0f8e5b6`, expose it through the root package, and update `.gitignore`; verify the **Use a local provider-neutral token counter package** build contract with `swift package describe` in both package roots and a test target that imports `TokenCounter`.
- [x] [P] 1.2 Add failing reference-vector and resource-integrity tests for **Offline GPT-4o counting** and **Bundle and verify the OpenAI vocabulary**, covering empty, ASCII, Traditional Chinese, mixed-script, emoji, the fixed SHA-256, corrupted resource bytes, and no downloader/cache invocation; verify the tests fail for missing local tokenizer behavior before production code is added.
- [x] [P] 1.3 Add failing stub-transport tests for **Explicit Anthropic network consent and credentials** and the **Anthropic request and response contract**, covering the fixed request, 2xx parsing, 401/403, 429, other status, redirect, 30-second timeout, streaming 64-KiB cap, malformed values, zero retries, and redacted errors; verify every test fails against the unimplemented provider without contacting the live endpoint.
- [x] [P] 1.4 Add failing service tests for **Reusable service behavior**, proving requested model order, exact model allow-listing, and atomic multi-provider failure; verify the tests fail until the typed models, counts, provider source, injectable transport, and asynchronous service exist.

## 2. Provider Implementations

- [x] 2.1 Implement the typed models, count values, errors, provider adapters, and ordered `TokenCounterService` described by **Behavior and interfaces** and **Scope boundaries**; verify the service tests from 1.4 pass and unsupported or duplicate model requests have deterministic typed outcomes.
- [x] 2.2 Bundle the audited `o200k_base.tiktoken` resource, verify its SHA-256 before parsing, construct the pinned pure-Swift `CoreBPE`, and prohibit runtime downloads or cache writes; verify the tests from 1.2 pass plus a sandboxed package test confirms GPT-4o counting creates no network, cache, or home-directory artifact.
- [x] 2.3 Implement the fixed-endpoint Anthropic transport and error mapping required by **Require explicit consent for Anthropic disclosure** and **Failure modes**, including streaming response enforcement and content/credential redaction; verify all tests from 1.3 pass with the stub transport and no live credential.

## 3. CLI Admission, Rendering, and Atomic Output

- [x] 3.1 Add failing compiled-command and command-factory tests for **Token counting command and supported models**, **Input admission and boundaries**, **Deterministic output and atomic presentation**, and **Token-route option validation**; cover exact 1,000,000/1,000,001-byte boundaries, invalid UTF-8, empty input, arbitrary extensions, option scoping, fixed numeric/table bytes, missing consent/key, and unchanged destinations, and verify the new assertions are red before CLI wiring.
- [x] 3.2 Extend `macdoc convert` with `tokens`, `--model`, and `--allow-network`, validate the complete input before counting, and render only after every requested provider succeeds as specified by **Validate the complete input before counting** and **Render stable all-or-nothing CLI output**; verify the tests from 3.1 pass with empty stdout on every failure and absent or byte-unchanged `--output` destinations.
- [x] 3.3 Connect the CLI to an injectable environment and Anthropic transport so tests can prove preflight makes zero requests and production reads `ANTHROPIC_API_KEY` only for consented Claude counts; verify success and every local/provider error through the command factory without exposing keys, headers, source text, or full response bodies.

## 4. End-to-End Acceptance

- [x] 4.1 Implement **Token-counting route coverage** through the compiled executable for offline GPT-4o stdout, `--output`, unsupported model, invalid UTF-8, size rejection, default consent failure, and missing Claude credentials; verify exact exit codes and bytes while networking and tokenizer caches are unavailable.
- [x] 4.2 Implement **Token-counting provider isolation** and **Test providers and the compiled command without live services** by exercising dual-model piping and provider failures with an injected stub, then verify authentication, rate-limit, timeout, redirect, oversized, and malformed responses never require a live key and never produce partial output.

## 5. Documentation and Release Verification

- [x] [P] 5.1 Update `README.md` and `CONVERSIONS.md` for **User-facing privacy and platform documentation** and **Document provider and platform boundaries**, including exact commands/output, accepted models, byte limit, offline resource, `ANTHROPIC_API_KEY`, per-invocation disclosure consent, Anthropic estimate semantics, and evidence-backed platform states; verify the documented examples match captured CLI acceptance bytes and pass the platform block validator.
- [x] 5.2 Confirm the complete **Acceptance criteria** by running the local package tests, root `swift test`, compiled-binary offline acceptance, official-vector comparison, secret/redaction checks, `spectra validate macdoc-token-counting`, and `git diff --check`; record the exact command results and verify `Package.resolved` pins the audited tokenizer revision with no live Anthropic call.

### Verification evidence — 2026-08-13

- `swift test` in `packages/token-counter-swift`: 19 tests, 0 failures (8.797 s), including 5 official Python `tiktoken` vectors, resource-integrity checks, no-cache/HOME isolation, all Anthropic status/limit/error mappings, and redaction assertions.
- Root `swift test`: 37 XCTest cases (3 environment-gated skips) plus 26 Swift Testing cases, 63 total, 0 failures. `TokenCountCommandTests` contributed 18 compiled/factory cases, 0 failures.
- Compiled GPT-4o acceptance ran under `sandbox-exec` with `(deny network*)`, isolated HOME/cache/TMP, exact stdout `2\n`, and no newly created isolation files. Successful `--output` wrote exact `2\n` with empty stdout.
- The six injected provider failures (authentication, rate limit, timeout, redirect, oversized response, malformed response) returned no renderable value and left absent/existing destinations absent/byte-identical; no live Anthropic credential or endpoint was used.
- `spectra validate macdoc-token-counting`: `valid`; artifact analysis: 0 Critical, 0 Warning (4 non-blocking example Suggestions).
- `o200k_base.tiktoken` SHA-256: `446a9538cb6c348e3516120d7c08b09f57c36495e2acfffe59a5bf8b0cfb1a2d`.
- Root and package `Package.resolved`, plus package manifest, pin `swift-tiktoken` revision `b4310ee520995ddff45b055de19e6605e0f8e5b6`.
- `swift package describe --type json` passed in both roots; `git diff --check`, platform-block gate, and secret/private-path scan passed.
- Evidence environment: macOS 27.0 arm64, Apple Swift 6.3.3. No live Anthropic call was made.
