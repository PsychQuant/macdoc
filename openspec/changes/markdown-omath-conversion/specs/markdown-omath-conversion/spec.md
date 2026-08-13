## ADDED Requirements

### Requirement: Markdown-to-Word exposes an opt-in native math mode

The `MDToWord` library SHALL expose a public `MarkdownMathMode` enum with raw string values `literal` and `omath`. `MarkdownToWordConverter` SHALL provide `init(mathMode: MarkdownMathMode = .literal)`. The default initializer and every conversion using `.literal` SHALL preserve dollar-delimited input as ordinary Markdown text and SHALL NOT invoke LaTeX parsing.

#### Scenario: Default converter preserves delimiters

- **WHEN** `MarkdownToWordConverter()` converts `Before $x^2$ after`
- **THEN** the generated document contains the literal text `$x^2$`
- **AND** `word/document.xml` contains no `<m:oMath` element

#### Scenario: Explicit literal mode is equivalent to the default

- **WHEN** the same Markdown is converted once with `MarkdownToWordConverter()` and once with `MarkdownToWordConverter(mathMode: .literal)`
- **THEN** both generated document models have equivalent paragraph text and contain no OMML elements

#### Scenario: Public client can select OMath mode

- **WHEN** an external Swift target imports `MDToWord` without `@testable`
- **THEN** `MarkdownToWordConverter(mathMode: .omath)` type-checks

### Requirement: OMath mode recognizes conservative dollar delimiters

In `.omath` mode, the converter SHALL recognize inline math only from a pair of unescaped single-dollar delimiters within non-code Markdown content. The first and last formula characters SHALL be non-whitespace, and an inline formula SHALL NOT contain a newline. The converter SHALL recognize display math only when a `$$...$$` pair occupies an entire logical paragraph, either on one trimmed line or between standalone opening and closing delimiter lines. Unmatched dollars SHALL remain literal.

The converter SHALL derive formula-eligible ranges from the original CommonMark tree before replacing source text. Inline formulas SHALL fit within one eligible original `Text` range. Display formulas SHALL fit within one eligible original `Paragraph` range whose inline descendants are limited to text and line breaks. Code, HTML, autolink, link/reference/image destinations, reference metadata, and delimiters split across formatting nodes SHALL remain non-math content. Source-range indexing, collision indexing, and replacement SHALL use a bounded number of linear passes over source characters. A placeholder SHALL be selected only after confirming that its numeric suffix does not occur in caller input.

Every generated placeholder SHALL be consumed exactly once by an allowed visible inline or display carrier. A placeholder that is absent, repeated, or present in HTML, metadata, a relationship target, or any other non-carrier location SHALL cause conversion to fail before destination replacement.

#### Scenario: Inline recognition boundary table

- **WHEN** `.omath` conversion receives each input below
- **THEN** recognition matches the expected result

##### Example: Inline recognition boundaries

| Markdown source | Recognized formula count | Literal content retained |
| --- | ---: | --- |
| `Before $x^2$ after` | 1 | `Before ` and ` after` |
| `Price \\$5` | 0 | `$5` |
| ``Code `$x$` end`` | 0 | `$x$` |
| `[link](https://example.com/$x$)` | 0 | relationship target is unchanged |
| `Unmatched $x` | 0 | `$x` |
| `$ spaced $` | 0 | `$ spaced $` |

#### Scenario: Fenced code remains non-math

- **WHEN** a fenced code block contains `$x$` and `$$y$$`
- **THEN** both delimiter pairs remain code text
- **AND** the generated paragraph for the code block contains no OMML element

#### Scenario: Multiline display formula is recognized

- **WHEN** `.omath` conversion receives a paragraph containing standalone `$$`, then `\\frac{a}{b}`, then standalone `$$`
- **THEN** exactly one display formula is recognized with source body `\\frac{a}{b}`

#### Scenario: Display formula cannot cross original CommonMark boundaries

- **WHEN** `.omath` conversion receives standalone `$$` delimiters separated by blank paragraphs, different list items, or a blockquote/container change
- **THEN** conversion throws `MarkdownMathConversionError.misplacedDisplayFormula` at the opening delimiter
- **AND** no destination is created or replaced

#### Scenario: HTML and formatting-node spans remain non-math

- **WHEN** `.omath` conversion receives dollar delimiters inside an HTML comment, HTML block, quoted HTML attribute, or split around an `Emphasis` or `Strong` node
- **THEN** no formula token is created from those delimiters
- **AND** no generated placeholder appears in visible document text

#### Scenario: CommonMark destinations and reference metadata are byte-preserving

- **WHEN** `.omath` conversion receives a multiline reference label, an angle-bracket destination containing `)`, a multiline inline or image destination, or a valid optional reference title containing dollar delimiters
- **THEN** every parsed relationship target remains byte-exact
- **AND** no generated placeholder appears in a target or reference metadata

#### Scenario: Invalid HTML-like visible text remains math-eligible

- **WHEN** CommonMark parses `$x$` as visible `Text` inside `<span $x$>`, `<$x$>`, or an invalid quoted opening tag followed by a closing tag
- **THEN** `.omath` mode converts `$x$` to one inline OMath carrier
- **AND** the visible angle-bracket text remains present without a generated placeholder

#### Scenario: Visible text after invalid reference-like syntax remains eligible

