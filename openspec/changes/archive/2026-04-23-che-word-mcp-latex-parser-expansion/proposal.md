## Why

`insert_equation`'s `latex` parameter advertises a "narrow-subset" LaTeX → OMML fallback, but the actual parser in `che-word-mcp/Sources/CheWordMCP/Server.swift:7253-7371` accepts only `\frac{}{}`, `\sqrt{}`, and a hard-coded 30-entry whitelist (22 lowercase Greek letters + 8 symbols). 18/18 fixed-form econometrics equations from a master's thesis (`PsychQuant/che-word-mcp#22`) fail with `unrecognized token` errors on `\ln`, `\hat`, `\Delta`, `\varepsilon`, `\sup`, `\left`, and (transitively) `\frac` whenever any inner sub-expression contains a non-whitelisted macro. The schema description and swiftdoc claim support for `_{}`/`^{}` and lowercase Greek letters, but no structural sub/superscript dispatch exists — `_` and `^` are appended as plain characters, producing `MathRun(text: "∑_{k=1}^{p}")` instead of an `<m:sSubSup>` element, which is not editable in MS Word's native equation editor. This drift between schema and implementation systematically misleads downstream LLM tool-use prompts and blocks any LaTeX-origin docx authoring workflow (theses, technical reports, teaching materials).

## What Changes

- **NEW: `PsychQuant/latex-math-swift` package** — a pure parser library with public API `LaTeXMathParser.parse(_ latex: String) throws -> [MathComponent]`. Depends only on `ooxml-swift` for the `MathComponent` types. No OMML wrapping (`<m:oMath>`, `<m:oMathPara>`), no display-mode handling — those are the caller's responsibility, so PPTX callers (which embed equations differently from Word: OMML inside `<a:t>` or OLE objects) can reuse the same parser without inheriting Word-flavored helpers.
- **NEW: `MathAccent` type in `ooxml-swift`** — emits `<m:acc>` (ECMA-376 §22.1.2.1) for `\hat{}`, `\bar{}`, `\tilde{}`, `\dot{}`, `\overline{}`. `ooxml-swift` bumps to v0.11.0.
- **MODIFIED: `che-word-mcp` `insert_equation` LaTeX subset** — `parseLatexSubset` is replaced by a delegation to `LaTeXMathParser.parse()`. The expanded parser SHALL accept all tokens needed to make 18/18 thesis equations pass: `\frac` / `\sqrt` (existing), structural `_{}` / `^{}` → `MathSubSuperScript`, `\hat` / `\bar` / `\tilde` → `MathAccent`, `\left(...\right)` / `\left|...\right|` / `\left\|...\right\|` / `\left[...\right]` → `MathDelimiter`, `\sum_{}^{}` / `\int_{}^{}` / `\prod_{}^{}` → `MathNary`, `\ln` / `\sin` / `\cos` / `\tan` / `\log` / `\exp` / `\max` / `\min` / `\det` → `MathFunction`, `\sup_{}` / `\inf_{}` / `\lim_{}` → `MathLimit`, `\text{...}` → `MathRun(style: .plain)`, expanded Greek/symbol dictionary including `\varepsilon`, `\Delta`, `\Omega`, `\Phi`, `\Psi`, `\rho`, `\sim`, `\quad`, `\mid`, `\cdots`, `\approx`, `\neq`, `\le`, `\ge`. **BREAKING for tool description only**: the `latex.description` schema string and swiftdoc are rewritten to enumerate the accurate token list, removing the misleading "narrow-subset (`\frac{}{}`, `\sqrt{}`, `_{}`, `^{}`, Greek, ∑/∫/∏/·/×/±)" claim. `che-word-mcp` bumps to v3.2.0.
- **NEW test: 18-equation golden suite** — `Tests/CheWordMCPTests/InsertEquationGoldenTests.swift` parses each fixture, asserts `MathComponent.toOMML()` matches a recorded OMML XML string, and round-trips through `ooxml-swift`'s `OMMLParser` to assert AST equality after read-back. Manual MS Word "double-click → native equation editor" verification documented in test file header.

## Non-Goals (optional)

