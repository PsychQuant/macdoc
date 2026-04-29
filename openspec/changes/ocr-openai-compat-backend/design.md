## Context

macdoc's OCR pipeline (`OCRPipeline` in `ocr-swift`) delegates image recognition to a pluggable `OCRBackend` protocol. Two implementations exist as of 2026-04-21:

- `MLXBackend` — loads a VLM in-process via `mlx-swift-lm` (pinned at 2.31.3) and runs inference on Apple Silicon
- `OllamaBackend` — POSTs to Ollama's native `/api/generate` HTTP endpoint

The MLX path is blocked by upstream `ml-explore/mlx-swift-lm#191` — a `broadcast_shapes (20) and (300)` crash in VLM inference. The bug was filed by macdoc's own maintainer 2026-04-07 and remains open; maintainer cannot reproduce, a second user reports identical crash on `main` 2026-04-14. Direct inspection of `GlmOcr.swift` and `Qwen3VL.swift` at tags 2.31.3 vs 3.31.3 shows only 2-line diffs (removed `import Hub` / `import Tokenizers`), so upgrading doesn't help.

The Ollama path works but couples macdoc to one specific local-server implementation. Mac-native alternatives popular with the target audience (Taiwanese research/teaching workflow, Apple Silicon) include:

- **LM Studio** — closed-source GUI; uses Python `mlx-vlm` internally (a different MLX binding, not affected by `#191`)
- **oMLX** ([jundot/omlx](https://github.com/jundot/omlx)) — Apache-2.0 Python server; continuous batching + SSD-tiered KV cache; managed from menu bar; OpenAI + Anthropic API compat
- **llama.cpp server** — CLI / headless; wide model format support

All three expose OpenAI-compatible `/v1/chat/completions` with base64-or-URL image inputs. Ollama additionally exposes OpenAI-compat alongside its native API. Therefore the strategic win is a single `OpenAIBackend` that fits all servers, not a per-server backend.

Stakeholders: `macdoc` CLI users (primary — Taiwanese academic workflow, Apple Silicon, mixed familiarity with local-server daemons); `ocr-swift` as a reusable library (secondary — currently only macdoc imports it, but the interface should stay clean for future consumers). Constraints: macOS 14+ target; macOS 26.0 Tahoe is the environment where `#191` manifests; no internet-dependent API keys (local-server-first). Must not degrade UX for existing Ollama users.

## Goals / Non-Goals

**Goals:**

- Close PsychQuant/macdoc#66 by providing a reliable default OCR path that does not depend on `mlx-swift-lm#191` resolution.
- Support LM Studio, oMLX, Ollama, llama.cpp server, and any OpenAI-compat HTTP hoster behind **one** `OpenAIBackend`.
- Eliminate the hardcoded `EZCon/GLM-OCR-8bit-mlx` default in `pdf ocr` that currently gives users garbage output.
- Establish backend-level regression coverage in `ocr-swift` (currently zero backend tests).
- Preserve `MLXBackend` as opt-in for users whose environment does not trip `#191` (maintainer's environment is one such).
- Keep existing Ollama users working without config changes on upgrade.

**Non-Goals:**

- Fix `mlx-swift-lm#191` upstream.
- Deprecate `OllamaBackend` — keep as native-protocol option.
- Add UI / model catalog to macdoc — stays CLI-only.
- Automatic backend fallback on failure — explicit-failure UX is clearer for debugging.
- Upgrade `mlx-swift-lm` to 3.31.3 — diff confirms irrelevant to `#191`.
- Add Anthropic API support (oMLX exposes it, but macdoc OCR does not need tool-calling / thinking-block semantics).
- Streaming response consumption — OCR returns one coherent text chunk; streaming adds complexity without end-user benefit.
- Integration tests that download real VLM weights — out of scope for unit coverage; manual verification only.

## Decisions

### Single `OpenAIBackend` over per-server backends

One `OpenAIBackend` accepting `host`, `apiKey?`, `model`, `endpoint?` covers LM Studio / oMLX / Ollama-OAI / llama.cpp / vLLM. Alternatives considered: (a) separate `LMStudioBackend` / `OMLXBackend` — rejected because 90% of the code would be duplicated; any per-server quirks can be handled by the `endpoint` parameter or a small request-transform closure if ever needed; (b) abstract `OpenAIBackend` + concrete subclasses per server — over-engineered for the single-endpoint case.

### Default to `OpenAIBackend` pointing at `localhost:11434`

`AIConfig.ocrDefaultBackend` switches from `"ollama"` (native Ollama protocol) to `"openai"` (generic OpenAI-compat). Default host stays at `localhost:11434` — Ollama's port, which Ollama-speaks-OpenAI-compat means existing Ollama users experience zero change. Alternatives: (a) default to LM Studio's `1234` — rejected because LM Studio must be GUI-launched and is not all users' choice; (b) default to oMLX's `8000` — rejected for same reason; (c) auto-probe which port is up — rejected because silent auto-detection masks misconfiguration.

### Keep `OllamaBackend` for native `/api/generate` path

Don't remove `OllamaBackend`. Ollama's native API has slight operational advantages (richer streaming event format, Ollama-specific model-loading lifecycle APIs, no `/v1` path prefix). Users invoking `--backend ollama` keep that path. Alternatives: (a) remove — rejected because it's a regression for users who explicitly chose Ollama native; (b) auto-redirect `ollama` → `openai` — rejected because the user's explicit choice is signal, not friction to eliminate.

### Unify `pdf ocr` with top-level `ocr` via AIConfig

`MacDoc+PDF.swift:203` currently sets `@Option var model: String = "EZCon/GLM-OCR-8bit-mlx"` — a hardcoded default that bypasses AIConfig entirely and points at the broken 8-bit quant. Replace with `@Option var model: String? = nil` and resolve via the same AIConfig-backed path as `MacDoc+OCR.swift:60-65`. Alternatives: (a) keep two separate defaults — rejected because users running `pdf ocr` with no flags currently get silent garbage; (b) add a `pdf ocr`-specific config key — rejected because there is no principled reason the two subcommands should diverge; they are both VLM OCR against an image stream.

### `OpenAIBackend` request shape

POST body follows the OpenAI Vision request template:

```json
{
  "model": "<user-configured model>",
  "messages": [
    {
      "role": "user",
      "content": [
        {"type": "text", "text": "OCR the text in this image. Output the exact text as it appears."},
        {"type": "image_url", "image_url": {"url": "data:image/png;base64,<b64>"}}
      ]
    }
  ],
  "max_tokens": 4096,
  "temperature": 0.0,
  "stream": false
}
```

Response is parsed from `choices[0].message.content`. Error handling: non-2xx → `OpenAIBackendError.serverError(code, body)`; JSON decode failure → `.invalidResponse`; URL construction failure → `.invalidHost(host)`. Alternatives: (a) use `tools` API for structured output — rejected as unnecessary; OCR wants plain text; (b) use `response_format: {"type": "text"}` — not all servers support this parameter, sticking to plain text keeps compatibility wider.

### Backend tests via `URLProtocol` mock (no model downloads)

Both `OpenAIBackendTests` and `OllamaBackendTests` use a `URLProtocol` subclass (registered on `URLSessionConfiguration.ephemeral`) to intercept requests. Tests assert: (a) request URL + method + headers, (b) request body JSON shape, (c) response parsing, (d) error paths. No `URLSession` hits real servers; no model downloads. Alternatives: (a) `MockURLSession` custom class — `URLProtocol` is standard and reusable; (b) integration test with an actually-running Ollama — requires CI infrastructure we don't want to take on.

### Release as `ocr-swift@0.2.0`

New public class `OpenAIBackend` is additive but significant — users will feel the default-change. Minor bump signals that meaningfully. Alternatives: (a) patch bump 0.1.x — masks a default-change that's user-visible; (b) major bump 1.0.0 — overstates stability claim given the package is <2 months old.

## Risks / Trade-offs

- **Risk**: User has Ollama running but not on default port `11434` — their OCR silently tries the wrong endpoint and fails with connection-refused. → **Mitigation**: error message includes the effective host URL so the user sees where it tried; `config ocr list` is prominently documented in the error output.
- **Risk**: User has no local server running at all and `OpenAIBackend` is default — first-run UX is "Error: Connection refused at localhost:11434". → **Mitigation**: error message explicitly suggests "start Ollama (`brew services start ollama`), LM Studio, or oMLX, then retry"; CLAUDE.md documents the server-install-first expectation.
- **Risk**: Different servers differ on how they accept `image_url` (data URL vs external URL vs custom). → **Mitigation**: we use data-URL base64 which is the common denominator; all four target servers (LM Studio / oMLX / Ollama / llama.cpp) accept this form per their docs. Any server that doesn't is out of scope.
- **Risk**: OpenAI spec allows `max_tokens` but some servers (newer API versions) prefer `max_completion_tokens`. → **Mitigation**: ship with `max_tokens` (widest compat on local servers as of 2026-04); revisit if community servers migrate.
- **Risk**: `--backend openai` name is generic; users may confuse it with "requires an OpenAI API key". → **Mitigation**: help text says "--backend openai (OpenAI-compatible server: LM Studio, oMLX, Ollama's /v1, etc.; does NOT require a real OpenAI API key)"; `apiKey` is optional with default empty.
- **Risk**: Existing `config ocr set backend ollama` users get auto-migrated behaviour (same port, same model) but not if their model name is Ollama-specific (e.g. tag syntax `glm-ocr:latest`). → **Mitigation**: test with Ollama's `ollama pull glm-ocr:latest` + `macdoc ocr X --backend openai` — confirm Ollama's OAI layer accepts this tag syntax; if not, document the caveat.
- **Risk**: Changing `pdf ocr` default from MLX to AIConfig-resolved means users whose config says `mlx` + `glm-ocr` still get the compat-shim Qwen3-VL redirect (which also may crash per `#191`). → **Mitigation**: the compat shim was added by `#84` specifically for this reason; users who want MLX explicitly can pass `--backend mlx --model glm-ocr` and accept the `#191` risk.
- **Risk**: Backend tests using `URLProtocol` cover happy path + basic errors but not network flakiness (timeout, partial response, HTTP/2 streams). → **Mitigation**: accepted for v0.2.0; add later if users hit edge cases.
- **Trade-off**: Adding `OpenAIBackend` grows the public API surface of `ocr-swift`. Anyone extending the package later has one more thing to know. Accepted because the payoff (four server supports from one backend) dominates the cost.
- **Trade-off**: Default-host `localhost:11434` means a Macbook with zero local servers + fresh install gets a connection-refused error on first `macdoc ocr`. Accepted because there is no principled alternative — we need the user to have chosen and run *some* local server, and the error with clear next-steps is better than silent fallback to cloud APIs.

## Migration Plan

**Pre-flight**: confirm current state — `ocr-swift@0.1.0` pinned in macdoc; no other consumers of `ocr-swift` exist in PsychQuant org (verified by `gh search`).

**Phase 1 — `ocr-swift@0.2.0`** (in `PsychQuant/ocr-swift` remote):
1. Add `Sources/OCRCore/Backends/OpenAIBackend.swift` with `OpenAIBackendError` enum + `OpenAIBackend` struct implementing `OCRBackend`.
2. Add `Tests/OCRCoreTests/OpenAIBackendTests.swift` with `URLProtocol` mock — cases: success, 4xx error, 5xx error, malformed JSON, invalid host, large image (>2MB base64).
3. Add `Tests/OCRCoreTests/OllamaBackendTests.swift` mirroring the above structure for the existing `OllamaBackend` (regression coverage — this was the gap that let `#66` fester).
4. Update `MLXBackend.swift` docstring with reference to `#191` + version-independence finding (no action beyond docstring).
5. `swift test` green locally → commit → tag `v0.2.0` → push.

**Phase 2 — macdoc wiring**:
1. `Package.swift`: bump `ocr-swift` pin to `from: "0.2.0"`.
2. `Sources/MacDocCLI/MacDoc+OCR.swift`: add `case "openai":` branch constructing `OpenAIBackend` from config; update help text for `--backend` flag.
3. `Sources/MacDocCLI/MacDoc+PDF.swift`: change `@Option var model: String = "EZCon/GLM-OCR-8bit-mlx"` to `@Option var model: String? = nil`; route through AIConfig resolution identical to `MacDoc+OCR.swift`.
4. `Sources/MacDocCLI/MacDoc+Config.swift`: accept `"openai"` as valid `ocrDefaultBackend` value; extend help text.
5. `pdf-to-latex-swift/AIConfig.swift`: change `ocrDefaultBackend` default from `"ollama"` to `"openai"`. Tag `pdf-to-latex-swift@0.1.x` if that package owns AIConfig; verify ownership during implementation.

**Phase 3 — Tests + docs**:
1. `Tests/MacDocCLITests`: add a smoke test that `macdoc ocr` with no flags produces a meaningful error when no server is reachable (specifically, error text contains "localhost:11434" and suggestion to start Ollama/LM Studio/oMLX). `XCTSkip` if a server IS running.
2. `macdoc/CLAUDE.md`: update OCR section with the three supported server options + port table + example commands for each.
3. `macdoc/SECURITY.md`: add a note to "Private-repo policy" section mentioning that local OCR backends expose HTTP ports (11434 / 1234 / 8000) on loopback only.
4. `macdoc/openspec/specs/simplified-pdf-ocr/spec.md`: after archive, reflect the Modified Capabilities — requirement text changes from "Page-level OCR via GLM-OCR" to "Page-level OCR via configured OpenAI-compatible VLM backend". Already-archived changes keep historical context.

**Phase 4 — close out**:
1. Open PR against `main` with title `fix: OpenAI-compat OCR backend (#66)`.
2. After merge → `/idd-close #66` with Closing Summary pointing at this Spectra change.
3. `/spectra-archive ocr-openai-compat-backend` → updates `simplified-pdf-ocr` spec + creates timestamped archive.

**Rollback**: symmetric. `macdoc/Package.swift` revert to `from: "0.1.0"` + `git revert` the `MacDoc+*.swift` changes. `ocr-swift@0.2.0` tag stays published (no harm). `AIConfig.ocrDefaultBackend` default rolls back to `"ollama"` — existing users' saved config files are unaffected because saved values are serialised, not defaulted.

## Open Questions

None remaining — all decisions resolved via `/spectra-discuss` (2026-04-21) + this design doc:

1. Scope: narrow to `#66` close → resolved.
2. Backend strategy: single `OpenAIBackend` → resolved.
3. Server defaults: default host `11434` (Ollama compat) → resolved.
4. Test strategy: `URLProtocol` mocks, no model downloads → resolved.
5. `mlx-swift-lm` upgrade: skip, 2.31.3 == 3.31.3 for affected code → resolved.
6. Release strategy: `ocr-swift@0.2.0` minor bump → resolved.
7. Supported servers: LM Studio + oMLX + Ollama + llama.cpp (generic) → resolved.
