## MODIFIED Requirements

### Requirement: Page-level OCR via GLM-OCR

The system SHALL provide page-level OCR using a pluggable VLM backend as the primary text extraction method for the pdf-to-latex pipeline, replacing block-level segmentation and per-block AI transcription. The backend SHALL be selected at invocation time from three options: `openai` (OpenAI-compatible HTTP server; default), `ollama` (Ollama's native `/api/generate` protocol), or `mlx` (in-process MLX inference via `mlx-swift-lm`). Model name SHALL be resolvable from `AIConfig.ocrDefaultModel` when not explicitly provided, with a compatibility shim mapping the legacy `"glm-ocr"` config value to `mlx-community/Qwen3-VL-4B-Instruct-4bit` when routed through the `mlx` backend. The original GLM-OCR-only requirement is superseded: `GLM-OCR` is no longer the primary path; the model name is resolved at runtime and defaults continue to work for users with `ocrDefaultModel == "glm-ocr"` by routing through whichever backend (openai/ollama/mlx) actually has a working GLM-OCR model available.

#### Scenario: OCR a vector PDF page with PDFKit cross-validation

- **WHEN** the user runs `macdoc pdf ocr --project <dir>` on a vector PDF with the default backend
- **THEN** the system renders each page to PNG at the configured DPI
- **AND** extracts text via PDFKit for each page
- **AND** POSTs the rendered image base64-encoded to `http://<AIConfig.ocrDefaultHost>:<port>/v1/chat/completions`
- **AND** stores both PDFKit text and VLM-recognized text in the manifest as `PageOCRResult`
- **AND** computes agreement ratio between PDFKit and VLM outputs

#### Scenario: OCR a scanned PDF page (no PDFKit)

- **WHEN** the user runs `macdoc pdf ocr --project <dir>` on a scanned PDF with the default backend
- **THEN** the system renders each page to PNG
- **AND** sends each page to the configured OpenAI-compatible server
- **AND** stores the VLM result in the manifest (pdfkitText is nil)

#### Scenario: OCR with Ollama native backend

- **WHEN** the user runs `macdoc pdf ocr --project <dir> --backend ollama`
- **THEN** the system sends each rendered page image to the configured Ollama host via the native `/api/generate` HTTP endpoint
- **AND** uses `AIConfig.ocrDefaultModel` (default `"glm-ocr"`) as the Ollama model name
- **AND** stores results in the same `PageOCRResult` format

#### Scenario: OCR with MLX local backend

- **WHEN** the user runs `macdoc pdf ocr --project <dir> --backend mlx`
- **THEN** the system loads a VLM container in-process via `mlx-swift-lm`
- **AND** if `AIConfig.ocrDefaultModel == "glm-ocr"`, the MLX model repo is resolved to `mlx-community/Qwen3-VL-4B-Instruct-4bit` per the compatibility shim (avoiding the broken `EZCon/GLM-OCR-8bit-mlx` third-party quant)
- **AND** emits the VLM output into `PageOCRResult`

#### Scenario: OCR specific page range

- **WHEN** the user specifies `--first-page 5 --last-page 10`
- **THEN** only pages 5 through 10 are rendered and OCR'd
- **AND** existing results for other pages in the manifest are preserved

## ADDED Requirements

### Requirement: OpenAI-compatible HTTP backend is the default OCR path

The `AIConfig.ocrDefaultBackend` value SHALL default to `"openai"`. This means a fresh install of macdoc with no user config makes `macdoc ocr image.png` and `macdoc pdf ocr --project <dir>` send requests to `http://localhost:11434/v1/chat/completions` (the default host preserves backwards compatibility with existing Ollama users, because Ollama exposes both its native `/api/generate` and an OpenAI-compatible `/v1/chat/completions` on the same port). Users running LM Studio, oMLX, or any other OpenAI-compatible local server SHALL be able to point macdoc at their server by running `macdoc config ocr set-host <hostname>:<port>` without any code changes or backend-switching.

#### Scenario: Default OCR request targets OpenAI-compatible endpoint

- **WHEN** a user runs `macdoc ocr image.png` on a fresh install with no prior config
- **THEN** macdoc resolves `AIConfig.ocrDefaultBackend == "openai"`, `AIConfig.ocrDefaultHost == "localhost:11434"`, and `AIConfig.ocrDefaultModel == "glm-ocr"`
- **AND** sends a POST request to `http://localhost:11434/v1/chat/completions`
- **AND** if an Ollama server is listening on port 11434, the request succeeds and returns recognized text; if no server is listening, the request fails with a connection-refused error whose message includes the effective URL and names all three supported server options

#### Scenario: LM Studio user redirects via config

- **WHEN** a user runs `macdoc config ocr add-host lm-studio localhost:1234 && macdoc config ocr set-default-host lm-studio`
- **THEN** subsequent `macdoc ocr` invocations POST to `http://localhost:1234/v1/chat/completions`
- **AND** no code change, no restart, no re-linking is required

#### Scenario: oMLX user redirects via config

- **WHEN** a user runs `macdoc config ocr add-host omlx localhost:8000 && macdoc config ocr set-default-host omlx`
- **THEN** subsequent `macdoc ocr` invocations POST to `http://localhost:8000/v1/chat/completions`
- **AND** macdoc retrieves recognized text from `choices[0].message.content` of the OpenAI-shaped response

### Requirement: OpenAIBackend request format

The `OpenAIBackend` implementation of `OCRBackend` SHALL construct each OCR request with the following JSON body:

```json
{
  "model": "<user-configured model>",
  "messages": [
    {
      "role": "user",
      "content": [
        {"type": "text", "text": "OCR the text in this image. Output the exact text as it appears."},
        {"type": "image_url", "image_url": {"url": "data:image/png;base64,<base64-encoded-png>"}}
      ]
    }
  ],
  "max_tokens": 4096,
  "temperature": 0.0,
  "stream": false
}
```

The backend SHALL set `Content-Type: application/json`; SHALL set `Authorization: Bearer <apiKey>` only when the configured `apiKey` is non-empty; SHALL parse the response expecting `choices[0].message.content` as the recognized text; SHALL map non-2xx HTTP status codes to `OpenAIBackendError.serverError(code, body)` and malformed JSON to `OpenAIBackendError.invalidResponse`.

#### Scenario: Standard OCR request against LM Studio

- **WHEN** `OpenAIBackend(host: "localhost:1234", model: "qwen2.5-vl:7b").processImage(pngData)` is called
- **THEN** a POST request is sent to `http://localhost:1234/v1/chat/completions`
- **AND** the request body contains exactly the JSON shape defined above with `model = "qwen2.5-vl:7b"`
- **AND** no `Authorization` header is present because `apiKey` is not set
- **AND** the returned text matches `choices[0].message.content` from the server's response

#### Scenario: Server error surfaces structured diagnostic

- **WHEN** the configured server returns HTTP 500 with body `{"error":"model not loaded"}`
- **THEN** `OpenAIBackend.processImage(...)` throws `OpenAIBackendError.serverError(500, "{\"error\":\"model not loaded\"}")`
- **AND** the error's `localizedDescription` includes both the status code and the server's body so the user can diagnose

#### Scenario: Malformed JSON response

- **WHEN** the configured server returns HTTP 200 with body `not-json`
- **THEN** `OpenAIBackend.processImage(...)` throws `OpenAIBackendError.invalidResponse`

### Requirement: pdf ocr and top-level ocr subcommands share backend resolution

`macdoc pdf ocr --project <dir>` SHALL resolve its OCR backend, host, and model via the same `AIConfig`-backed path used by the top-level `macdoc ocr` subcommand. The hardcoded `@Option var model: String = "EZCon/GLM-OCR-8bit-mlx"` default in `MacDoc+PDF.swift` SHALL be removed; when the user does not pass `--model`, the value SHALL be resolved from `AIConfig.ocrDefaultModel` with the same compatibility-shim semantics as top-level `ocr`.

#### Scenario: pdf ocr default matches top-level ocr default

- **WHEN** a user with default config runs both `macdoc ocr image.png` and `macdoc pdf ocr --project /path/to/project`
- **THEN** both invocations resolve to the same backend (`openai`), same host (`localhost:11434`), and same model (`"glm-ocr"`, which the Ollama path interprets directly or the MLX path shims to `Qwen3-VL-4B-Instruct-4bit`)
- **AND** neither invocation emits garbage output from `EZCon/GLM-OCR-8bit-mlx`

#### Scenario: pdf ocr explicit override

- **WHEN** a user runs `macdoc pdf ocr --project /path --backend mlx --model mlx-community/Qwen3-VL-4B-Instruct-4bit`
- **THEN** the command ignores AIConfig defaults and uses the explicitly-passed backend + model
- **AND** the MLX backend loads in-process per existing `MLXBackend.load(...)` semantics

### Requirement: Backend test coverage via URLProtocol mock

The `ocr-swift` test suite SHALL include unit tests for `OpenAIBackend` and `OllamaBackend` that exercise URL construction, request body shape, response parsing, and error paths without downloading VLM models or requiring a running server. Tests SHALL use a `URLProtocol` subclass registered on an ephemeral `URLSessionConfiguration` to intercept requests. The test suite SHALL fail (exit non-zero) when any of the asserted behaviours regresses.

#### Scenario: OpenAIBackend URL construction test

- **WHEN** the test initializes `OpenAIBackend(host: "example.test:9999", model: "m1")` and calls `processImage(pngData)`
- **THEN** the intercepted request's URL matches `http://example.test:9999/v1/chat/completions` exactly
- **AND** the request method is `POST`
- **AND** the request body JSON contains `model == "m1"` and a single `messages` entry with text + image_url content items

#### Scenario: Ollama backend regression coverage

- **WHEN** the test initializes `OllamaBackend(host: "example.test:11434", model: "llava")` and calls `processImage(pngData)`
- **THEN** the intercepted request's URL matches `http://example.test:11434/api/generate` exactly
- **AND** the request body JSON contains `model == "llava"`, `images` as an array with a single base64 string, and `stream == false`

### Requirement: MLXBackend remains opt-in with documented upstream dependency

`MLXBackend` SHALL remain available but SHALL NOT be the default backend. Its docstring SHALL document that `ml-explore/mlx-swift-lm#191` (`broadcast_shapes` VLM inference crash) is a known blocker in some environments (confirmed in macOS 26.0 Tahoe on M4 Max; maintainer unable to reproduce), that upgrading `mlx-swift-lm` to 3.31.3 does not resolve the bug (version diff of `GlmOcr.swift` and `Qwen3VL.swift` shows only import-statement changes between 2.31.3 and 3.31.3), and that `OpenAIBackend` pointed at LM Studio, oMLX, or Ollama is the recommended alternative. The backend SHALL NOT be removed from the public API; users on unaffected environments SHALL be able to invoke it via `--backend mlx`.

#### Scenario: MLXBackend opt-in via explicit flag

- **WHEN** a user runs `macdoc ocr image.png --backend mlx --model mlx-community/Qwen3-VL-4B-Instruct-4bit`
- **THEN** macdoc loads the MLX container and runs VLM inference in-process
- **AND** if the environment triggers `#191`, the user sees the `broadcast_shapes` crash; this is an accepted risk of choosing the MLX backend explicitly

#### Scenario: MLX docstring references the upstream bug

- **WHEN** a developer reads `MLXBackend.swift` source
- **THEN** the file-level docstring names `ml-explore/mlx-swift-lm#191`, notes the 2.31.3-vs-3.31.3 equivalence for affected files, and directs readers to `OpenAIBackend` as the recommended production path
