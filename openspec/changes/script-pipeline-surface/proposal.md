## Why

macdoc already ships a complete docx-to-Swift script pipeline — `export_script`, `get_script_coverage`, `execute_script` (che-word-mcp) plus `macdoc word reverse` (CLI) — but it is invisible and asymmetric. Neither plugin skill mentions it, so users cannot discover it. The CLI can produce a script but cannot run one, because the execute half exists only on the MCP face. Two specs already promise more than the code delivers: `mdocx-grammar` names a `macdoc word render` command that was never implemented, and `che-word-mcp-script-pipeline-tools` states that MCP/CLI parity is "guaranteed structurally by riding the same ooxml-swift transcoder entry points" — true for export, false for execute, whose orchestration lives in che-word-mcp rather than the shared library.

## What Changes

- Promote the execute orchestration into the shared transcode module so both faces call one implementation instead of two, carrying its ordering contract (the reference docx must be read before any output is written) into normative text.
- Add a `macdoc word render` CLI subcommand that turns an `.mdocx.swift` script back into a `.docx`, accepting the bare `.mdocx` form as well, with optional byte-equal verification against a reference document. This is the first behavioral contract ever written for `render`; the existing spec only named it while illustrating extension dispatch.
- Reduce the che-word-mcp `execute_script` handler to argument parsing over the promoted API. No change to its tool schema or response shape.
- Correct the parity claim in `che-word-mcp-script-pipeline-tools` so it is accurate for all three tools rather than only export and coverage.
- Fill the `ooxml-script-transcode` Purpose, which is still the literal placeholder text left behind when `word-aligned-state-sync` was archived.
- Document the pipeline on both plugin skill surfaces: the macdoc skill gains the `word` subcommand group it currently omits entirely; the che-word-mcp skill gains the three script-pipeline tools.
- Add a `swiftify` workflow skill covering the end-to-end loop and stating the fidelity boundary in plain terms.

## Capabilities

### New Capabilities

- `swiftify-workflow`: the user-facing workflow contract for the docx-to-script-to-docx loop, including the mandatory coverage-check step and the explicit non-promise of readable output for table-bearing documents.

### Modified Capabilities

- `ooxml-script-transcode`: gains the promoted execute-orchestration API and its write-ordering requirement; Purpose placeholder replaced.
- `mdocx-grammar`: gains the first behavioral requirement for the `word render` command it already names.
- `che-word-mcp-script-pipeline-tools`: parity statement corrected to match what the code actually guarantees.

## Impact

- Affected specs: `swiftify-workflow` (new), `ooxml-script-transcode`, `mdocx-grammar`, `che-word-mcp-script-pipeline-tools`
- Affected code:
  - New:
    - `Sources/MacDocCLI/MacDoc+Word+Render.swift`
    - `Tests/MacDocCLITests/WordRenderTests.swift`
    - `plugins/macdoc/skills/swiftify/SKILL.md`
    - `packages/ooxml-swift/Sources/OOXMLSwift/Transcode/ScriptPipelineExecute.swift`
  - Modified:
    - `Sources/MacDocCLI/MacDoc+Word.swift`
    - `mcp/che-word-mcp/Sources/CheWordMCP/ScriptPipelineTools.swift`
    - `plugins/macdoc/skills/macdoc/SKILL.md`
    - `plugins/che-word-mcp/skills/che-word-mcp/SKILL.md`
    - `plugins/macdoc/.claude-plugin/plugin.json`
    - `.claude-plugin/marketplace.json`
    - `CLAUDE.md`
  - Removed: (none)
