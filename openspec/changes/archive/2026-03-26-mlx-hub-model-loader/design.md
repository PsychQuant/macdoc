## Context

`ocr-swift` is a local Swift package in the macdoc monorepo that runs GLM-OCR (a vision-language model) via MLX for PDF/image → Markdown OCR. Its `ModelLoader` struct handles downloading safetensors from HuggingFace using raw `URLSession.shared.download(from:)` — no resume, no retry, no timeout. Models are 2-4 GB; downloads fail on unstable connections.

The package already depends on `mlx-swift` (MLX, MLXNN, MLXFast, MLXRandom). The `mlx-swift-examples` repository provides a `Hub` module that wraps HuggingFace Hub operations (file listing, resumable download, local cache management) and is designed to work with the MLX Swift ecosystem.

Current `ModelLoader` cache path: `~/.cache/huggingface/hub/models--<org>--<name>/snapshots/main/` — this already matches HF Hub convention, so switching to Hub should be cache-compatible.

## Goals / Non-Goals

**Goals:**

- Replace hand-written download logic with Hub's battle-tested implementation
- Gain resume support for interrupted large file downloads
- Maintain the existing `ModelLoader` public API so `OCRPipeline` and `MacDoc+OCR.swift` require zero changes
- Remain cache-compatible with existing downloaded models (no re-download after upgrade)

**Non-Goals:**

- Modifying `surya-swift`'s CoreML `ModelLoader` (different package, different model format)
- Adding model quantization or conversion capabilities
- Supporting authenticated/private HF repos (public models only for now)
- Replacing `loadWeights` — MLX's `loadArrays(url:)` is already correct for safetensors

## Decisions

### Use Hub module from swift-transformers (already a dependency)

Discovery during implementation: `swift-transformers` (already depended on for `Tokenizers`) includes a `Hub` module with `HubApi.snapshot(from:matching:progressHandler:)` — full HF model downloading with resume, metadata validation, and progress reporting. `OCRPipeline` already does `import Hub`.

**Decision**: Use `HubApi.snapshot` from `swift-transformers`. No new dependency needed. The `Hub` target is available transitively through `Tokenizers → Hub`.

Key API: `HubApi(downloadBase:).snapshot(from: repoId, matching: globs, progressHandler:) async throws -> URL`

### Keep ModelLoader as a struct with the same public API

The three public methods stay unchanged:

- `ensureModel(repo:progressHandler:) async throws -> URL` — now delegates to Hub
- `loadConfig(from:) throws -> GlmOcrConfig` — unchanged (reads local JSON)
- `loadWeights(from:) throws -> [String: MLXArray]` — unchanged (reads local safetensors)

Only `ensureModel` internals change. `loadConfig` and `loadWeights` operate on local files and are unaffected.

### Remove hand-written HF API and download methods

Delete these private methods from `ModelLoader`:

- `listRepoFiles(repo:matching:)` — replaced by Hub's file listing
- `downloadFile(repo:filename:to:)` — replaced by Hub's resumable download
- `matchGlob(pattern:string:)` — no longer needed

## Risks / Trade-offs

- **[Risk] `mlx-swift-examples` API instability** — This is a sample/examples repo, not a versioned library. API may change without notice. → Mitigation: Pin to a specific commit/tag in `Package.swift`. The `ensureModel` boundary means internal Hub API changes only affect one method.
- **[Risk] Dependency size increase** — `MLXLMCommon` may bring in tokenizer and model factory code unused by `ocr-swift`. → Mitigation: Swift Package Manager only compiles what's imported. Monitor build time; extract if problematic.
- **[Risk] Cache format mismatch** — Hub may use a slightly different directory structure than our current hand-rolled cache. → Mitigation: Verify Hub uses the same `models--org--name/snapshots/<ref>/` layout before merging. If different, add a one-time migration or symlink.
