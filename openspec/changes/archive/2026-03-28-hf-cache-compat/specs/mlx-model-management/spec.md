## MODIFIED Requirements

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

## ADDED Requirements

### Requirement: Fallback cache lookup for hf CLI downloads

The system SHALL check the `hf` CLI cache layout (`models--<org>--<name>/snapshots/*/`) as a fallback when the primary Hub Swift cache does not contain the model. If multiple snapshots exist, the system SHALL use the most recently modified one.

#### Scenario: Multiple snapshots from hf CLI

- **WHEN** `hf` CLI cache contains multiple snapshot directories (e.g., different commits)
- **THEN** `ensureModel` uses the most recently modified snapshot that contains a complete model

#### Scenario: hf CLI snapshot with symlinks

- **WHEN** `hf` CLI snapshot contains symlinks pointing to `../../blobs/<hash>` files
- **THEN** `ensureModel` follows the symlinks when checking for file existence and returns the snapshot directory path (symlinks remain intact)
