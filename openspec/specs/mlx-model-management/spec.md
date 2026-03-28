# mlx-model-management Specification

## Purpose

TBD - created by archiving change 'mlx-hub-model-loader'. Update Purpose after archive.

## Requirements

### Requirement: Automatic model download on first use

The system SHALL automatically download the requested MLX model from HuggingFace Hub when `ensureModel(repo:)` is called and the model is not present in local cache. The download SHALL use the Hub module from `mlx-swift-examples` for resumable transfers.

#### Scenario: First-time model download

- **WHEN** `ensureModel(repo: "EZCon/GLM-OCR-8bit-mlx")` is called and no cached model exists at `~/.cache/huggingface/hub/models--EZCon--GLM-OCR-8bit-mlx/`
- **THEN** the system downloads all required files (config.json, safetensors, tokenizer files) from HuggingFace Hub to the local cache directory and returns the path to the cached model directory

#### Scenario: Model already cached

- **WHEN** `ensureModel(repo: "EZCon/GLM-OCR-8bit-mlx")` is called and the model files already exist in local cache
- **THEN** the system returns the cached model directory path without making any network requests


<!-- @trace
source: mlx-hub-model-loader
updated: 2026-03-26
code:
  - AGENTS.md
  - Tests/MacDocCLITests/ConvertRouteTests.swift
  - CONVERSIONS.md
  - .spectra.yaml
  - CLAUDE.md
  - Tests/MacDocCLITests/ErrorHandlingTests.swift
  - .github/skills/spectra-apply/SKILL.md
  - .github/skills/spectra-audit/SKILL.md
  - .github/prompts/spectra-propose.prompt.md
  - .agents/skills/spectra-archive/SKILL.md
  - Tests/MacDocCLITests/FixtureManager.swift
  - .agents/skills/spectra-audit/SKILL.md
  - .github/prompts/spectra-ingest.prompt.md
  - .github/skills/spectra-debug/SKILL.md
  - .github/skills/spectra-archive/SKILL.md
  - .github/skills/spectra-propose/SKILL.md
  - .github/skills/spectra-ask/SKILL.md
  - GEMINI.md
  - .agents/skills/spectra-debug/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - .github/skills/spectra-discuss/SKILL.md
  - .github/skills/spectra-ingest/SKILL.md
  - .github/prompts/spectra-ask.prompt.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .github/prompts/spectra-debug.prompt.md
  - Package.swift
  - Sources/MacDocCLI/MacDoc+OCR.swift
  - .agents/skills/spectra-apply/SKILL.md
  - .github/prompts/spectra-audit.prompt.md
  - .github/prompts/spectra-archive.prompt.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Package.resolved
  - .agents/skills/spectra-ask/SKILL.md
  - .github/prompts/spectra-apply.prompt.md
  - README.md
  - Sources/MacDocCLI/MacDoc.swift
  - Tests/MacDocCLITests/ConvertFlagTests.swift
  - .agents/skills/spectra-propose/SKILL.md
  - .vscode/launch.json
  - packages/srt-to-html-swift/Sources/SRTToHTML/SRTConverter.swift
  - .github/prompts/spectra-discuss.prompt.md
-->

---
### Requirement: Resumable downloads for large files

The system SHALL resume interrupted downloads from the point of failure rather than restarting from the beginning. This is critical because safetensors files are typically 2-4 GB.

#### Scenario: Download interrupted and resumed

- **WHEN** a model download is interrupted (network drop, user cancellation, process termination) after partial transfer
- **THEN** calling `ensureModel` again resumes the download from the last successfully transferred byte, not from the beginning

#### Scenario: Corrupted partial download

- **WHEN** a partially downloaded file is detected as corrupted (size mismatch or integrity check failure)
- **THEN** the system deletes the corrupted partial file and restarts the download for that file from the beginning


