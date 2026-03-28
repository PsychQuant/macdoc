## Problem

`ModelLoader.ensureModel` uses `HubApi.snapshot` from `swift-transformers` to download models. Hub Swift stores files at `~/.cache/huggingface/hub/models/<org>/<name>/` and requires `.cache/huggingface/download/` metadata to recognize cached files. Without this metadata, Hub Swift re-downloads the entire model on every call — even when the files already exist locally.

This causes two failures:

1. **hf CLI downloads not recognized**: Models downloaded via `hf download` (Python CLI) are stored at `~/.cache/huggingface/hub/models--<org>--<name>/snapshots/<commit>/` with blob symlinks. Hub Swift cannot find these files because the path structure is completely different.

2. **Hub Swift's own partial downloads not recognized**: When Hub Swift downloads files but fails before completing all files (network drop), it has the files on disk but no metadata. On retry, it re-downloads everything from scratch instead of resuming.

Both violate the `mlx-model-management` spec requirement: "Existing models downloaded by the previous hand-written downloader or by `hf` CLI SHALL remain usable without re-download."

## Root Cause

Hub Swift (`HubApi`) and `hf` CLI (Python `huggingface_hub`) use fundamentally different cache layouts:

| Tool | Cache path | Metadata |
|------|-----------|----------|
| Hub Swift | `<base>/models/<org>/<name>/` | `.cache/huggingface/download/*.json` |
| hf CLI (Python) | `<base>/models--<org>--<name>/snapshots/<commit>/` | `refs/`, `blobs/`, symlinks |

There is no shared convention. Hub Swift's `snapshot` method checks its own metadata to determine if files are cached; without metadata, it assumes nothing is cached.

## Proposed Solution

Add a fallback cache lookup to `ModelLoader.ensureModel` that checks known cache paths before calling `HubApi.snapshot`:

1. Check `hf` CLI path first (`models--<org>--<name>/snapshots/*/`) — this is the most common pre-download path, and `hf` CLI is more reliable for large files (multi-connection, xet protocol)
2. Check Hub Swift path (`models/<org>/<name>/`) — for models previously downloaded by `HubApi.snapshot`
3. A model is "complete" if the directory contains `config.json` and at least one `.safetensors` file
4. If found at either location, return that path directly — skip `HubApi.snapshot` entirely
5. If not found anywhere, fall through to `HubApi.snapshot` (current behavior)

**Note**: Investigation confirmed that MLX Swift Hub (`mlx-swift-examples`) uses the exact same `HubApi` from `swift-transformers` — there is no separate Apple download mechanism. The `hf` CLI (Python/Rust) remains the most robust way to pre-download large models.

## Non-Goals

- Unifying the two cache formats (they are maintained by different ecosystems)
- Writing Hub Swift metadata for `hf` CLI downloads (fragile, metadata format may change)
- Supporting other download tools (aria2c, wget, curl)
- Modifying `swift-transformers` Hub module upstream

## Success Criteria

- `macdoc ocr` works immediately after `hf download EZCon/GLM-OCR-8bit-mlx` without re-downloading
- `macdoc ocr` works immediately if model files already exist at the Hub Swift cache path with config.json + safetensors present
- `macdoc ocr` still downloads automatically if no cached model exists anywhere
- No changes to public API signatures

## Impact

- Affected specs: `mlx-model-management` (modifying cache compatibility requirement scenarios)
- Affected code:
  - `packages/ocr-swift/Sources/OCRCore/Models/ModelLoader.swift` — add fallback cache lookup
  - `packages/ocr-swift/Tests/OCRCoreTests/ModelLoaderTests.swift` — add cache fallback tests
