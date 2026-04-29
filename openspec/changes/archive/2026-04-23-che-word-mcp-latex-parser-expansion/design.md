## Context

`che-word-mcp` ships an `insert_equation` MCP tool with a `latex` argument advertised as a "narrow-subset" pseudo-LaTeX parser. The current implementation in `mcp/che-word-mcp/Sources/CheWordMCP/Server.swift:7253-7371` consists of:

- `parseLatexSubset(_ latex: String) throws -> MathComponent` — top-level dispatcher with hard-coded `\frac{...}{...}` and `\sqrt{...}` matchers, falling through to `parseLatexPlain` for everything else.
- `parseLatexPlain(_ s: String) throws -> MathComponent` — single-pass char loop with a 30-entry `[String: String]` lookup table (22 lowercase Greek + 8 symbols including `\sum \int \prod`). Any `\token` not in the table throws `LatexParseError.unrecognizedToken`. Critically, `_` and `^` characters are appended as plain characters, never producing `MathSubSuperScript`.

The OMML emitter layer in `packages/ooxml-swift/Sources/OOXMLSwift/Models/MathComponent.swift` is in fact rich — it ships 9 `MathComponent` conformances (`MathRun`, `MathFraction`, `MathSubSuperScript`, `MathRadical`, `MathNary`, `MathDelimiter`, `MathFunction`, `MathLimit`, `MathMatrix`) plus an `UnknownMath` round-trip fallback. The current parser only routes to 3 of them. The bottleneck is the parser dispatcher, not the OMML AST.

The triggering incident is `PsychQuant/che-word-mcp#22`: 18 fixed-form econometrics equations from a master's thesis (Vietnam VN30 GARCH analysis) all fail to parse, blocking native Word equation embed for the thesis defense. Equivalent fallback `components:` JSON tree input works but requires hand-writing 30-80 lines of JSON per equation (~1000 LOC total for the thesis).

Stakeholders:
- Thesis author (immediate: P1 deadline this week)
- Future LaTeX-origin docx authoring users (long-term: every theses / technical report / teaching material workflow hits this limit)
- `che-pptx-mcp` maintainer (latent: PPTX equation tools will eventually need the same parser, and Word vs PPTX equation embedding genuinely differs — Word inlines OMML in `<m:oMath>`, PPTX commonly uses OLE-embedded equation editor objects or OMML inside `<a:t>` runs).

Repository constraints:
- `che-word-mcp` is a git submodule under `mcp/che-word-mcp` of the `macdoc` umbrella. Spec lives in macdoc's `openspec/`.
- `ooxml-swift` is a remote-url Swift Package dep, owned by `PsychQuant/ooxml-swift`. Versioned releases.
- `pptx-swift` already depends on `ooxml-swift ^0.7.0` (verified in `packages/pptx-swift/Package.swift`), so adding a new public type to `ooxml-swift` propagates to PPTX consumers automatically.

## Goals / Non-Goals

**Goals:**

- Make 18/18 fixture equations from `PsychQuant/che-word-mcp#22` parse successfully via `insert_equation(latex:)`, producing OMML structurally correct enough that MS Word's "double-click → native equation editor" works.
- Eliminate the schema-vs-implementation drift: the `latex.description` schema string and swiftdoc SHALL accurately enumerate supported tokens.
- Establish a parser/wrapper boundary that lets future `che-pptx-mcp` equation work share the LaTeX → AST conversion without inheriting Word-specific OMML wrapping logic.
- Add OMML accent support (`<m:acc>`) to `ooxml-swift` so `\hat{x}`, `\bar{x}`, `\tilde{x}` produce native editable equations rather than Unicode combining-character hacks.
- Maintain backward compatibility for callers currently using `components:` JSON tree input (no contract change to that path).

**Non-Goals:**