<!-- @trace
source: mlx-hub-model-loader
updated: 2026-03-26
code:
  - AGENTS.md
  - Tests/MacDocCLITests/ConvertRouteTests.swift
  - CONVERSIONS.md
  - .spectra.yaml
  - CLAUDE.md
  - Tests/MacDocCLITests/ErrorHandlingTests.swift
  - .github/skills/spectra-apply/SKILL.md
  - .github/skills/spectra-audit/SKILL.md
  - .github/prompts/spectra-propose.prompt.md
  - .agents/skills/spectra-archive/SKILL.md
  - Tests/MacDocCLITests/FixtureManager.swift
  - .agents/skills/spectra-audit/SKILL.md
  - .github/prompts/spectra-ingest.prompt.md
  - .github/skills/spectra-debug/SKILL.md
  - .github/skills/spectra-archive/SKILL.md
  - .github/skills/spectra-propose/SKILL.md
  - .github/skills/spectra-ask/SKILL.md
  - GEMINI.md
  - .agents/skills/spectra-debug/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - .github/skills/spectra-discuss/SKILL.md
  - .github/skills/spectra-ingest/SKILL.md
  - .github/prompts/spectra-ask.prompt.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .github/prompts/spectra-debug.prompt.md
  - Package.swift
  - Sources/MacDocCLI/MacDoc+OCR.swift
  - .agents/skills/spectra-apply/SKILL.md
  - .github/prompts/spectra-audit.prompt.md
  - .github/prompts/spectra-archive.prompt.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Package.resolved
  - .agents/skills/spectra-ask/SKILL.md
  - .github/prompts/spectra-apply.prompt.md
  - README.md
  - Sources/MacDocCLI/MacDoc.swift
  - Tests/MacDocCLITests/ConvertFlagTests.swift
  - .agents/skills/spectra-propose/SKILL.md
  - .vscode/launch.json
  - packages/srt-to-html-swift/Sources/SRTToHTML/SRTConverter.swift
  - .github/prompts/spectra-discuss.prompt.md
-->

---
### Requirement: Download progress reporting

The system SHALL report download progress through the existing `progressHandler` callback with filename and completion fraction.

#### Scenario: Progress callback during download

- **WHEN** a model download is in progress
- **THEN** the `progressHandler` callback is invoked with the current filename and a progress value between 0.0 and 1.0 for each file being downloaded

#### Scenario: No progress callback when cached

- **WHEN** a model is already fully cached
- **THEN** the `progressHandler` callback is NOT invoked (no spurious progress events)


<!-- @trace
source: mlx-hub-model-loader
updated: 2026-03-26
code:
  - AGENTS.md
  - Tests/MacDocCLITests/ConvertRouteTests.swift
  - CONVERSIONS.md
  - .spectra.yaml
  - CLAUDE.md
  - Tests/MacDocCLITests/ErrorHandlingTests.swift
  - .github/skills/spectra-apply/SKILL.md
  - .github/skills/spectra-audit/SKILL.md
  - .github/prompts/spectra-propose.prompt.md
  - .agents/skills/spectra-archive/SKILL.md
  - Tests/MacDocCLITests/FixtureManager.swift
  - .agents/skills/spectra-audit/SKILL.md
  - .github/prompts/spectra-ingest.prompt.md
  - .github/skills/spectra-debug/SKILL.md
  - .github/skills/spectra-archive/SKILL.md
  - .github/skills/spectra-propose/SKILL.md
  - .github/skills/spectra-ask/SKILL.md
  - GEMINI.md
  - .agents/skills/spectra-debug/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - .github/skills/spectra-discuss/SKILL.md
  - .github/skills/spectra-ingest/SKILL.md
  - .github/prompts/spectra-ask.prompt.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .github/prompts/spectra-debug.prompt.md
  - Package.swift
  - Sources/MacDocCLI/MacDoc+OCR.swift
  - .agents/skills/spectra-apply/SKILL.md
  - .github/prompts/spectra-audit.prompt.md
  - .github/prompts/spectra-archive.prompt.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Package.resolved
  - .agents/skills/spectra-ask/SKILL.md
  - .github/prompts/spectra-apply.prompt.md
  - README.md
  - Sources/MacDocCLI/MacDoc.swift
  - Tests/MacDocCLITests/ConvertFlagTests.swift
  - .agents/skills/spectra-propose/SKILL.md
  - .vscode/launch.json
  - packages/srt-to-html-swift/Sources/SRTToHTML/SRTConverter.swift
  - .github/prompts/spectra-discuss.prompt.md
