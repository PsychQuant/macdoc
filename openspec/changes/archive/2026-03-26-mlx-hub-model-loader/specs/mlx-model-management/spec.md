## ADDED Requirements

### Requirement: Automatic model download on first use

The system SHALL automatically download the requested MLX model from HuggingFace Hub when `ensureModel(repo:)` is called and the model is not present in local cache. The download SHALL use the Hub module from `mlx-swift-examples` for resumable transfers.

#### Scenario: First-time model download

- **WHEN** `ensureModel(repo: "EZCon/GLM-OCR-8bit-mlx")` is called and no cached model exists at `~/.cache/huggingface/hub/models--EZCon--GLM-OCR-8bit-mlx/`
- **THEN** the system downloads all required files (config.json, safetensors, tokenizer files) from HuggingFace Hub to the local cache directory and returns the path to the cached model directory

#### Scenario: Model already cached

- **WHEN** `ensureModel(repo: "EZCon/GLM-OCR-8bit-mlx")` is called and the model files already exist in local cache
- **THEN** the system returns the cached model directory path without making any network requests

### Requirement: Resumable downloads for large files

The system SHALL resume interrupted downloads from the point of failure rather than restarting from the beginning. This is critical because safetensors files are typically 2-4 GB.

#### Scenario: Download interrupted and resumed

- **WHEN** a model download is interrupted (network drop, user cancellation, process termination) after partial transfer
- **THEN** calling `ensureModel` again resumes the download from the last successfully transferred byte, not from the beginning

#### Scenario: Corrupted partial download

- **WHEN** a partially downloaded file is detected as corrupted (size mismatch or integrity check failure)
- **THEN** the system deletes the corrupted partial file and restarts the download for that file from the beginning

### Requirement: Download progress reporting

The system SHALL report download progress through the existing `progressHandler` callback with filename and completion fraction.

#### Scenario: Progress callback during download

- **WHEN** a model download is in progress
- **THEN** the `progressHandler` callback is invoked with the current filename and a progress value between 0.0 and 1.0 for each file being downloaded

#### Scenario: No progress callback when cached

- **WHEN** a model is already fully cached
- **THEN** the `progressHandler` callback is NOT invoked (no spurious progress events)

### Requirement: Cache compatibility with HuggingFace Hub convention

The system SHALL store downloaded models at `~/.cache/huggingface/hub/models--<org>--<name>/` following the standard HuggingFace Hub cache layout. Existing models downloaded by the previous hand-written downloader or by `hf` CLI SHALL remain usable without re-download.

#### Scenario: Existing hand-downloaded model is recognized

- **WHEN** a model was previously downloaded by the old `ModelLoader` to `~/.cache/huggingface/hub/models--EZCon--GLM-OCR-8bit-mlx/snapshots/main/`
- **THEN** `ensureModel` recognizes the existing files and does not re-download them

#### Scenario: Model downloaded by hf CLI is recognized

- **WHEN** a model was downloaded via `hf download EZCon/GLM-OCR-8bit-mlx`
- **THEN** `ensureModel` recognizes the existing files and does not re-download them

### Requirement: Public API preservation

The `ModelLoader` struct SHALL maintain its existing public API surface. Callers (`OCRPipeline`, `MacDoc+OCR.swift`) SHALL NOT require any changes.

#### Scenario: OCRPipeline uses ModelLoader without changes

- **WHEN** `OCRPipeline.loadModel(repo:progressHandler:)` calls `ModelLoader.ensureModel`
- **THEN** the call succeeds with the same signature and return type as before the refactor

### Requirement: Support arbitrary MLX model repos

The system SHALL accept any HuggingFace repo identifier in `org/model-name` format, not just GLM-OCR. This enables future model swapping via the `--model` CLI flag.

#### Scenario: Loading a different MLX model

- **WHEN** `ensureModel(repo: "some-org/other-mlx-model")` is called
- **THEN** the system downloads and caches that model using the same Hub mechanism

#### Scenario: Invalid repo identifier

- **WHEN** `ensureModel(repo: "not-a-valid-repo")` is called and the HuggingFace API returns a 404
- **THEN** the system throws a `ModelLoaderError.downloadFailed` with a descriptive message