- Pandoc-equivalent token coverage. `\overset`, `\underset`, `\begin{matrix}...\end{matrix}`, `\stackrel`, `\xrightarrow`, `\frac` chained with `\binom`, etc. remain unsupported. These are Phase 3 follow-up.
- Modifying `che-pptx-mcp`. PPTX adoption of `latex-math-swift` is a separate change opened when PPTX equation tooling is prioritized.
- Embedding `components:` JSON snippet hints in error messages (issue #22 Option C). Useful UX but orthogonal to parser correctness; defer to a later UX change.
- Streaming or incremental parser API. Equations are short (typically ≤ 200 chars); synchronous `parse()` returning `[MathComponent]` is sufficient.
- Extracting `MathComponent` types out of `ooxml-swift` into a neutral package. `ooxml-swift` already owns OMML emit logic and `pptx-swift` already depends on it; no duplication is introduced by leaving the types in place.
- Parser-driven LaTeX → MathML translation as an intermediate step. We go straight to OMML AST since both Word and PPTX (when not using OLE) consume OMML, not MathML.

## Decisions

### Decision: Extract parser as new `latex-math-swift` package with pure-parser boundary

**Choice**: Create a new GitHub repo `PsychQuant/latex-math-swift` (Swift Package), depending only on `ooxml-swift` (for `MathComponent` types). Public API surface is one entry point: `LaTeXMathParser.parse(_ latex: String) throws -> [MathComponent]`. The package SHALL NOT emit OMML wrapper elements (`<m:oMath>`, `<m:oMathPara>`), handle display vs inline mode, manage `<w:p>` paragraph wrapping, or write any output XML beyond what `MathComponent.toOMML()` produces from `ooxml-swift`. All wrapping is the caller's responsibility.

**Rationale**: Word and PPTX equation embedding genuinely differ. Word uses inline `<m:oMath>` blocks inside `<w:p>` paragraphs. PowerPoint commonly uses either OLE-embedded `equation.bin` objects (older PPT-compat) or OMML inside `<a:r>`/`<a:t>` text runs (Office 2016+). Both flavors share the LaTeX → AST conversion but diverge on the embedding layer. Putting wrapper logic in `latex-math-swift` would either force PPTX callers to ignore Word-flavored helpers (dead code) or introduce conditional `displayMode: .word | .pptx` flags that pollute the parser API. Pure parser keeps the package's single responsibility crisp and lets each MCP server own its embedding semantics.

**Alternatives considered**:

- **Inline parser in `Server.swift`** (no extraction). Rejected: forces future `che-pptx-mcp` equation tools to either copy-paste the parser or grow a `che-word-mcp` dependency for parsing-only purposes. Both are worse than a small dedicated package.
- **Add parser as a module inside `ooxml-swift`**. Rejected: `ooxml-swift` is the OMML emitter library — adding a LaTeX frontend conflates parsing (input format-specific) with emitting (output format-specific). Future formats (e.g., MathML input) would re-conflate.
- **Parser + Word OMML wrapper helper bundled together** (Option B from discuss). Rejected: PPTX-OLE caller would import an unused Word-specific helper. Not catastrophic but a YAGNI violation; the wrapper is small enough to repeat in callers.

### Decision: Add `MathAccent` to `ooxml-swift`, bump v0.10.0 → v0.11.0

**Choice**: Add a new `public struct MathAccent: MathComponent` to `packages/ooxml-swift/Sources/OOXMLSwift/Models/MathComponent.swift` emitting ECMA-376 §22.1.2.1 `<m:acc>`:

```swift
public struct MathAccent: MathComponent {
    public var base: [MathComponent]
    public var accentChar: String  // combining diacritic, e.g. "\u{0302}" for hat

    public func toOMML() -> String {
        return """
        <m:acc>\
        <m:accPr><m:chr m:val="\(accentChar)"/></m:accPr>\
        <m:e>\(combine(base))</m:e>\
        </m:acc>
        """
    }
}
```

Bump to v0.11.0 (additive, no breaking changes). Update `packages/ooxml-swift/CHANGELOG.md`. Tag and push before `latex-math-swift` work begins.

**Rationale**: 18 fixture equations include `\hat{\rho}`, `\hat{\theta}`, `\hat{\varepsilon}`. Without `MathAccent`, the parser must either fall back to `MathRun(text: "x̂")` using a Unicode combining `\u{0302}` (which renders but is *not* an editable native equation in MS Word) or throw. Both violate the issue acceptance criteria. `<m:acc>` is a first-class OMML element; ECMA-376 specifies the `m:chr` attribute drives accent type, so one struct covers all of `\hat \bar \tilde \dot \overline` via different `accentChar` values.

**Alternatives considered**:

- **Use `UnknownMath(rawXML:)` as escape hatch**. Rejected: `UnknownMath` is a round-trip fallback for parser unknowns, not an emit path. Defeats the AST type-safety story.
- **Combining-diacritic `MathRun` only**. Rejected: not editable in MS Word native equation editor — fails acceptance criteria explicitly.

### Decision: Build sequence requires three ordered releases; no cross-repo PR coupling

**Choice**: The work product ships as three separate releases in strict order:

1. `PsychQuant/ooxml-swift` v0.11.0 (adds `MathAccent`)
2. `PsychQuant/latex-math-swift` v0.1.0 (new repo; depends on `ooxml-swift ^0.11.0`)
3. `PsychQuant/che-word-mcp` v3.2.0 (depends on `latex-math-swift ^0.1.0` + `ooxml-swift ^0.11.0`)

Each step requires the previous tag to exist on GitHub before its `Package.swift` / `Package.resolved` can resolve. No simultaneous multi-repo PRs.

**Rationale**: Swift Package Manager pins `url:` deps by tag. Trying to land all three in parallel with un-tagged commits forces using `path:` overrides during development, which mask integration bugs and break CI on other contributors. Sequential releases also let each layer's tests gate the next layer.

**Alternatives considered**:

- **Monorepo migration** (move `ooxml-swift` and `latex-math-swift` into `macdoc/packages/` with `path:` deps). Rejected: outside scope of this change; `ooxml-swift` is shared with non-`macdoc` consumers.
- **Pre-release tags + `branch:`-based `Package.swift` overrides during development**. Allowed for local iteration but the final shipped versions SHALL use semver tags.

### Decision: Replace `parseLatexSubset` with `LaTeXMathParser.parse()` delegation; preserve all surrounding `Server.swift` equation-insert code

**Choice**: In `mcp/che-word-mcp/Sources/CheWordMCP/Server.swift`:

- Lines 7155-7371 (the `// MARK: - Math parsers (insert_equation helpers)` section): replace `parseLatexSubset`, `parseFracTopLevel`, `parseSingleBracedArg`, `scanBalancedBraceBody`, `parseLatexPlain` with a single call site:

  ```swift
  import LaTeXMathSwift  // new dep

  private func parseLatex(_ latex: String) throws -> [MathComponent] {
      return try LaTeXMathParser.parse(latex)
  }
  ```

- Lines 7090-7130 (`insert_equation` MCP handler entry): keep paragraph-level wrapping logic (`<m:oMathPara>` for display mode, `<m:oMath>` for inline) — these are Word-specific and stay in `Server.swift`.
- Lines 2153 (`latex.description` schema string in tools/list registry) + 7097-7099 (swiftdoc): rewrite to enumerate the accurate supported token list (one bullet per macro family).
- `mcpb/manifest.json` `tools` entry for `insert_equation`: same description rewrite.

**Rationale**: The Word-specific OMML wrapper logic (paragraph-level vs inline math, namespace declarations) is correct as-is — only the parser needs replacing. Keeping the wrapping in `Server.swift` matches the parser/wrapper boundary established in the first decision. Updating schema description in the same PR prevents the drift from re-occurring during a multi-PR landing.

**Alternatives considered**:

- **Keep `parseLatexSubset` as a thin wrapper that calls `LaTeXMathParser.parse()`**. Rejected: useless indirection; the function name now lies (no longer a "subset" of anything specific).
- **Rewrite paragraph wrapping into `latex-math-swift` too**. Rejected: violates the first decision (pure parser).

### Decision: Golden test suite asserts OMML XML strings + round-trips through `OMMLParser`

**Choice**: Create `Tests/CheWordMCPTests/InsertEquationGoldenTests.swift` containing:

1. An `EquationFixture` struct with `(latex: String, expectedOMML: String)` for each of the 18 issue #22 equations.
2. For each fixture: parse via `LaTeXMathParser.parse()`, assert `combine(components).toOMML() == fixture.expectedOMML` after whitespace normalization.
3. For each fixture: write a real `.docx` using the existing `insert_equation` flow, read it back via `ooxml-swift`'s `OMMLParser` (added in v0.10.0 per `che-word-mcp` CLAUDE.md), and assert the parsed AST equals the original `MathComponent` tree (deep `==`).
4. File header documents the manual MS Word verification step (open output `.docx`, double-click each equation, assert native equation editor opens with editable structure — to be re-run when fixtures change).

Add `latex-math-swift` test suite mirroring (1) and (2) for upstream coverage independent of `che-word-mcp` integration.

**Rationale**: No-throw assertions are insufficient — the historic bug was that `\sum_{k=1}^{p}` *didn't throw* but produced structurally wrong `MathRun(text: "∑_{k=1}^{p}")`. Comparing OMML XML strings catches this. Round-trip via `OMMLParser` catches subtler write-then-read bugs (e.g., element-order-dependent issues that XML string compare misses if the writer happens to be deterministic but the reader is order-sensitive). The manual MS Word check covers the only remaining gap (OMML structurally valid but Word's editor refuses it) — this is documented but not automated, since automating MS Word UI is outside reasonable test scope.

