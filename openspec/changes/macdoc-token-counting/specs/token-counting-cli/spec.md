## ADDED Requirements

### Requirement: Token counting command and supported models

The CLI SHALL accept `macdoc convert --to tokens <file>` for UTF-8 text files. The optional `--model` value SHALL accept exactly `gpt-4o` or `claude-sonnet-4-6`. Without `--model`, the CLI SHALL request `gpt-4o` followed by `claude-sonnet-4-6`.

#### Scenario: Count one OpenAI model

- **WHEN** a user runs `macdoc convert --to tokens sample.md --model gpt-4o`
- **THEN** the CLI SHALL count the complete UTF-8 contents using the `gpt-4o` model mapping

#### Scenario: Count both default models

- **WHEN** a user runs `macdoc convert --to tokens sample.md --allow-network` without `--model`
- **THEN** the CLI SHALL count `gpt-4o` first and `claude-sonnet-4-6` second

#### Scenario: Reject an unsupported model

- **WHEN** a user supplies a model other than `gpt-4o` or `claude-sonnet-4-6`
- **THEN** the CLI SHALL fail before counting and list the two supported values

### Requirement: Offline GPT-4o counting

The GPT-4o provider SHALL use the bundled `o200k_base` vocabulary, SHALL verify SHA-256 `446a9538cb6c348e3516120d7c08b09f57c36495e2acfffe59a5bf8b0cfb1a2d` before parsing it, and SHALL NOT perform network requests, runtime downloads, cache writes, or home-directory writes.

#### Scenario: Count with networking unavailable

- **WHEN** the compiled CLI counts a valid file for `gpt-4o` while networking is unavailable
- **THEN** the count SHALL succeed using only the bundled resource

#### Scenario: Reject a corrupted vocabulary

- **WHEN** the local provider loads vocabulary bytes whose SHA-256 differs from the fixed digest
- **THEN** it SHALL fail with a resource-integrity error before parsing or counting

#### Scenario: Match official reference vectors

- **WHEN** the provider counts repository vectors covering empty, ASCII, Traditional Chinese, mixed-script, and emoji text
- **THEN** every result SHALL equal the recorded result produced by the official Python `tiktoken` `o200k_base` encoding

### Requirement: Explicit Anthropic network consent and credentials

Any count containing `claude-sonnet-4-6` SHALL require `--allow-network` and a non-empty `ANTHROPIC_API_KEY`. The CLI SHALL validate both conditions before constructing or invoking the Anthropic transport.

#### Scenario: Reject missing network consent

- **WHEN** a user requests `claude-sonnet-4-6` without `--allow-network`
- **THEN** the CLI SHALL fail locally with an instruction to add explicit network consent and SHALL make zero HTTP requests

#### Scenario: Reject missing credentials

- **WHEN** a user requests `claude-sonnet-4-6` with `--allow-network` but `ANTHROPIC_API_KEY` is absent or empty
- **THEN** the CLI SHALL fail locally with an authentication-configuration error and SHALL make zero HTTP requests

#### Scenario: Use explicit consent and credentials

- **WHEN** a user requests `claude-sonnet-4-6` with `--allow-network` and a non-empty `ANTHROPIC_API_KEY`
- **THEN** the CLI SHALL supply the key only as the `x-api-key` request header and SHALL submit the complete admitted file text

### Requirement: Anthropic request and response contract

The Anthropic provider SHALL send `POST https://api.anthropic.com/v1/messages/count_tokens` with `anthropic-version: 2023-06-01`, the selected model, and one user text message. It SHALL reject redirects, SHALL use a 30-second timeout, SHALL stop reading response bytes after 64 KiB, SHALL NOT retry automatically, and SHALL accept only a 2xx JSON response containing a non-negative integer `input_tokens`.

#### Scenario: Parse a successful response

- **WHEN** the fixed endpoint returns status 200 and `{ "input_tokens": 1198 }`
- **THEN** the provider SHALL return 1198 for `claude-sonnet-4-6`

#### Scenario: Map provider failures

- **WHEN** the endpoint returns 401 or 403, 429, another non-2xx status, a redirect, a timeout, more than 64 KiB, invalid JSON, or an invalid `input_tokens` value
- **THEN** the provider SHALL return the corresponding authentication, rate-limit, provider, redirect, timeout, response-size, or invalid-response error

#### Scenario: Protect request data in errors

- **WHEN** any Anthropic request fails
- **THEN** the resulting error and logs SHALL NOT contain the API key, source text, request headers, request body, or full provider response body