- **No PPTX integration in this change.** `che-pptx-mcp` adopting `latex-math-swift` is a separate follow-up issue (decided in discuss because Word vs PPTX equation embedding genuinely differs — Word uses inline OMML, PPTX commonly uses OLE-embedded objects or OMML inside `<a:t>` runs — and pre-emptive integration would create unused code paths).
- **No Pandoc-equivalent token coverage.** `\overset`, `\underset`, `\begin{matrix}...\end{matrix}`, `\stackrel`, `\xrightarrow`, and other lower-frequency macros remain unsupported. Phase 3 follow-up.
- **No `components:` JSON snippet hint in error messages.** Issue #22 Option C suggests embedding a per-token `components:` JSON example in the error string. Useful but orthogonal — deferred to a separate UX-focused change after the parser stabilizes.
- **No extraction of `MathComponent` out of `ooxml-swift`.** A neutral standalone math-AST package was considered, but `ooxml-swift` already owns the OMML emit logic and `pptx-swift` already depends on `ooxml-swift`, so no duplication is created by leaving the types in place.
- **No streaming / incremental parser API.** `LaTeXMathParser.parse()` returns `[MathComponent]` synchronously. Equations are short (typical ≤ 200 chars); streaming adds complexity with no measurable benefit.

## Capabilities

### New Capabilities

- `latex-math-parsing`: A LaTeX subset parser producing OMML `MathComponent` ASTs, packaged as `latex-math-swift` (depends on `ooxml-swift`) and reusable across any caller that needs LaTeX → OMML AST conversion (initially `che-word-mcp`, future `che-pptx-mcp`).

### Modified Capabilities

- `che-word-mcp-insertion-tools`: `insert_equation` MCP tool's `latex` parameter SHALL accept the expanded token set listed in What Changes, delegate parsing to `LaTeXMathParser.parse()`, and the tool description SHALL enumerate the accurate token list rather than the previous misleading summary.
- `ooxml-content-insertion-primitives`: `ooxml-swift` SHALL provide a `MathAccent` `MathComponent` conformance emitting `<m:acc>` per ECMA-376 §22.1.2.1, with selectable accent character (combining diacritics for `\hat`, `\bar`, `\tilde`, `\dot`, `\overline`).

## Impact

- **Affected specs**: new `latex-math-parsing` spec; modified `che-word-mcp-insertion-tools` (insert_equation behavior delta); modified `ooxml-content-insertion-primitives` (new MathAccent requirement).
- **Affected code**:
  - **NEW repo `PsychQuant/latex-math-swift`**: `Package.swift`, `Sources/LaTeXMathSwift/{LaTeXMathParser.swift, TokenDictionary.swift, MacroDispatcher.swift, LaTeXParseError.swift}`, `Tests/LaTeXMathSwiftTests/`, `README.md`, `LICENSE`, tag `v0.1.0`.
  - **`packages/ooxml-swift/`** (separate repo `PsychQuant/ooxml-swift`): add `MathAccent` to `Sources/OOXMLSwift/Models/MathComponent.swift`, add tests in `Tests/OOXMLSwiftTests/MathComponentTests.swift`, bump `Package.swift`/CHANGELOG to v0.11.0, tag and push.
  - **`mcp/che-word-mcp/`** (submodule, separate repo): `Package.swift` adds `latex-math-swift ^0.1.0` dep and bumps `ooxml-swift` to `^0.11.0`; `Sources/CheWordMCP/Server.swift` lines 7253-7371 (parser) replaced with `LaTeXMathParser.parse()` delegation; lines 2153 (`latex.description` schema) and 7097-7099 (swiftdoc) rewritten with accurate token list; `mcpb/manifest.json` tool description updated; `Tests/CheWordMCPTests/InsertEquationGoldenTests.swift` added with 18 equation fixtures; `CHANGELOG.md` entry; tag `v3.2.0`.
- **Affected APIs / contracts**:
  - **MCP tool surface (BREAKING in description only, not in contract)**: `insert_equation`'s `latex` parameter accepts a strictly larger superset; existing equations that used to throw will now succeed. The schema `description` string changes — any LLM caller that cached the old description will see updated guidance on next `tools/list` call.
  - **Public Swift API (additive)**: `OOXMLSwift.MathAccent` is new public type; `LaTeXMathSwift.LaTeXMathParser` is a new package's public API.
- **Build sequence (mandatory order)**: (1) `ooxml-swift` v0.11.0 release → (2) `latex-math-swift` v0.1.0 release → (3) `che-word-mcp` v3.2.0 release. Each step requires the prior tag to exist on GitHub before its `Package.resolved` update.
- **Downstream**: any LaTeX-origin docx workflow (theses, technical reports, teaching materials) immediately benefits; future `che-pptx-mcp` equation work can adopt `latex-math-swift` without re-parsing-layer rewrite. No removal of existing capability — `components:` JSON tree input remains supported and is the recommended path for Phase 3 macros not yet covered.
- **Closes**: `PsychQuant/che-word-mcp#22`.