**Alternatives considered**:

- **Pure structural assertion (compare `[MathComponent]` trees, no XML strings)**. Rejected: doesn't catch OMML emitter regressions in `ooxml-swift` itself. XML string compare keeps the contract honest end-to-end.
- **Snapshot-test the entire `.docx` ZIP**. Rejected: too coarse — any unrelated file (e.g., `app.xml` timestamp) would create false diffs. Targeted OMML XML compare is more diagnostic.

## Risks / Trade-offs

- **OMML correctness diverges from MS Word's tolerance** → Mitigation: every new fixture in the golden set must be manually opened in MS Word once before merging. Document the verification matrix in the test file header. CI cannot replace this gate.

- **`m:sSubSup` sub/sup ordering ambiguity** for `\sum^{n}_{i=1}` (sup-then-sub form) → Mitigation: `LaTeXMathParser` SHALL normalize both `_..^..` and `^.._..` to the same `MathSubSuperScript(sub:, sup:)` and emit `<m:sub>` before `<m:sup>` per ECMA-376 §22.1.2.86. Add a fixture for the sup-first form.

- **Recursion depth on nested fractions** (e.g., `\frac{\hat{\rho}_{k}^{2}}{T-k}` from issue #22 #3) → Mitigation: `LaTeXMathParser` is recursive-descent. Stress-test with a 5-level-deep fixture (`\frac{\frac{\frac{a}{b}}{c}}{\frac{d}{e}}`) in the parser unit tests. Swift's default stack is 512KB which accommodates ~10K levels — far beyond any realistic equation.

- **Cross-repo build sequence breaks if a tag is reverted** → Mitigation: each release goes through `make release` (or equivalent) with a 30-min cooling-off before the next layer's PR opens. Document in `latex-math-swift` README that yanking v0.1.0 would break `che-word-mcp ^3.2.0`.

- **Schema description becomes long and verbose, hurting LLM prompt budgets** → Mitigation: structure the description as `Supported macros: [enumerated list]. For unsupported macros use components: argument.` Keep under 500 chars. Test by counting tokens in the new description string.

- **`\sum` dual semantics in transition** — old code mapped `\sum` to Unicode `∑` plain char (works without `_/^`); new parser maps `\sum_{...}^{...}` to `MathNary` and bare `\sum` to `MathRun(text: "∑")`. → Mitigation: parser SHALL look ahead for `_` or `^` immediately after `\sum` (and `\int`, `\prod`) to disambiguate. Add fixture for both bare and decorated forms. Same logic applies to `\lim_{x \to 0}` (with limit) vs bare `\lim` (without).

- **Backward-incompat regression**: a caller that was relying on the *current* failure of, say, `\Delta` to validate input will now silently succeed. → Mitigation: Considered acceptable. The tool advertises LaTeX support; expanding the accepted set is the explicit purpose. CHANGELOG entry for `che-word-mcp v3.2.0` SHALL flag this as a behavior expansion.

- **Two parser code paths** (LaTeX → AST and `components:` JSON → AST) remain in `che-word-mcp` → Mitigation: Acceptable. `components:` is the explicit escape hatch for macros not yet in the parser. Long-term, the parser may grow to cover everything `components:` can express, at which point the JSON path could be deprecated — out of scope for this change.

- **`latex-math-swift` becomes the bottleneck for any future LaTeX work** → Mitigation: `LaTeXMathParser.parse()` returns `[MathComponent]` so callers can inspect / transform / reject the AST before emitting. Adding a new macro is a single-file change in `MacroDispatcher.swift`. Public API SHALL remain `parse(_ latex: String) throws -> [MathComponent]` for v0.x; v1.0 can add streaming or incremental APIs without breaking it.