-->

---
### Requirement: Cache compatibility with HuggingFace Hub convention

The system SHALL store downloaded models at `~/.cache/huggingface/hub/` and recognize models cached by both Hub Swift and `hf` CLI (Python). When `ensureModel` is called, the system SHALL check multiple cache locations before attempting a network download.

The lookup order SHALL be:

1. `hf` CLI path: `<downloadBase>/models--<org>--<name>/snapshots/*/` (most reliable pre-download method)
2. Hub Swift path: `<downloadBase>/models/<org>/<name>/`
3. If neither contains a complete model, download via `HubApi.snapshot`

A cached model is considered "complete" when the directory contains `config.json` AND at least one `.safetensors` file.

#### Scenario: Existing hand-downloaded model is recognized

- **WHEN** a model was previously downloaded by the old `ModelLoader` to `~/.cache/huggingface/hub/models--EZCon--GLM-OCR-8bit-mlx/snapshots/main/` containing `config.json` and `model.safetensors`
- **THEN** `ensureModel` recognizes the existing files and returns the path without making any network requests

#### Scenario: Model downloaded by hf CLI is recognized

- **WHEN** a model was downloaded via `hf download EZCon/GLM-OCR-8bit-mlx` to `~/.cache/huggingface/hub/models--EZCon--GLM-OCR-8bit-mlx/snapshots/<commit>/` with symlinks to blobs
- **THEN** `ensureModel` resolves the symlinks, verifies `config.json` and at least one `.safetensors` file exist, and returns the snapshot path without making any network requests

#### Scenario: Hub Swift cached model is recognized

- **WHEN** a model was previously downloaded by Hub Swift to `~/.cache/huggingface/hub/models/EZCon/GLM-OCR-8bit-mlx/` containing `config.json` and `model.safetensors`
- **THEN** `ensureModel` returns the Hub Swift path without making any network requests

#### Scenario: No cached model found

- **WHEN** no complete model exists at any known cache location
- **THEN** `ensureModel` downloads the model via `HubApi.snapshot` and returns the downloaded path

#### Scenario: Incomplete cached model is ignored

- **WHEN** a cache directory exists but contains only `config.json` without any `.safetensors` files
- **THEN** `ensureModel` treats the cache as incomplete and proceeds to the next lookup location or downloads


<!-- @trace
source: hf-cache-compat
updated: 2026-03-28
code:
  - .agents/skills/spectra-archive/SKILL.md
  - .github/prompts/spectra-apply.prompt.md
  - .github/prompts/spectra-archive.prompt.md
  - GEMINI.md
  - .github/skills/spectra-propose/SKILL.md
  - .github/skills/spectra-archive/SKILL.md
  - Tests/MacDocCLITests/ConvertRouteTests.swift
  - Tests/MacDocCLITests/ErrorHandlingTests.swift
  - Sources/MacDocCLI/MacDoc+OCR.swift
  - .github/skills/spectra-ingest/SKILL.md
  - .github/skills/spectra-ask/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - .github/prompts/spectra-audit.prompt.md
  - Package.resolved
  - Tests/MacDocCLITests/FixtureManager.swift
  - .agents/skills/spectra-apply/SKILL.md
  - Tests/MacDocCLITests/ConvertFlagTests.swift
  - CONVERSIONS.md
  - Package.swift
  - .agents/skills/spectra-ingest/SKILL.md
  - .github/prompts/spectra-ask.prompt.md
  - .github/prompts/spectra-discuss.prompt.md
  - .vscode/launch.json
  - .github/prompts/spectra-propose.prompt.md
  - Sources/MacDocCLI/MacDoc.swift
  - .agents/skills/spectra-ask/SKILL.md
  - AGENTS.md
  - .agents/skills/spectra-debug/SKILL.md
  - README.md
  - .agents/skills/spectra-audit/SKILL.md
  - .github/skills/spectra-discuss/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - .github/skills/spectra-audit/SKILL.md
  - .github/prompts/spectra-debug.prompt.md
  - .github/skills/spectra-apply/SKILL.md
  - .spectra.yaml
  - CLAUDE.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - .github/prompts/spectra-ingest.prompt.md
  - mlx-swift-examples/
  - .github/skills/spectra-debug/SKILL.md
  - packages/srt-to-html-swift/Sources/SRTToHTML/SRTConverter.swift
