## Why

The word-imitation line (format-alignment-engine #130, word-canonical-forms #131, render-effect-semantics) shipped a complete script pipeline — docx to executable rebuild script (`.mdocx.swift`), dual-track coverage, strict content slots, Stage-B byte-equal guarantees — but only through the macdoc CLI. che-word-mcp, the MCP surface that lets Claude Desktop / Claude Code users work with Word documents, cannot reach any of it: its ooxml-swift dependency is pinned below 1.0.0 (semver cap on a 0.24 pin), and its 16,100-line tool server exposes none of the pipeline verbs. MCP users cannot drive the submission-document workflow without leaving Claude for a terminal.

Diagnosed in PsychQuant/macdoc#134 (trial resolution proved the dependency-chain blocker verbatim); acceptance level and migration scope were settled by the user in the issue's Clarity Surface, and five direction decisions were locked in the 2026-07-16 spectra-discuss convergence (recorded as a decision comment on #134).

## What Changes

1. **Dependency chain unblocks** — latex-math-swift and word-to-md-swift each bump their ooxml-swift requirement to 1.4 and release a 0.x minor. word-to-md-swift's source is already proven 1.4-compatible (macdoc's graph builds it against ooxml main via the word-builder-swift branch override); latex-math-swift needs a real build measurement after the bump.
2. **che-word-mcp cross-major migration** — bump ooxml-swift to 1.4.0 (plus the two intermediary releases), fix hard breaking changes only (RunProperties.rawChildren removal, tree-only IO path); all existing tools' tests stay green. Deprecation warnings from direct typed mutation are tolerated.
3. **Three new MCP tools (frozen contract, snake_case verb-first per the existing 242-definition convention)**:
   - export_script — docx to full-fidelity rebuild script; optional slot designations as an array of {name, para_id} objects; strict-mode designation failures surface as MCP errors
   - get_script_coverage — per-part DSL/raw split plus aggregate percentage, same numbers as the CLI coverage report
   - execute_script — rebuild docx from a script; optional byte-equal verification against a reference docx
4. **Parity by construction** — the tool handlers are thin wrappers over the same ooxml-swift transcoder entry points the CLI uses (ReverseExtractor / ScriptExporter / ScriptImporter). Behavior parity is guarded by an in-process Stage-B byte-equal test (CI-runnable) plus an env-gated MCP-versus-CLI byte comparison (needs the macdoc binary and MACDOC_TEMPLATE_DIR).
5. **Release chain** — che-word-mcp ships a signed + notarized release; macdoc marketplace bumps binary_version and version per the #116 decoupling contract.

## Non-Goals

- Migrating the existing ~145 tools from direct typed mutation to op-based implementations (deprecation direction noted in ooxml-swift v1.0.0; separate line of work).
- Renaming or reshaping any existing tool (frozen contracts stay frozen).
- Any CLI-side change — macdoc word reverse behavior is the reference, not a target.
- pptx or other formats (the imitation ladder for pptx does not exist yet).
- Elevating the intermediary packages to 1.0 (a dependency's major bump is not an API break of their own surface; both release 0.x minors).

## Capabilities

### New Capabilities

- `che-word-mcp-script-pipeline-tools`: the three script-pipeline MCP tools (export_script / get_script_coverage / execute_script) with shared-code-path parity guarantees against the macdoc CLI.

### Modified Capabilities

(none)

## Impact

- Affected specs: `che-word-mcp-script-pipeline-tools` (new). Read-only reference: `ooxml-script-transcode`, `template-content-slots` (their contracts are consumed, not modified).
- Affected code:
  - New: mcp/che-word-mcp/Sources/CheWordMCP/ScriptPipelineTools.swift, mcp/che-word-mcp/Tests/CheWordMCPTests/ScriptPipelineParityTests.swift
  - Modified: packages/latex-math-swift/Package.swift, packages/word-to-md-swift/Package.swift, mcp/che-word-mcp/Package.swift, mcp/che-word-mcp/Sources/CheWordMCP/Server.swift, plugins/che-word-mcp/.claude-plugin/plugin.json, .claude-plugin/marketplace.json
  - Removed: (none)
