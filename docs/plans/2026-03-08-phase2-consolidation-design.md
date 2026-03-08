# Phase 2: LaTeX Consolidation Pipeline Design

Date: 2026-03-08

## Context

After Phase 1 (page-by-page AI transcription), `accumulated.tex` is a concatenation of 387 independently transcribed pages. It has good structure (`\chapter`, `\section`, `\begin{equation}`) and consistent symbols, but won't compile due to:
- Wrong document class (`article` with `\chapter` commands)
- Some missing `$` delimiters
- Potential cross-page duplications

This design covers three additions to macdoc:
1. AI backend configuration system
2. Mechanical CLI cleanup steps
3. Agent-based consolidation command

## Part 1: AI Config System

### Config File

Location: `~/.config/macdoc/config.json`

```json
{
  "ai": {
    "available": ["codex", "claude", "gemini"],
    "transcription": "codex",
    "agent": "claude"
  }
}
```

### New Type: `AIConfig`

In `PDFToLaTeXCore/AIConfig.swift`:

```swift
public struct AIConfig: Codable, Sendable {
    public var available: [String]       // detected CLI tools
    public var transcription: String     // default for one-shot transcription
    public var agent: String             // default for agentic consolidation

    public static let configURL: URL     // ~/.config/macdoc/config.json
    public static func load() -> AIConfig
    public func save() throws
    public static func detect() -> AIConfig  // runs `which codex/claude/gemini`
}
```

### New CLI Commands

```
macdoc config ai detect       # auto-detect installed tools, write config
macdoc config ai list         # show current config
macdoc config ai set <key> <value>  # e.g., set agent claude
```

Added as `MacDoc.Config.AI` subcommand group in `MacDoc.swift`.

### Integration

- All AI commands read `AIConfig.load()` as default
- `--backend` CLI flag still overrides config
- If no config exists, first AI command auto-runs detect

## Part 2: Mechanical CLI Steps

### 2a. `macdoc pdf normalize`

Input: `--project <path>` (reads `accumulated.tex`)
Output: overwrites `accumulated.tex` (backup to `accumulated.tex.bak`)

Steps:
1. **Document class fix**: If `\chapter` found and preamble uses `article`, change to `book`
2. **Symbol normalization**: Configurable rules (e.g., `\bm{` -> `\boldsymbol{`)
3. **Cross-page dedup**: Compare last 3 lines of page N with first 3 lines of page N+1, remove exact duplicates
4. **Clean markers**: Optionally strip `%% === Page N ===` comments

Implementation: `LaTeXNormalizer` struct in `PDFToLaTeXCore`.

### 2b. `macdoc pdf fix-envs`

Input: `--project <path>`
Output: report + optional auto-fix

Steps:
1. **Parse environment stack**: Track all `\begin{X}`/`\end{X}` with line numbers
2. **Detect mismatches**: Unclosed, extra-closed, or nested same-type environments
3. **Auto-fix mode** (`--fix`): Insert missing `\end{X}` or remove duplicate `\begin{X}`
4. **Report mode** (default): Print issues as structured list

Implementation: `LaTeXEnvChecker` struct in `PDFToLaTeXCore`.

### 2c. `macdoc pdf compile-check`

Input: `--project <path>`
Output: structured error report

Steps:
1. Run `pdflatex -interaction=nonstopmode` (no halt on error)
2. Parse `.log` file for errors (`!` lines) and warnings
3. Categorize errors:
   - `undefined_command`: `! Undefined control sequence`
   - `missing_math`: `! Missing $ inserted`
   - `missing_brace`: `! Missing } inserted`
   - `environment`: `! LaTeX Error: \begin{X} ended by \end{Y}`
   - `other`: anything else
4. Output JSON report to `compile-report.json`
5. `--fix` mode: Auto-fix trivial errors (add `$`, add `\newcommand` stubs for undefined commands)

Implementation: `TexCompileChecker` struct in `PDFToLaTeXCore` (extends existing `TexCompiler`).

## Part 3: Agent Consolidation

### Command

```
macdoc pdf consolidate --project <path> [--agent codex|claude|gemini] [--dry-run]
```

### Flow (Option C: Hybrid)

```
1. Run normalize (mechanical)
2. Run fix-envs --fix (mechanical)
3. Run compile-check (mechanical)
4. Collect remaining errors into error-list.json
5. If errors remain:
   a. Send accumulated.tex + error-list.json to agent
   b. Agent prompt: "Fix ONLY the listed errors. Do not rewrite or restructure."
   c. Agent reads/writes files directly
   d. Re-run compile-check
   e. Repeat up to 3 times
6. Final report: success or remaining issues
```

### Agent Invocation

Based on `AIConfig.agent` (or `--agent` override):

```swift
// codex
["codex", "exec", "-C", projectRoot, "-s", "full",
 "-m", model, "-i", "error-list.json", "-i", "accumulated.tex",
 "-p", prompt]

// claude
["claude", "-p", prompt, "--allowedTools", "Read,Write,Bash"]

// gemini
["gemini", prompt]
```

The prompt includes:
- The error list (from compile-check)
- Instructions to fix only listed errors
- The project directory path (agent reads files itself)

### `--dry-run` Mode

Runs steps 1-4 only (mechanical), prints the error list without invoking agent.
Useful for inspecting what the agent would need to fix.

## File Structure

New files in `PDFToLaTeXCore`:
- `AIConfig.swift` — config system
- `LaTeXNormalizer.swift` — normalize step
- `LaTeXEnvChecker.swift` — environment checking
- `TexCompileChecker.swift` — compilation + error parsing
- `Consolidator.swift` — orchestrates the full pipeline

New CLI commands in `PDFToLaTeXCLI/Commands`:
- `NormalizeCommand.swift`
- `FixEnvsCommand.swift`
- `CompileCheckCommand.swift`
- `ConsolidateCommand.swift`

New subcommands in `MacDoc+Config.swift`:
- `MacDoc.Config.AI.Detect`
- `MacDoc.Config.AI.List`
- `MacDoc.Config.AI.Set`

## Implementation Order

1. `AIConfig` (foundation for everything)
2. `LaTeXNormalizer` + CLI command
3. `LaTeXEnvChecker` + CLI command
4. `TexCompileChecker` + CLI command
5. `Consolidator` + CLI command
6. `MacDoc.Config.AI` subcommands
7. Integration: wire consolidate into macdoc CLI
