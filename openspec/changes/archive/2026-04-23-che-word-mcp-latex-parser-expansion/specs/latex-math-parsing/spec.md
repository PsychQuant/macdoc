## ADDED Requirements

### Requirement: LaTeXMathParser exposes a single public parse entry point

The `latex-math-swift` package SHALL provide a public type `LaTeXMathParser` with one public static method `parse(_ latex: String) throws -> [MathComponent]`. The method SHALL accept a UTF-8 LaTeX subset string and return an array of `MathComponent` values from the `OOXMLSwift` package representing the parsed expression in document order. The method SHALL throw `LaTeXParseError` for any input it cannot parse. The package MUST NOT expose any other public top-level type, and SHALL NOT emit OMML wrapper elements (`<m:oMath>`, `<m:oMathPara>`, `<m:r>` outside what `MathComponent.toOMML()` produces) — wrapper responsibility belongs to the caller.

#### Scenario: Single fraction parses to MathFraction

- **WHEN** `LaTeXMathParser.parse("\\frac{a}{b}")` is called
- **THEN** the result is `[MathFraction(numerator: [MathRun(text: "a")], denominator: [MathRun(text: "b")])]`

#### Scenario: Empty input throws

- **WHEN** `LaTeXMathParser.parse("")` is called
- **THEN** the call throws `LaTeXParseError.empty`

#### Scenario: Whitespace-only input throws

- **WHEN** `LaTeXMathParser.parse("   ")` is called
- **THEN** the call throws `LaTeXParseError.empty`

### Requirement: LaTeXMathParser supports the expanded macro coverage required by issue #22

`LaTeXMathParser.parse()` SHALL accept and produce structurally correct OMML AST for every macro listed below. Each macro MUST map to the named `MathComponent` from `OOXMLSwift`. Inputs containing only these macros (in any nesting up to recursion depth 32) MUST NOT throw.

| Macro | OOXMLSwift type |
|---|---|
| `\frac{a}{b}` | `MathFraction` |
| `\sqrt{a}` | `MathRadical` (degree nil) |
| `\sqrt[n]{a}` | `MathRadical` (degree `[MathRun(text: "n")]`) |
| `a_{b}`, `a^{b}`, `a_{b}^{c}`, `a^{c}_{b}` | `MathSubSuperScript` |
| `\hat{x}`, `\bar{x}`, `\tilde{x}`, `\dot{x}`, `\overline{x}` | `MathAccent` with combining diacritic |
| `\left(...\right)`, `\left[...\right]`, `\left\{...\right\}`, `\left\|...\right\|`, `\left|...\right|` | `MathDelimiter` |
| `\sum_{a}^{b} f`, `\int_{a}^{b} f`, `\prod_{a}^{b} f`, bare `\sum f` (no bounds) | `MathNary` |
| `\ln`, `\sin`, `\cos`, `\tan`, `\log`, `\exp`, `\max`, `\min`, `\det` (with following `(...)` argument) | `MathFunction` |
| `\sup_{x} f`, `\inf_{x} f`, `\lim_{x \to 0} f` | `MathLimit` |
| `\text{abc}` | `MathRun` with `style: .plain` |
| All ECMA-376 §22.1.2.93 lowercase Greek letters from `\alpha` through `\omega` | `MathRun` with the Unicode codepoint |
| Greek letter variants: `\varepsilon`, `\vartheta`, `\varphi`, `\varpi`, `\varrho`, `\varsigma` | `MathRun` with the variant Unicode codepoint |
| Uppercase Greek letters: `\Gamma`, `\Delta`, `\Theta`, `\Lambda`, `\Xi`, `\Pi`, `\Sigma`, `\Phi`, `\Psi`, `\Omega` | `MathRun` with the uppercase Unicode codepoint |
| Common operators: `\cdot`, `\times`, `\pm`, `\mp`, `\sim`, `\approx`, `\neq`, `\le`, `\leq`, `\ge`, `\geq`, `\to`, `\rightarrow`, `\infty`, `\partial`, `\nabla`, `\cdots`, `\ldots`, `\mid`, `\quad`, `\,` (thin space) | `MathRun` with the Unicode codepoint |

#### Scenario: Nested fraction with accent and subscript-superscript parses

- **WHEN** `LaTeXMathParser.parse("\\frac{\\hat{\\rho}_{k}^{2}}{T-k}")` is called
- **THEN** the result is a single `MathFraction` whose numerator contains a `MathSubSuperScript` whose base is a `MathAccent(base: [MathRun(text: "ρ")], accentChar: "\u{0302}")`, sub `[MathRun(text: "k")]`, sup `[MathRun(text: "2")]`, and whose denominator contains the runs `T`, `-`, `k`

