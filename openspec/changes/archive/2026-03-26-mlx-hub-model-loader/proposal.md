## Why

The `ocr-swift` package's `ModelLoader` uses bare `URLSession.shared.download(from:)` to fetch HuggingFace models (safetensors, typically 2-4 GB). There is no resume, no retry, and no timeout configuration. Large downloads fail silently on unstable connections, leaving users unable to use OCR — a core macdoc feature. Additionally, macdoc will support multiple MLX models long-term (not just GLM-OCR), requiring a robust model management layer rather than hand-rolled download logic.

## What Changes

- Replace the hand-written HF download logic in `ocr-swift`'s `ModelLoader` with the MLX Swift Hub module (`MLXLMCommon` or the `Hub` subpackage from `mlx-swift-examples`)
- Hub handles: HF API file listing, download with resume, local cache at `~/.cache/huggingface/hub`, progress reporting
- `ModelLoader`'s public API (`ensureModel`, `loadConfig`, `loadWeights`) stays unchanged — only the download implementation is swapped
- Remove `listRepoFiles`, `downloadFile`, and `matchGlob` private methods (replaced by Hub)
- Add `mlx-swift-examples` (Hub module) as a dependency to `ocr-swift/Package.swift`

## Non-Goals

- Changing `surya-swift`'s CoreML model loading — that package stays as-is
- Adding model conversion (CoreML ↔ MLX) — models must already be in MLX-compatible format on HF
- Building a custom download manager with URLSession background transfers
- Supporting non-HuggingFace model sources

## Capabilities

### New Capabilities

- `mlx-model-management`: Robust MLX model downloading, caching, and lifecycle management via HuggingFace Hub, with resume support and progress reporting

### Modified Capabilities

(none)

## Impact

- Affected code:
  - `packages/ocr-swift/Package.swift` — add `mlx-swift-examples` Hub dependency
  - `packages/ocr-swift/Sources/OCRCore/Models/ModelLoader.swift` — rewrite download logic
  - `packages/ocr-swift/Sources/OCRCore/Pipeline/OCRPipeline.swift` — may need minor adjustment for Hub API
- Affected dependencies: new dependency on `mlx-swift-examples` (Hub module)
- No breaking changes to macdoc CLI (`MacDoc+OCR.swift` unchanged)
