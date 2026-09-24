## Why

macdoc's command surface (`convert` with 17 conversions — 24 extension/target pairs counting the `.htm`, `.markdown` and `.ntb` aliases — plus the `tokens` measurement route, the `pdf` pipeline, `bib`, `config ai|ocr|document`, `docx`, `word reverse|render`, and the removed top-level `ocr` shim) is described only by the ArgumentParser declarations in Sources/MacDocCLI and by hand-maintained prose spread over CLAUDE.md, `.claude/rules/cli-design/`, CONVERSIONS.md and the plugin SKILL.md. There is no machine-readable manifest, so every one of those documents drifts silently (#85: the skill doc lagged the HTML→PDF route for more than a release), agents have to grep several files to learn how to call macdoc, and the overlap between `convert --to md file.pdf`, `pdf ocr` and the removed `ocr` is recorded nowhere discoverable. PsychQuant/macdoc#72 (diagnosis 2026-08-12, routing correction 2026-08-23) fixed the approach: code-first — the ArgumentParser declarations stay authoritative, a versioned `cli-spec.yaml` is generated from them, and a test fails whenever the committed file differs from a fresh generation. Its blockers (#20, #144) are closed.

## What Changes

- New library target `CLISpec` (Sources/CLISpec) with no third-party dependencies: a decoder for swift-argument-parser's `--experimental-dump-help` JSON (serializationVersion 0 only), a builder that maps it into a project-owned schema and merges a project metadata overlay, and a small deterministic YAML emitter.
- New project metadata overlay as a Swift literal (Sources/CLISpec/MacDocCLIMetadata.swift) holding what ArgumentParser cannot express: command status (active / deprecated / removed) and replacements, conversion routes with input/output formats and output mode, overlapping-path notes (`convert --to md` vs `pdf ocr` vs the removed `ocr`; `convert … .bib` vs `bib to-*`), and external dependencies (playwright, TeX, AI CLIs, Ollama, Hugging Face, Anthropic API, Microsoft Word). The builder rejects overlay entries that reference commands, options, styles or dependencies absent from the derived surface.
- New generated file `cli-spec.yaml` at the repository root (schema_version 1), committed.
- New tests in Tests/MacDocCLITests: emitter and builder unit tests over synthetic dumps; contract tests against the built binary (root, `convert`, `pdf ocr`, `word reverse` / `word render`, `config document`, the `ocr` shim); a drift test that asserts byte equality and rewrites the file when `MACDOC_RECORD_CLI_SPEC=1`; a route probe that checks the overlay's `convert` routes against the binary's actual accept/reject behavior; and a CONVERSIONS.md consistency check.
- New Makefile target `cli-spec` that regenerates the file; CLAUDE.md points at the file and the command.
- CONVERSIONS.md gains the three `convert` routes it was missing (Word → Marker, HTML → PDF, LaTeX → Word) so the consistency check holds.
- No existing CLI behavior changes: the `macdoc` executable does not link the new target.

## Non-Goals (optional)

Recorded in design.md (Goals / Non-Goals): no spec-first generation of Swift routing, no replacement of ArgumentParser, no generation of CONVERSIONS.md or SKILL.md from the spec in this change.

## Capabilities

### New Capabilities

- `cli-spec`: generated, versioned, machine-readable specification of the macdoc CLI — schema, derivation rules from ArgumentParser, metadata overlay contract, deterministic serialization, and the drift / route / documentation consistency contracts.

### Modified Capabilities

(none)

## Impact

- Affected specs: `cli-spec` (new)
- Affected code:
  - New: Sources/CLISpec/DumpHelp.swift, Sources/CLISpec/CLISpecModel.swift, Sources/CLISpec/CLISpecBuilder.swift, Sources/CLISpec/YAMLEmitter.swift, Sources/CLISpec/CLISpecGenerator.swift, Sources/CLISpec/MacDocCLIMetadata.swift, Tests/MacDocCLITests/CLISpecHarness.swift, Tests/MacDocCLITests/CLISpecEmitterTests.swift, Tests/MacDocCLITests/CLISpecBuilderTests.swift, Tests/MacDocCLITests/CLISpecContractTests.swift, Tests/MacDocCLITests/CLISpecDriftTests.swift, Tests/MacDocCLITests/CLISpecRouteProbeTests.swift, Tests/MacDocCLITests/CLISpecConversionsDocTests.swift, cli-spec.yaml
  - Modified: Package.swift, Makefile, CLAUDE.md, CONVERSIONS.md
  - Removed: (none)