#### Scenario: Sum with both bounds parses to MathNary

- **WHEN** `LaTeXMathParser.parse("\\sum_{k=1}^{p} a_k")` is called
- **THEN** the result contains exactly one `MathNary(op: .sum, sub: [...], sup: [...], base: [...])` whose `sub` parses `k=1`, `sup` parses `p`, and `base` parses `a_k` as a `MathSubSuperScript`

#### Scenario: Sup-first then sub normalizes to same MathSubSuperScript as sub-first then sup

- **WHEN** `LaTeXMathParser.parse("x^{2}_{k}")` is called
- **AND** `LaTeXMathParser.parse("x_{k}^{2}")` is called
- **THEN** both return the identical `[MathSubSuperScript(base: [MathRun(text: "x")], sub: [MathRun(text: "k")], sup: [MathRun(text: "2")])]`

#### Scenario: Left-right delimiter pair with double bar parses

- **WHEN** `LaTeXMathParser.parse("\\left\\|F_1(x)-F_2(x)\\right\\|")` is called
- **THEN** the result contains exactly one `MathDelimiter(open: "‖", close: "‖", elements: [...], separator: "")`

#### Scenario: Variant Greek letter varepsilon maps to lowercase epsilon variant codepoint

- **WHEN** `LaTeXMathParser.parse("\\varepsilon_{t}")` is called
- **THEN** the result is `[MathSubSuperScript(base: [MathRun(text: "ε")], sub: [MathRun(text: "t")], sup: nil)]`

#### Scenario: Function name with parenthesized argument

- **WHEN** `LaTeXMathParser.parse("\\ln(P_t)")` is called
- **THEN** the result is `[MathFunction(functionName: [MathRun(text: "ln")], argument: [MathSubSuperScript(base: [MathRun(text: "P")], sub: [MathRun(text: "t")], sup: nil)])]`

#### Scenario: Plain text inside math via text macro

- **WHEN** `LaTeXMathParser.parse("HL = \\frac{\\ln(0.5)}{\\ln(\\text{persistence})}")` is called
- **THEN** the result includes a `MathRun(text: "persistence", style: .plain)` inside the second `MathFunction`'s argument

### Requirement: LaTeXMathParser throws structured errors naming the unsupported token

Any input containing a `\token` not listed in the Requirement above MUST cause `LaTeXMathParser.parse()` to throw `LaTeXParseError.unrecognizedToken(token: String)` where the associated value is the verbatim token starting with backslash and ending at the first non-letter character. Any malformed brace nesting (unterminated `{`, mismatched `\left`/`\right`) MUST throw `LaTeXParseError.malformed(message: String)` whose message describes the structural problem. The parser MUST NOT silently produce structurally wrong output for unrecognized input.

#### Scenario: Unrecognized macro throws with token name

- **WHEN** `LaTeXMathParser.parse("\\overbrace{abc}")` is called
- **THEN** the call throws `LaTeXParseError.unrecognizedToken(token: "\\overbrace")`

#### Scenario: Unterminated brace throws malformed

- **WHEN** `LaTeXMathParser.parse("\\frac{a}{b")` is called
- **THEN** the call throws `LaTeXParseError.malformed` whose message contains `unterminated`

#### Scenario: Mismatched delimiter throws malformed

- **WHEN** `LaTeXMathParser.parse("\\left(x\\right]")` is called
- **THEN** the call throws `LaTeXParseError.malformed` whose message names both `\left(` and `\right]`

### Requirement: LaTeXMathParser depends only on OOXMLSwift

The `latex-math-swift` Swift Package manifest (`Package.swift`) MUST declare exactly one external dependency: `PsychQuant/ooxml-swift` at minimum version `0.11.0`. The package SHALL NOT depend on `che-word-mcp`, `pptx-swift`, or any other PsychQuant Swift package. The library product SHALL be named `LaTeXMathSwift` and the test target `LaTeXMathSwiftTests`.

#### Scenario: Package.swift exposes only LaTeXMathSwift product

- **WHEN** `swift package describe --type json` is run in the `latex-math-swift` repo
- **THEN** the output `products` array contains exactly one entry with name `LaTeXMathSwift` and type `library`
- **AND** the `dependencies` array contains exactly one URL `https://github.com/PsychQuant/ooxml-swift.git` with version range starting at `0.11.0`