- **WHEN** a line beginning with reference-like or title-like syntax is parsed by CommonMark as visible text containing `$x$`
- **THEN** `.omath` mode converts `$x$` as ordinary visible inline math

#### Scenario: Every token has one allowed consumer

- **WHEN** scanning produces formula tokens and the transformed CommonMark tree is built
- **THEN** each token is consumed exactly once by one visible inline text carrier or one standalone display paragraph
- **AND** any missing, duplicate, metadata, HTML, or relationship consumer causes a pre-write conversion failure

##### Example: One inline and one display carrier

- **GIVEN** source `Before $x$` followed by a separate `$$y$$` paragraph
- **WHEN** conversion succeeds in `.omath` mode
- **THEN** the inline token is consumed once by `<m:oMath>` and the display token once by `<m:oMathPara>`
- **AND** neither placeholder remains in document XML or relationships

#### Scenario: Display delimiter mixed with paragraph text is rejected

- **WHEN** `.omath` conversion receives `before $$x$$ after` in one paragraph
- **THEN** conversion throws `MarkdownMathConversionError.misplacedDisplayFormula` with a one-based line and column

### Requirement: Recognized formulas use the versioned LaTeX parser

Every recognized formula SHALL be parsed by `LaTeXMathParser.parse(_:)` from `latex-math-swift` version 0.2.0 or a backward-compatible later release. The converter SHALL use the parser's frozen supported subset and SHALL NOT implement a second macro parser. Parser results SHALL be serialized by joining each returned `MathComponent.toOMML()` fragment in document order.

#### Scenario: Supported fraction delegates to parser output

- **WHEN** `.omath` conversion receives `$\\frac{a}{b}$`
- **THEN** the generated OMML contains one `m:f` with numerator `a` and denominator `b`

#### Scenario: Unsupported macro is normalized to an MDToWord error

- **WHEN** `.omath` conversion receives `$\\overbrace{x}$`
- **THEN** conversion throws `MarkdownMathConversionError.unsupportedFormula`
- **AND** the error contains the one-based source line and column of the opening delimiter

#### Scenario: Malformed formula is normalized to an MDToWord error

- **WHEN** `.omath` conversion receives `$\\frac{a}{b$`
- **THEN** conversion throws `MarkdownMathConversionError.malformedFormula`
- **AND** the error contains the one-based source line and column of the opening delimiter

### Requirement: Inline and display math use native Word carriers

An inline formula SHALL serialize as one direct paragraph child `<m:oMath>` containing the parsed OMML components. A display formula SHALL serialize as one direct paragraph child `<m:oMathPara>` containing one `<m:oMath>` and SHALL NOT generate a synthetic `<w:t>` run for the formula. Generated XML containing either carrier SHALL bind prefix `m` to `http://schemas.openxmlformats.org/officeDocument/2006/math`.

#### Scenario: Mixed text and inline formula preserve source order

- **WHEN** `.omath` conversion receives `Before $x^2$ after`
- **THEN** `word/document.xml` orders a text run containing `Before `, one `<m:oMath>`, and a text run containing ` after`
- **AND** no literal `$x^2$` remains

##### Example: Inline carrier sequence

- **GIVEN** source `Before $x^2$ after`
- **WHEN** it is converted in `.omath` mode
- **THEN** the paragraph child sequence is `w:r`, `m:oMath`, `w:r`

#### Scenario: Display formula uses oMathPara

- **WHEN** `.omath` conversion receives a standalone display formula `$$\\frac{a}{b}$$`
- **THEN** its paragraph contains exactly one `<m:oMathPara>` and exactly one nested `<m:oMath>`
- **AND** the paragraph contains no literal delimiters and no synthetic `<w:t>` for the formula

#### Scenario: Streaming XML declares the math namespace

- **WHEN** the `DocumentConverter.convert` streaming surface emits a document containing inline or display math
- **THEN** the document root binds `xmlns:m` to the standard Office Math namespace
- **AND** an XML parser accepts the emitted document

### Requirement: Formula failures occur before destination replacement

`convertMarkdown`, `convertToDocument`, and `convertToFile` SHALL parse every recognized formula before returning success. `convertToFile` SHALL NOT invoke the DOCX writer when scanning or formula parsing fails. On failure, a nonexistent destination SHALL remain absent and an existing destination SHALL remain byte-identical.

#### Scenario: Unsupported formula leaves absent destination absent

- **WHEN** `convertToFile` receives `$\\overbrace{x}$` in `.omath` mode and the destination does not exist
- **THEN** conversion throws `MarkdownMathConversionError.unsupportedFormula`
- **AND** the destination is not created

#### Scenario: Malformed formula preserves existing destination

- **GIVEN** an existing destination containing sentinel bytes `KEEP`
- **WHEN** `convertToFile` receives `$\\frac{a}{b$` in `.omath` mode
- **THEN** conversion throws `MarkdownMathConversionError.malformedFormula`
- **AND** the destination bytes remain exactly `KEEP`

### Requirement: Documentation states the native math boundary

The route documentation SHALL state that native OMath is opt-in, SHALL name `literal` as the default, SHALL list the supported macro families by linking to `latex-math-swift`, and SHALL state that full TeX and Pandoc texmath parity are outside this capability.

#### Scenario: Conversion documentation identifies mode and subset

- **WHEN** a user reads the Markdown-to-DOCX route documentation
- **THEN** the documentation shows `--math omath`, the literal default, and the parser-subset boundary
