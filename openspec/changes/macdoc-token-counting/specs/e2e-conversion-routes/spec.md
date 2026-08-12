## ADDED Requirements

### Requirement: Token-counting route coverage

The end-to-end suite SHALL invoke the compiled `macdoc` executable to verify the token-counting route's offline success, exact output bytes, output-file behavior, validation, and provider preflight without requiring a live Anthropic credential or network service.

#### Scenario: Offline GPT-4o compiled-binary route

- **WHEN** the compiled executable runs `convert --to tokens <fixture> --model gpt-4o` with networking unavailable and no tokenizer cache
- **THEN** exit code SHALL be zero, stdout SHALL equal the recorded official tiktoken count plus a newline, and the process SHALL create no cache or home-directory file

#### Scenario: Single-model output file

- **WHEN** the compiled executable runs the GPT-4o token route with `--output <temp.txt>`
- **THEN** exit code SHALL be zero, stdout SHALL be empty, and the output file SHALL contain exactly one integer plus a newline

#### Scenario: Default route requires network consent

- **WHEN** the compiled executable runs `convert --to tokens <fixture>` without `--allow-network`
- **THEN** exit code SHALL be non-zero, stdout SHALL be empty, and stderr SHALL identify the missing Anthropic network consent

#### Scenario: Claude route requires credentials

- **WHEN** the compiled executable runs the Claude token route with `--allow-network` and without `ANTHROPIC_API_KEY`
- **THEN** exit code SHALL be non-zero, stdout SHALL be empty, and stderr SHALL identify the missing credential

#### Scenario: Invalid token input fails before output

- **WHEN** the compiled executable receives an unsupported model, invalid UTF-8, or an input above 1,000,000 bytes
- **THEN** exit code SHALL be non-zero and stdout SHALL be empty

#### Scenario: Stubbed dual-provider piping output

- **WHEN** the command layer receives stubbed counts 1234 and 1198 for the default model order
- **THEN** the exact bytes available to a shell pipeline SHALL be `Model\tTokens\ngpt-4o\t1234\nclaude-sonnet-4-6\t1198\n`

### Requirement: Token-counting provider isolation

The automated suite SHALL exercise Anthropic behavior through an injected stub transport and SHALL NOT depend on a live API key, live endpoint, or network timing.

#### Scenario: Test successful Anthropic request construction

- **WHEN** a stub transport returns a valid token-count response
- **THEN** the suite SHALL verify the fixed endpoint, method, headers, model, complete source text, and parsed count without contacting Anthropic

#### Scenario: Test Anthropic failure without partial output

- **WHEN** a stub transport returns authentication, rate-limit, timeout, redirect, oversized, or malformed-response failure after local GPT-4o counting succeeds
- **THEN** the suite SHALL verify a non-zero command result, empty stdout, unchanged output destination, and diagnostics without secrets or source text
