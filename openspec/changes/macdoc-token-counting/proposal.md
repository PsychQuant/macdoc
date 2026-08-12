## Why

macdoc has a unified `convert --to` entry point, but it still cannot measure a text file for the OpenAI and Anthropic model families described in issue #20. The implementation must keep the OpenAI path genuinely offline, make Anthropic disclosure explicit, and expose deterministic output suitable for shell pipelines instead of hiding provider failures behind approximate counts.

## What Changes

- Add `macdoc convert --to tokens <file>` with an optional `--model` selector and an explicit `--allow-network` consent gate for Anthropic requests.
- Add a reusable local `token-counter-swift` package that provides an offline OpenAI `o200k_base` counter and an injectable Anthropic Message Token Count API client.
- Bundle the audited OpenAI `o200k_base` vocabulary as a package resource so the OpenAI path never downloads data at runtime.
- Define deterministic single-model numeric output, deterministic dual-model tabular output, size and UTF-8 validation, authentication errors, provider error mapping, and no-partial-output behavior.
- Add CLI, library, and end-to-end tests, including a stub HTTP transport and reference vectors cross-checked against OpenAI tiktoken.
- Document privacy, network, model, environment-variable, and platform boundaries.

## Capabilities

### New Capabilities

- `token-counting-cli`: Text-file token measurement, provider selection, deterministic rendering, offline OpenAI counting, explicit Anthropic network consent, and typed error behavior.

### Modified Capabilities

- `e2e-conversion-routes`: Extend the compiled-binary route matrix with token-counting success, consent, authentication, and piping scenarios.

## Impact

- Affected specs: `token-counting-cli`, `e2e-conversion-routes`
- Affected code:
  - New:
    - `packages/token-counter-swift/Package.swift`
    - `packages/token-counter-swift/Sources/TokenCounter/`
    - `packages/token-counter-swift/Sources/TokenCounter/Resources/o200k_base.tiktoken`
    - `packages/token-counter-swift/Tests/TokenCounterTests/`
    - `Tests/MacDocCLITests/TokenCountCommandTests.swift`
  - Modified:
    - `.gitignore`
    - `Package.swift`
    - `Package.resolved`
    - `Sources/MacDocCLI/MacDoc+Convert.swift`
    - `README.md`
    - `CONVERSIONS.md`
  - Removed: none