### Requirement: Input admission and boundaries

The token route SHALL accept regular files of at most 1,000,000 bytes that decode strictly as UTF-8. It SHALL reject directories, larger files, and invalid UTF-8 before invoking any provider. It SHALL count the entire admitted file and SHALL NOT truncate input.

#### Scenario: Accept the size boundary

- **WHEN** an input is exactly 1,000,000 bytes and decodes as UTF-8
- **THEN** the CLI SHALL admit the complete input for counting

#### Scenario: Reject input above the size boundary

- **WHEN** an input is 1,000,001 bytes
- **THEN** the CLI SHALL fail before local counting or network activity

#### Scenario: Reject invalid UTF-8

- **WHEN** an input contains an invalid UTF-8 byte sequence
- **THEN** the CLI SHALL fail before local counting or network activity

#### Scenario: Count an empty file

- **WHEN** an input is an empty UTF-8 file
- **THEN** GPT-4o SHALL return zero and Anthropic SHALL return its non-negative provider count when requested

### Requirement: Deterministic output and atomic presentation

A successful single-model command SHALL emit one base-10 integer followed by a newline. A successful default dual-model command SHALL emit the tab-separated header `Model\tTokens`, then `gpt-4o`, then `claude-sonnet-4-6`, with one row per line and a trailing newline. Counts SHALL use ASCII digits without locale grouping. The command SHALL buffer all requested counts before writing stdout or an output file.

#### Scenario: Render a single-model result

- **WHEN** `gpt-4o` returns 1234
- **THEN** the exact output bytes SHALL be `1234\n`

#### Scenario: Render a dual-model result

- **WHEN** `gpt-4o` returns 1234 and `claude-sonnet-4-6` returns 1198
- **THEN** the exact output bytes SHALL be `Model\tTokens\ngpt-4o\t1234\nclaude-sonnet-4-6\t1198\n`

#### Scenario: Prevent partial stdout

- **WHEN** GPT-4o succeeds and Anthropic fails during a dual-model command
- **THEN** the command SHALL fail with empty stdout

#### Scenario: Prevent partial file output

- **WHEN** a requested provider fails and `--output result.txt` was supplied
- **THEN** the command SHALL leave an absent destination absent and SHALL leave an existing destination unchanged

### Requirement: Token-route option validation

The CLI SHALL accept `--model` and `--allow-network` only with `--to tokens`. The token route SHALL reject format-specific flags `--css`, `--hard-breaks`, `--full`, `--frontmatter`, and `--html-extensions` when their values differ from defaults. It SHALL ignore the input filename extension and SHALL operate only on admitted UTF-8 bytes.

#### Scenario: Reject token options on a conversion route

- **WHEN** a user supplies `--model gpt-4o` or `--allow-network` with a target other than `tokens`
- **THEN** the CLI SHALL fail with an option-scope error before conversion

#### Scenario: Reject conversion flags on the token route

- **WHEN** a user supplies a non-default format-specific flag with `--to tokens`
- **THEN** the CLI SHALL fail with an option-scope error before counting

#### Scenario: Count a text file with an arbitrary extension

- **WHEN** a regular UTF-8 file named `sample.data` is counted
- **THEN** the CLI SHALL count its complete text without using `.data` as a format signal

### Requirement: Reusable service behavior

The `TokenCounter` package SHALL expose typed model and count values, an injectable Anthropic transport, and an asynchronous service that returns one result per requested model in request order. The service SHALL throw without returning a partial array if any model fails.

#### Scenario: Preserve requested order

- **WHEN** a caller requests `[claude-sonnet-4-6, gpt-4o]` and both providers succeed
- **THEN** the service SHALL return Claude first and GPT-4o second

#### Scenario: Fail a multi-provider request atomically

- **WHEN** any requested provider fails
- **THEN** the service SHALL throw and SHALL NOT return the successful providers' partial results

### Requirement: User-facing privacy and platform documentation

User documentation SHALL identify supported models, exact output shapes, the UTF-8 byte limit, the bundled GPT-4o resource, `ANTHROPIC_API_KEY`, the per-invocation `--allow-network` gate, full-file disclosure to Anthropic, and Anthropic's provider-estimate semantics. Platform claims SHALL follow the repository platform-state taxonomy and SHALL include evidence for every `verified` state.

#### Scenario: Read the token-counting documentation

- **WHEN** a user consults the command and conversion documentation
- **THEN** the user SHALL see which path is offline, which path sends the complete file to Anthropic, which credentials and consent are required, and which platforms have evidence
