## MODIFIED Requirements

### Requirement: insert_equation latex fallback supports documented subset

The `che-word-mcp` server's `insert_equation` MCP tool SHALL accept a `latex:` argument as a fallback when `components:` is not provided. The tool SHALL delegate parsing to `LaTeXMathParser.parse(_ latex: String) throws -> [MathComponent]` from the `latex-math-swift` package and SHALL NOT maintain its own LaTeX parser. The accepted pseudo-LaTeX subset is the set of macros defined in the `latex-math-parsing` capability, which at minimum MUST include: `\frac{a}{b}`, `\sqrt{a}`, `\sqrt[n]{a}`, structural sub/superscript `a_{b}`, `a^{b}`, `a_{b}^{c}`, `a^{c}_{b}`; accents `\hat{}`, `\bar{}`, `\tilde{}`, `\dot{}`, `\overline{}`; delimiter pairs `\left(\right)`, `\left[\right]`, `\left\{\right\}`, `\left|\right|`, `\left\|\right\|`; n-ary operators `\sum_{a}^{b}`, `\int_{a}^{b}`, `\prod_{a}^{b}` (with or without bounds); function names `\ln`, `\sin`, `\cos`, `\tan`, `\log`, `\exp`, `\max`, `\min`, `\det` (with following parenthesized argument); limit forms `\sup_{x}`, `\inf_{x}`, `\lim_{x \to 0}`; text escape `\text{...}`; all lowercase and uppercase Greek letters listed in the `latex-math-parsing` capability (including variants `\varepsilon`, `\vartheta`, `\varphi`); and common operators `\cdot`, `\times`, `\pm`, `\mp`, `\sim`, `\approx`, `\neq`, `\le`, `\ge`, `\to`, `\infty`, `\partial`, `\cdots`, `\ldots`, `\mid`, `\quad`. Syntax outside this subset MUST cause the tool to return an error message naming the first unrecognized token and referring the caller to the `components:` argument for full control. The tool's schema description string (exposed via MCP `tools/list`) SHALL enumerate the supported macro families verbatim and MUST NOT use the previous misleading summary phrase "narrow subset: `\frac{}{}`, `\sqrt{}`, `_{}`, `^{}`, Greek letters, `∑/∫/∏/·/×/±`".

#### Scenario: LaTeX within subset succeeds

- **WHEN** `insert_equation({ latex: "\\frac{a}{b}" })` is called
- **THEN** the inserted paragraph contains `<m:f>` with numerator `a` and denominator `b`

#### Scenario: Unsupported LaTeX macro rejected with clear error

- **WHEN** `insert_equation({ latex: "\\overbrace{abc}" })` is called
- **THEN** the tool returns an error whose message contains both the token `\overbrace` and a reference to the `components:` argument

#### Scenario: All 18 issue-22 fixture equations succeed

- **WHEN** each LaTeX string from the issue #22 fixture table (18 equations covering `\ln`, `\frac`, `\Delta`, `\hat`, `\sup`, `\varepsilon`, `\left\|...\right\|`, nested subscript-superscript) is passed as `insert_equation({ latex: <equation>, display_mode: true })`
- **THEN** every call returns a non-error result whose inserted paragraph contains `<m:oMathPara>` wrapping `<m:oMath>` wrapping structurally valid OMML

#### Scenario: Tool description enumerates accurate macro list

- **WHEN** the MCP `tools/list` request returns the `insert_equation` tool definition
- **THEN** the `latex` parameter's `description` string contains bullet items or equivalent enumeration covering at minimum the macro families `\frac`, `\sqrt`, sub/superscript, accent (`\hat`/`\bar`/`\tilde`), delimiter (`\left`/`\right`), n-ary (`\sum`/`\int`/`\prod`), function name (`\ln`/`\sin`/`\cos`/...), limit form (`\sup`/`\inf`/`\lim`), and `\text{}`
- **AND** the description MUST NOT contain the phrase "narrow subset" describing the content coverage

#### Scenario: Schema description word count stays within budget

- **WHEN** the `insert_equation.parameters.latex.description` string is inspected
- **THEN** its character length is at most 800 characters
- **AND** the description ends with guidance that `components:` remains available for macros outside the enumerated set