-->

---
### Requirement: Public API preservation

The `ModelLoader` struct SHALL maintain its existing public API surface. Callers (`OCRPipeline`, `MacDoc+OCR.swift`) SHALL NOT require any changes.

#### Scenario: OCRPipeline uses ModelLoader without changes

- **WHEN** `OCRPipeline.loadModel(repo:progressHandler:)` calls `ModelLoader.ensureModel`
- **THEN** the call succeeds with the same signature and return type as before the refactor


<!-- @trace
source: mlx-hub-model-loader
updated: 2026-03-26
code:
  - AGENTS.md
  - Tests/MacDocCLITests/ConvertRouteTests.swift
  - CONVERSIONS.md
  - .spectra.yaml
  - CLAUDE.md
  - Tests/MacDocCLITests/ErrorHandlingTests.swift
  - .github/skills/spectra-apply/SKILL.md
  - .github/skills/spectra-audit/SKILL.md
  - .github/prompts/spectra-propose.prompt.md
  - .agents/skills/spectra-archive/SKILL.md
  - Tests/MacDocCLITests/FixtureManager.swift
  - .agents/skills/spectra-audit/SKILL.md
  - .github/prompts/spectra-ingest.prompt.md
  - .github/skills/spectra-debug/SKILL.md
  - .github/skills/spectra-archive/SKILL.md
  - .github/skills/spectra-propose/SKILL.md
  - .github/skills/spectra-ask/SKILL.md
  - GEMINI.md
  - .agents/skills/spectra-debug/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - .github/skills/spectra-discuss/SKILL.md
  - .github/skills/spectra-ingest/SKILL.md
  - .github/prompts/spectra-ask.prompt.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .github/prompts/spectra-debug.prompt.md
  - Package.swift
  - Sources/MacDocCLI/MacDoc+OCR.swift
  - .agents/skills/spectra-apply/SKILL.md
  - .github/prompts/spectra-audit.prompt.md
  - .github/prompts/spectra-archive.prompt.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Package.resolved
  - .agents/skills/spectra-ask/SKILL.md
  - .github/prompts/spectra-apply.prompt.md
  - README.md
  - Sources/MacDocCLI/MacDoc.swift
  - Tests/MacDocCLITests/ConvertFlagTests.swift
  - .agents/skills/spectra-propose/SKILL.md
  - .vscode/launch.json
  - packages/srt-to-html-swift/Sources/SRTToHTML/SRTConverter.swift
  - .github/prompts/spectra-discuss.prompt.md
-->

---
### Requirement: Support arbitrary MLX model repos

The system SHALL accept any HuggingFace repo identifier in `org/model-name` format, not just GLM-OCR. This enables future model swapping via the `--model` CLI flag.

#### Scenario: Loading a different MLX model

- **WHEN** `ensureModel(repo: "some-org/other-mlx-model")` is called
- **THEN** the system downloads and caches that model using the same Hub mechanism

#### Scenario: Invalid repo identifier

- **WHEN** `ensureModel(repo: "not-a-valid-repo")` is called and the HuggingFace API returns a 404
- **THEN** the system throws a `ModelLoaderError.downloadFailed` with a descriptive message

