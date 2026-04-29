## Problem

`macdoc ocr` (and `macdoc pdf ocr`) currently has three OCR backend paths, two of which are unreliable or narrow:

1. **MLX backend** (`MLXBackend` in `ocr-swift`) — native Swift VLM inference via `mlx-swift-lm`. Currently blocked by upstream bug `ml-explore/mlx-swift-lm#191` (`broadcast_shapes (20) and (300)` crash on any VLM inference in our macOS 26.0 Tahoe + M4 Max environment). Upstream maintainer could not reproduce (2026-04-07); second user reported same crash on `main` branch (2026-04-14). Version bump 2.31.3 → 3.31.3 does not help (diff between versions only removes 2 import lines; RoPE logic unchanged).

2. **Ollama backend** (`OllamaBackend` in `ocr-swift`) — works, but hardcodes Ollama-specific `/api/generate` endpoint. Users running LM Studio, llama.cpp server, vLLM, or any other OpenAI-compatible local server cannot use macdoc OCR without running Ollama alongside.

3. **Hardcoded GLM-OCR default in `pdf ocr`** (`Sources/MacDocCLI/MacDoc+PDF.swift:203`) — defaults to `EZCon/GLM-OCR-8bit-mlx`, a third-party 8-bit MLX quantization that is affected by `#191`. Inconsistent with top-level `ocr` subcommand which already silently redirects `glm-ocr` → `Qwen3-VL-4B-Instruct-4bit` via compatibility shim (`MacDoc+OCR.swift:60-65`).

Result: PsychQuant/macdoc#66 (P1 bug, opened 2026-03-28) remains unresolved three weeks later because the default path is broken and the workaround path (Ollama) requires a non-native daemon. `ocr-swift` has zero backend coverage in its test suite (`Tests/OCRCoreTests/` only tests `PDFKitExtractor`) so regressions are undetectable.

## Root Cause

Two independent issues compound:

- **Upstream**: `mlx-swift-lm#191` is environment-specific and unresponsive. Maintainer can't reproduce; waiting on upstream is open-ended.
- **Local**: `OllamaBackend` is tightly coupled to Ollama's proprietary `/api/generate` API instead of the widely-adopted OpenAI-compatible `/v1/chat/completions`. This forces users to pick Ollama specifically rather than whichever local inference server they already run (LM Studio is popular on macOS because it uses MLX internally via Python `mlx-vlm`, which is a **different binding** from Swift `mlx-swift-lm` and therefore **not affected by #191**).

## Proposed Solution

Four coordinated changes, scoped to one Spectra change and one PR:

1. **Add `OpenAIBackend` to `ocr-swift`** — new `OCRBackend` implementation that POSTs to an OpenAI-compatible `/v1/chat/completions` endpoint with `model`, `messages`, and `image_url` (base64 data URL). Accepts `host`, optional `apiKey`, `model`, and `endpoint` (defaults to `/v1/chat/completions`). This single backend works with:
   - **LM Studio** at `http://localhost:1234` (GUI app; MLX-backed on Apple Silicon)
   - **Ollama** at `http://localhost:11434/v1/chat/completions` (Ollama speaks both its native `/api/generate` and OpenAI-compat)
   - **oMLX** at `http://localhost:8000/v1` ([jundot/omlx](https://github.com/jundot/omlx) — Apache-2.0 Mac-native MLX server with continuous batching + KV cache tiering; menu-bar-managed)
   - **llama.cpp server, vLLM, text-generation-webui**, and any OpenAI API hoster

2. **Make `OpenAIBackend` the default** — `AIConfig.ocrDefaultBackend` switches from `"ollama"` to `"openai"`; `MacDoc+OCR.swift` backend resolution adds `"openai"` case; documented default host is `localhost:11434` (Ollama's port) so existing Ollama users keep working without config changes, but can point at LM Studio via `config ocr add-host lm-studio localhost:1234 && config ocr set-default lm-studio`.

3. **Unify `pdf ocr` with top-level `ocr`** — drop `EZCon/GLM-OCR-8bit-mlx` hardcoded default from `MacDoc+PDF.swift:203`; route through the same `AIConfig`-based resolution as top-level `ocr`. Users with `ocrDefaultModel = "glm-ocr"` continue to get the `Qwen3-VL` compat-shim redirect (already in place).

4. **Add minimal backend smoke tests** — new `Tests/OCRCoreTests/OpenAIBackendTests.swift` and `OllamaBackendTests.swift` exercising URL construction, request payload shape, response parsing, and error handling via mocked `URLSession`. No model downloads required. Covers the regression-detection gap that let #66 sit for 3 weeks.

## Non-Goals

- **Not fixing `mlx-swift-lm#191`** upstream — out of our control. `MLXBackend` is left in place as opt-in with its existing docstring warning; docstring is updated with version observation (2.31.3 identical to 3.31.3 for this bug).
- **Not deprecating `OllamaBackend`** — kept for users who prefer the native `/api/generate` path (supports Ollama-specific features like streaming chunk parsing that `/v1/chat/completions` abstracts away). Both backends coexist.
- **Not adding a model catalog UI** — macdoc stays CLI-only; model selection is by name string via `--model` or `config ocr set-model`. LM Studio users manage their models via LM Studio's own UI.
- **Not switching native SDK integration** — macdoc talks HTTP to whatever server the user runs. No Swift-level integration with LM Studio's private APIs, no Python subprocess.
- **Not adding automatic fallback between backends** — if the configured backend fails (connection refused, 500, etc.), macdoc surfaces the error; it does NOT silently retry with a different backend. Fallback-on-failure has UX / debuggability tradeoffs better addressed as a separate feature.
- **Not upgrading `mlx-swift-lm` to 3.31.3** — version diff confirmed irrelevant to `#191`; upgrade would be cost-without-benefit. Keep 2.31.3 pin.
- **Not running Track A reproduction** (from earlier `/spectra-discuss`) — already validated via direct repo inspection that upgrade path doesn't help; skipping saves ~30 min of local setup that wouldn't change the proposal.

## Success Criteria

- `macdoc ocr image.png` on a fresh install with only LM Studio running (no Ollama) produces recognized text — end-to-end success without Ollama.
- `macdoc ocr image.png` on a fresh install with only Ollama running produces recognized text — backwards-compatible with current users.
- `macdoc pdf ocr --project /path` does NOT default to `EZCon/GLM-OCR-8bit-mlx`; instead uses whatever `AIConfig.ocrDefaultModel` resolves to (default: Qwen3-VL via compat shim).
- `swift test` in `ocr-swift` exercises `OpenAIBackend` and `OllamaBackend` URL construction, payload shape, and response parsing via `URLProtocol` mock — regressions are caught before release.
- PsychQuant/macdoc#66 can close with a Closing Summary pointing at this change + confirming the test suite would now flag the regression.

## Impact

- **Affected specs**: 1 modified — `simplified-pdf-ocr` (current Requirement "Page-level OCR via GLM-OCR" loosens to "Page-level OCR via configured VLM backend"). `mlx-model-management` is NOT modified (it's about download mechanics, not backend selection).
- **Affected code**:
  - `packages/ocr-swift` (remote `PsychQuant/ocr-swift`):
    - NEW: `Sources/OCRCore/Backends/OpenAIBackend.swift`
    - NEW: `Tests/OCRCoreTests/OpenAIBackendTests.swift` (URLProtocol mock)
    - NEW: `Tests/OCRCoreTests/OllamaBackendTests.swift` (URLProtocol mock for existing backend — regression coverage)
    - MODIFIED: `Sources/OCRCore/Backends/MLXBackend.swift` — docstring update (link `#191`, version finding)
    - Tag: `v0.2.0` (minor bump — new public backend class is additive but worth signalling)
  - `Sources/MacDocCLI/MacDoc+OCR.swift`:
    - MODIFIED: backend switch adds `case "openai":` branch constructing `OpenAIBackend(host:, model:)`
  - `Sources/MacDocCLI/MacDoc+PDF.swift`:
    - MODIFIED: drop `@Option default = "EZCon/GLM-OCR-8bit-mlx"` in favour of AIConfig resolution path
    - MODIFIED: phase-2 `pdf ocr` help text updated to reference AIConfig model-default
  - `Sources/MacDocCLI/MacDoc+Config.swift`:
    - MODIFIED: `config ocr set backend` accepts `openai` as third valid value
  - `macdoc/Package.swift`: bump `ocr-swift` pin from `from: "0.1.0"` to `from: "0.2.0"`
  - `AIConfig.swift` in `pdf-to-latex-swift` (the shared config owner): change `ocrDefaultBackend` default from `"ollama"` to `"openai"`.
- **Affected dependencies**: no external additions. `OpenAIBackend` uses only `Foundation.URLSession`.
- **Docs**:
  - `macdoc/CLAUDE.md`: update OCR section to document the 3 backend options with URLs for LM Studio + Ollama port defaults
  - `macdoc/SECURITY.md`: note that local OCR backends expose a local HTTP port; document which port is which
  - `macdoc/openspec/specs/simplified-pdf-ocr/spec.md`: loosen requirement text per Modified Capabilities above
- **End-user impact**:
  - Existing Ollama users: zero config change required. `OpenAIBackend` at default host `localhost:11434` hits Ollama's `/v1/chat/completions` (Ollama speaks both protocols).
  - LM Studio users (new): one-time `config ocr set-host localhost:1234` gets them working.
  - oMLX users (new): one-time `config ocr set-host localhost:8000` gets them working (plus set-model to whatever they loaded).
  - MLX users (rare, since default was already effectively Qwen3-VL): unchanged; still via `--backend mlx`.
  - `pdf ocr` users: previously silently broken (GLM-OCR → garbage); now silently works (AIConfig route).
- **PsychQuant/macdoc#66**: closes after this change merges; Closing Summary points at `ocr-openai-compat-backend` Spectra change.
- **Release**: one new `ocr-swift@0.2.0` tag; one macdoc PR bumping the pin + code changes.
