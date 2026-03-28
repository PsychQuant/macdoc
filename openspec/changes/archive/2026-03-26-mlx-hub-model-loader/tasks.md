## 1. Dependency Setup

- [x] 1.1 Add `mlx-swift-examples` Hub dependency to `packages/ocr-swift/Package.swift` — use MLXLMCommon Hub module (decision: use MLXLMCommon Hub module from mlx-swift-examples)
- [x] 1.2 Verify `swift build` succeeds in `packages/ocr-swift/` with the new dependency
- [x] 1.3 Verify cache compatibility: confirm Hub uses `~/.cache/huggingface/hub/models--<org>--<name>/` layout matching the existing hand-written cache (requirement: cache compatibility with HuggingFace Hub convention)

## 2. Rewrite ModelLoader Download Logic

- [x] 2.1 Replace `ensureModel` internals with Hub download API — delegate file listing and resumable download to Hub (requirement: automatic model download on first use, requirement: resumable downloads for large files)
- [x] 2.2 Wire Hub's progress callback to the existing `progressHandler: ((String, Double) -> Void)?` parameter (requirement: download progress reporting)
- [x] 2.3 Remove hand-written HF API and download methods: delete `listRepoFiles`, `downloadFile`, and `matchGlob` private methods (decision: remove hand-written HF API and download methods)
- [x] 2.4 Preserve `ModelLoader` public API: `ensureModel`, `loadConfig`, `loadWeights` signatures unchanged (requirement: public API preservation, decision: keep ModelLoader as a struct with the same public API)

## 3. Error Handling

- [x] 3.1 Map Hub error types to existing `ModelLoaderError` cases — `downloadFailed`, `httpError` (requirement: invalid repo identifier scenario from support arbitrary MLX model repos)
- [x] 3.2 Handle interrupted downloads gracefully: verify Hub resumes from partial state, and handles corrupted partials by re-downloading (requirement: resumable downloads for large files — corrupted partial download scenario)

## 4. Testing

- [x] 4.1 Test cached model recognition: verify `ensureModel` returns immediately when model exists locally without network calls (requirement: automatic model download on first use — model already cached scenario)
- [x] 4.2 Test arbitrary model repo support: verify `ensureModel` accepts any `org/model-name` format (requirement: support arbitrary MLX model repos)
- [x] 4.3 Test error case: verify invalid repo throws `ModelLoaderError.downloadFailed` (requirement: support arbitrary MLX model repos — invalid repo identifier scenario)
- [x] 4.4 Integration test: run `macdoc ocr` end-to-end with a small test image to verify the full pipeline works with Hub-based loading

## 5. Cleanup

- [x] 5.1 Pin `mlx-swift-examples` dependency to a specific commit or tag in `Package.swift` to guard against API instability (risk mitigation from design)
- [x] 5.2 Update `packages/ocr-swift/README.md` to document Hub-based model management and cache location