<!-- @trace
source: mlx-hub-model-loader
updated: 2026-03-26
code:
  - AGENTS.md
  - Tests/MacDocCLITests/ConvertRouteTests.swift
  - CONVERSIONS.md
  - .spectra.yaml
  - CLAUDE.md
  - Tests/MacDocCLITests/ErrorHandlingTests.swift
  - .github/skills/spectra-apply/SKILL.md
  - .github/skills/spectra-audit/SKILL.md
  - .github/prompts/spectra-propose.prompt.md
  - .agents/skills/spectra-archive/SKILL.md
  - Tests/MacDocCLITests/FixtureManager.swift
  - .agents/skills/spectra-audit/SKILL.md
  - .github/prompts/spectra-ingest.prompt.md
  - .github/skills/spectra-debug/SKILL.md
  - .github/skills/spectra-archive/SKILL.md
  - .github/skills/spectra-propose/SKILL.md
  - .github/skills/spectra-ask/SKILL.md
  - GEMINI.md
  - .agents/skills/spectra-debug/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - .github/skills/spectra-discuss/SKILL.md
  - .github/skills/spectra-ingest/SKILL.md
  - .github/prompts/spectra-ask.prompt.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .github/prompts/spectra-debug.prompt.md
  - Package.swift
  - Sources/MacDocCLI/MacDoc+OCR.swift
  - .agents/skills/spectra-apply/SKILL.md
  - .github/prompts/spectra-audit.prompt.md
  - .github/prompts/spectra-archive.prompt.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Package.resolved
  - .agents/skills/spectra-ask/SKILL.md
  - .github/prompts/spectra-apply.prompt.md
  - README.md
  - Sources/MacDocCLI/MacDoc.swift
  - Tests/MacDocCLITests/ConvertFlagTests.swift
  - .agents/skills/spectra-propose/SKILL.md
  - .vscode/launch.json
  - packages/srt-to-html-swift/Sources/SRTToHTML/SRTConverter.swift
  - .github/prompts/spectra-discuss.prompt.md
-->

---
### Requirement: Fallback cache lookup for hf CLI downloads

The system SHALL check the `hf` CLI cache layout (`models--<org>--<name>/snapshots/*/`) as a fallback when the primary Hub Swift cache does not contain the model. If multiple snapshots exist, the system SHALL use the most recently modified one.

#### Scenario: Multiple snapshots from hf CLI

- **WHEN** `hf` CLI cache contains multiple snapshot directories (e.g., different commits)
- **THEN** `ensureModel` uses the most recently modified snapshot that contains a complete model

#### Scenario: hf CLI snapshot with symlinks

- **WHEN** `hf` CLI snapshot contains symlinks pointing to `../../blobs/<hash>` files
- **THEN** `ensureModel` follows the symlinks when checking for file existence and returns the snapshot directory path (symlinks remain intact)

<!-- @trace
source: hf-cache-compat
updated: 2026-03-28
code:
  - .agents/skills/spectra-archive/SKILL.md
  - .github/prompts/spectra-apply.prompt.md
  - .github/prompts/spectra-archive.prompt.md
  - GEMINI.md
  - .github/skills/spectra-propose/SKILL.md
  - .github/skills/spectra-archive/SKILL.md
  - Tests/MacDocCLITests/ConvertRouteTests.swift
  - Tests/MacDocCLITests/ErrorHandlingTests.swift
  - Sources/MacDocCLI/MacDoc+OCR.swift
  - .github/skills/spectra-ingest/SKILL.md
  - .github/skills/spectra-ask/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - .github/prompts/spectra-audit.prompt.md
  - Package.resolved
  - Tests/MacDocCLITests/FixtureManager.swift
  - .agents/skills/spectra-apply/SKILL.md
  - Tests/MacDocCLITests/ConvertFlagTests.swift
  - CONVERSIONS.md
  - Package.swift
  - .agents/skills/spectra-ingest/SKILL.md
  - .github/prompts/spectra-ask.prompt.md
  - .github/prompts/spectra-discuss.prompt.md
  - .vscode/launch.json
  - .github/prompts/spectra-propose.prompt.md
  - Sources/MacDocCLI/MacDoc.swift
  - .agents/skills/spectra-ask/SKILL.md
  - AGENTS.md
  - .agents/skills/spectra-debug/SKILL.md
  - README.md
  - .agents/skills/spectra-audit/SKILL.md
  - .github/skills/spectra-discuss/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - .github/skills/spectra-audit/SKILL.md
  - .github/prompts/spectra-debug.prompt.md
  - .github/skills/spectra-apply/SKILL.md
  - .spectra.yaml
  - CLAUDE.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - .github/prompts/spectra-ingest.prompt.md
  - mlx-swift-examples/
  - .github/skills/spectra-debug/SKILL.md
  - packages/srt-to-html-swift/Sources/SRTToHTML/SRTConverter.swift
-->