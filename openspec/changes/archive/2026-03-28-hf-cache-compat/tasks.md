## 1. Add Fallback Cache Lookup

- [x] 1.1 Add `findCachedModel(repo:)` private method to `ModelLoader` — first check `hf` CLI path (`models--<org>--<name>/snapshots/*/`) for complete model, follow symlinks, pick most recent snapshot (requirement: fallback cache lookup for hf CLI downloads, requirement: model downloaded by hf CLI is recognized, requirement: hf CLI snapshot with symlinks)
- [x] 1.2 In `findCachedModel`, add Hub Swift path fallback (`models/<org>/<name>/`) for `config.json` + `*.safetensors` (requirement: Hub Swift cached model is recognized, requirement: incomplete cached model is ignored)
- [x] 1.3 Wire `findCachedModel` into `ensureModel` — call before `HubApi.snapshot`, return early if found (requirement: cache compatibility with HuggingFace Hub convention, requirement: no cached model found)

## 2. Testing

- [x] 2.1 Test Hub Swift cache hit: create temp dir with `models/org/name/` containing config.json + fake safetensors, verify `findCachedModel` returns path (requirement: Hub Swift cached model is recognized)
- [x] 2.2 Test hf CLI cache hit: create temp dir with `models--org--name/snapshots/abc123/` containing config.json + fake safetensors, verify `findCachedModel` returns snapshot path (requirement: model downloaded by hf CLI is recognized)
- [x] 2.3 Test incomplete cache ignored: create temp dir with only config.json (no safetensors), verify `findCachedModel` returns nil (requirement: incomplete cached model is ignored)
- [x] 2.4 Test multiple snapshots: create two snapshot dirs with different modification times, verify most recent is returned (requirement: multiple snapshots from hf CLI)
- [x] 2.5 Integration test: verify `macdoc ocr` works with existing `hf` CLI downloaded model at `~/.cache/huggingface/hub/models--EZCon--GLM-OCR-8bit-mlx/`
