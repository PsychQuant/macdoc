## Context

The macdoc CLI is declared with swift-argument-parser (resolved 1.8.2) across Sources/MacDocCLI: the root `MacDoc` command registers `convert`, `pdf` (17 subcommands, default `status`), `bib` (4), `config` (`ai` 3, `ocr` 6, `document` 3), the top-level `ocr` deprecation shim (#145), `docx` (4) and `word` (`reverse`, `render`). Descriptions of that surface live in four hand-maintained places (CLAUDE.md Development Commands, `.claude/rules/cli-design/`, CONVERSIONS.md, the marketplace plugin SKILL.md) and nothing checks them against the code. PsychQuant/macdoc#72's 2026-08-12 diagnosis chose a code-first design: ArgumentParser stays authoritative, a versioned `cli-spec.yaml` is generated from it, and a drift test pins the committed file to a fresh generation. The 2026-08-23 routing correction kept that strategy and classified the work as `C_shared_module_coord` (root package graph and CLI schema); its blockers #20 and #144 are closed.

Facts established against the built binary (debug build of this branch):

- `macdoc --experimental-dump-help` prints a single JSON object `{ "serializationVersion": 0, "command": { … } }` (about 184 KB). Command objects carry `commandName`, `abstract`, `discussion`, `aliases`, `shouldDisplay`, `superCommands`, `defaultSubcommand`, `subcommands`, `arguments`; argument objects carry `kind` (`positional` / `option` / `flag`), `names` (`long` / `short` / `longWithSingleDash`), `preferredName`, `valueName`, `isOptional`, `isRepeating`, `parsingStrategy`, `defaultValue`, `allValues`, `completionKind`, `shouldDisplay`, `sectionTitle`, `abstract`, `discussion`.
- ArgumentParser injects `-h/--help` and `--version` flags into every command and an auto-generated `help` subcommand under the root; the dump contains them. The dump does not contain the version string; `macdoc --version` prints it (`0.9.0`).
- The `convert` route table is a Swift `switch (ext, target)` — not introspectable. It has 17 conversions (24 extension/target pairs counting the `.htm`, `.markdown` and `.ntb` aliases) plus the `--to tokens` measurement route that accepts any extension. Unsupported pairs fail with `不支援從 .<ext> 轉換到 <target>` before any conversion work.
- CONVERSIONS.md's Converter Details table lacks three shipped routes (Word → Marker, HTML → PDF, LaTeX → Word) and lists PDF → LaTeX, which is served by the `macdoc pdf` pipeline rather than `convert`.
- `convert --to html file.srt` and `convert --to html file.note` without `--css` fail, because `--css` defaults to `web` and those routes accept only `dark` / `light`. This change records the behavior; it does not change it.

## Goals / Non-Goals

**Goals:**

- A committed, machine-readable `cli-spec.yaml` that lists every user-facing command path with its positional arguments, options and flags (names, required/optional, repeating, defaults, allowed values, help text), generated from the code.
- An explicit, validated overlay for facts ArgumentParser cannot express: command status and replacement, conversion routes (input extensions, target, converter package, output mode, route-specific options and CSS styles), overlapping paths, external dependencies.
- Byte-for-byte deterministic output, and a test that fails when the committed file is stale, with a one-command regeneration.
- End-to-end evidence that the spec is useful: the overlay's routes are checked against the binary's dispatch, and CONVERSIONS.md is checked against the spec.

**Non-Goals:**

- No spec-first generation of Swift routing or ArgumentParser declarations; YAML never feeds back into code.
- No replacement of ArgumentParser, no new `macdoc` subcommand, no change to any existing command's behavior or help text (the `srt` / `note` `--css` default defect is reported as a follow-up, not fixed here).
- No generation of CONVERSIONS.md, CLAUDE.md or the plugin SKILL.md from the spec in this change; only a consistency check against CONVERSIONS.md.
- No YAML parsing anywhere in macdoc; the only YAML the project reads back is its own output, compared as bytes.
- No new third-party package dependency.

## Decisions

### Code-first authority with a generated cli-spec.yaml

ArgumentParser declarations are the single source of truth for command paths, arguments, options, flags, required/optional, defaults, allowed values and help text. `cli-spec.yaml` is an output, committed at the repository root and marked as generated in its header. Alternative considered: spec-first (YAML authoritative, Swift stubs generated) — rejected by the #72 diagnosis because it duplicates ArgumentParser and moves the drift from Markdown into YAML instead of removing it.

### Out-of-process dump-help consumed through a private versioned decoder

The generator runs the built `macdoc --experimental-dump-help` and decodes the JSON with its own minimal `Decodable` types that read only the fields listed in Context. It accepts `serializationVersion` 0 and fails with a named error for any other value; unknown JSON fields are ignored; unknown `kind`, name-kind or `parsingStrategy` values fail decoding. Alternatives considered: linking the `ArgumentParserToolInfo` product (ties the project's schema to experimental types and adds a product dependency to the test graph); calling ArgumentParser's internal dump from inside the process (requires linking the executable target and experimental SPI). Running the real binary also proves the shipped executable, not a test-only reconstruction, produced the surface.

### Project-owned schema with a derived/overlay provenance split

The YAML schema is owned by macdoc and versioned by its own `schema_version: 1`, independent of the dump's serialization version. Derived fields sit directly on command and argument entries; overlay facts appear only under a command's `project:` key and in the top-level `conversions`, `overlaps` and `external_dependencies` sections, so a reader can always tell which facts the compiler vouches for. Parsing strategies are re-spelled into project names (`upToNextOption` → `up_to_next_option`), so an upstream rename changes the decoder, not the schema.

### Metadata overlay as a compiler-checked Swift literal

The overlay is a Swift value (`MacDocCLIMetadata.overlay`, type `CLISpecMetadata`) in the `CLISpec` target. Overlay prose never restates a value ArgumentParser already reports (defaults, allowed values); a contract test rejects notes that quote a default. Status, output mode and dependency kind are Swift enums, so a typo is a compile error; comments are allowed next to each fact. The builder cross-checks every reference against the derived surface (closed list of failure classes in the spec). Alternatives considered: a YAML overlay file (needs a YAML parser — a third-party dependency, contrary to `.claude/rules/native-macos-compat.md`); a JSON overlay (native `JSONDecoder`, but it silently ignores misspelled keys and forbids comments, and the overlay would be a second hand-edited data file beside the generated one).

### Deterministic YAML subset emitter over an ordered node tree

The document is first converted to an ordered node tree (mapping entries are arrays, never dictionaries), then printed by a small emitter: two-space indentation, block sequences for lists of mappings and for `notes`, flow sequences for lists of scalars, a conservative plain-scalar rule with double-quoted strings otherwise, `true` / `false`, decimal integers, LF line endings, no trailing whitespace, exactly one trailing newline, non-ASCII text written as UTF-8. Alternatives considered: Yams (third-party, and its formatting choices change across versions, which would break byte equality on a dependency bump); emitting JSON (the issue asks for YAML, and JSON's escaping of CJK help text hurts readability).

### Builtin surface normalization and declaration-order traversal

Flags whose long name is `help` or `version`, and the root's auto-generated `help` subcommand, are dropped from every command; the version string goes to `tool.version`, read from `macdoc --version`. Commands are listed in depth-first pre-order following each parent's `subcommands` declaration order (the order `--help` shows); arguments keep declaration order within their kind; names are ordered long, then single-dash long, then short. Alternative considered: alphabetical ordering — rejected because declaration order is equally deterministic and mirrors what users see in `--help`.

### One transform shared by the drift test and make cli-spec

All transform code lives in the `CLISpec` library target (no dependencies beyond Foundation); `CLISpecGenerator.generate(dumpHelpJSON:versionOutput:metadata:)` is the only entry point. A test-side harness runs the binary and calls it. The drift test compares the result with the committed bytes; `make cli-spec` — the only documented way to record — builds and runs the same test with `MACDOC_RECORD_CLI_SPEC=1` for that one invocation, which rewrites the file. Record mode is refused when `CI` is present, so an inherited variable cannot turn the CI drift check into a rewrite. The `macdoc` executable does not link `CLISpec`, so the shipped binary is unchanged. Alternatives considered: a `macdoc spec` subcommand (changes the CLI surface this change must keep additive, and the command would describe itself); a separate executable target (a second product whose only job is to spawn `macdoc` and call the same library); keeping the transform inside the test target (couples it to the test framework and blocks reuse by a later SKILL.md generator).

### Route probe against the binary's convert dispatch

Because the route table is not introspectable, a test checks the overlay's `macdoc convert` conversions against observable behavior: for every source extension and target that appear in those conversions or in a fixed probe vocabulary (all extensions and targets known when the vocabulary was last updated, plus candidate formats such as `txt`, `rtf`, `epub`), it runs `macdoc convert` inside a temporary directory with `PATH=/usr/bin:/bin` (so playwright is never launched). A listed pair runs on a real fixture of its format (with the route's first `--css` style when it has styles) and must succeed with a non-empty output; the only exception is the closed in-route diagnostics table (`HTML → PDF` → `需要 playwright CLI`). Absence of `不支援從` alone is not accepted as evidence, because a route blocked by an earlier validation would also lack it — verified by mutation: removing the `(srt, html)` case, and making the `(tex, docx)` case throw before its converter, both fail the probe, while the earlier absence-only probe passed the second. An unlisted pair runs on an empty file and must produce exactly `不支援從 .<ext> 轉換到 <target>`. The docx and pdf fixtures are generated into the probe's own directory because the shared FixtureManager copies are rewritten non-atomically by parallel suites. The `tokens` route (any extension) is excluded; it is covered by `TokenCountCommandTests`.

### CONVERSIONS.md consistency by label equality

Each overlay conversion carries a `label` equal to the first cell of its row in CONVERSIONS.md's "Converter Details" table. The consistency test requires the two label sets to be equal. CONVERSIONS.md gains Converter Details rows for Word → Marker, HTML → PDF and LaTeX → Word; the cross matrix gains the HTML → PDF cell and a LaTeX source row (Marker has no matrix column because it is a directory format, so it appears only in the table); PDF → LaTeX maps to the `macdoc pdf` conversion. Alternative considered: generating the whole CONVERSIONS.md from the spec — deferred (Non-Goals); the check is the smallest end-to-end proof the diagnosis asked for.

## Implementation Contract

**Behavior.** After `swift build`, `make cli-spec` rewrites `cli-spec.yaml`; `swift test --filter CLISpec` passes when the committed file equals a fresh generation and fails otherwise, naming the first differing line and the regeneration command. `macdoc` itself behaves exactly as before.

**Interface.**

- `CLISpecGenerator.generate(dumpHelpJSON: Data, versionOutput: String, metadata: CLISpecMetadata) throws -> String` returns the complete file content.
- `CLISpecBuilder` produces a `CLISpecDocument` value; `CLISpecDocument.yamlNode` produces the ordered node tree; `YAMLEmitter.emit(_:headerComments:)` prints it. Tests use these directly with synthetic dumps.
- `MacDocCLIMetadata.overlay: CLISpecMetadata` is the only overlay instance.
- `CLISpecError` covers: unsupported dump serialization version, malformed dump, empty version output, a missing or empty required field (`missingRequiredField(command:element:field:)`), and the eight overlay failure classes named in the spec.

**Data shape (schema_version 1).** Top-level keys in order: `schema_version`, `tool` (`name`, `version`, `abstract`), `source` (`authority`, `dump_help_serialization_version`, `overlay`, `regenerate`), `commands`, `conversions`, `overlaps`, `external_dependencies`. Per-entry key orders, emission rules and value spellings are normative in the `cli-spec` spec.

**Failure modes.** Every generation failure is a thrown `CLISpecError` whose description names the offending path, option, style, label or dependency id; nothing is skipped silently. A binary that cannot be found fails the harness with the existing `BinarySelectionError` message.

**Acceptance criteria.** `CLISpecEmitterTests`, `CLISpecBuilderTests`, `CLISpecContractTests`, `CLISpecDriftTests`, `CLISpecRouteProbeTests` and `CLISpecConversionsDocTests` pass; the full `swift test` run keeps the baseline (111 XCTest with 4 skipped, 43 Swift Testing) with zero failures plus the new tests; `spectra validate cli-spec-yaml` passes.

**In scope:** the `CLISpec` target, the overlay, `cli-spec.yaml`, the six test suites, the `cli-spec` Makefile target, CONVERSIONS.md rows, CLAUDE.md pointers. **Out of scope:** changing any command's behavior or help text, generating other documents, CI workflow wiring, plugin SKILL.md changes, macdoc version bumps.

## Risks / Trade-offs

- [ArgumentParser changes the experimental dump format] → The decoder checks `serializationVersion` and fails with a named error; field renames surface as decode failures in `CLISpecBuilderTests` / `CLISpecDriftTests` rather than as a silently thinner spec.
- [Help-text or default edits make the drift test fail] → Intended: that is the signal the spec must be regenerated. The failure message states the command (`make cli-spec`).
- [The overlay drifts from the untyped route switch] → The route probe fails in both directions: an overlay route the binary rejects, and a binary route missing from the overlay (verified by mutation: dropping `LaTeX → Word` from the overlay and adding a fake `txt → html` both fail the probe). Residual gap: a new `switch` case for an extension outside the probe vocabulary is caught only by the CONVERSIONS.md check, and only if that file is updated.
- [A future user-declared `help` subcommand or `--version` flag would be dropped by builtin normalization] → Recorded in the spec; macdoc declares neither today, and such a declaration would collide with ArgumentParser's own builtins anyway.
- [The root package graph gains a target (shared resource per the #72 routing correction)] → The target is additive, has no dependencies, is linked only by the test target, and leaves Package.resolved untouched.
- [Record mode could mask drift if set in CI] → Record mode requires the exact value `1`, is refused whenever `CI` is present (the test fails with a message naming `make cli-spec`), and `make cli-spec` is the only documented way to set it, for one invocation.
- [A dump field renamed or dropped upstream yields a nameless argument] → Required fields are validated per argument kind and fail as `missingRequiredField`, naming the command, the element and the field.
- [A header comment containing a line break or control character could break out of the comment] → The emitter splits comments into physical lines, each with its own `# `, and writes disallowed characters as visible `\uXXXX`.

## Migration Plan

Additive. Rollback is reverting the change's commits; no data format or CLI behavior depends on the new target.
