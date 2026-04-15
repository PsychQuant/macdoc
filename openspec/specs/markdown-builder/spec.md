# markdown-builder Specification

## Purpose

Programmatic markdown generation API in the `markdown-swift` package — heading, table, bullet/numbered list, code block, paragraph builders. Used by MCP tools and converters to compose markdown output without ad-hoc string concatenation.

## Requirements

### Requirement: Programmatic markdown construction API

The `markdown-swift` package SHALL expose a `MarkdownBuilder` value type that constructs markdown documents through chainable method calls and returns a `String` containing valid CommonMark-compliant markdown.

#### Scenario: Build a document with heading, paragraph, and table

- **WHEN** a caller creates a `MarkdownBuilder`, calls `.heading(level: 1, text: "Title")`, `.paragraph("Intro text.")`, `.table(headers: ["A", "B"], rows: [["1", "2"]])`, then `.build()`
- **THEN** the returned string contains the heading on its own line prefixed with `# `, a blank line, the paragraph text on its own line, a blank line, and a markdown table with header row, separator row, and data rows

#### Scenario: Build is idempotent

- **WHEN** a caller calls `.build()` twice on the same `MarkdownBuilder` instance without further mutation
- **THEN** both calls return the identical string

<!-- @trace
source: manuscript-review-markdown-export
updated: 2026-04-15
code:
  - packages/markdown-swift/Sources/MarkdownSwift/MarkdownBuilder.swift
-->

---

### Requirement: Heading builder

The `MarkdownBuilder` SHALL provide a `heading(level:text:)` method that accepts a level integer in the range 1 through 6 and a non-empty text string.

#### Scenario: Standard heading levels

- **WHEN** `heading(level: 3, text: "Section")` is called
- **THEN** the output contains `### Section` followed by a blank line

#### Scenario: Level out of range fails fast

- **WHEN** `heading(level: 0, ...)` or `heading(level: 7, ...)` is called
- **THEN** the builder traps with a precondition failure indicating the valid range

<!-- @trace
source: manuscript-review-markdown-export
updated: 2026-04-15
code:
  - packages/markdown-swift/Sources/MarkdownSwift/MarkdownBuilder.swift
-->

---

### Requirement: Paragraph builder

The `MarkdownBuilder` SHALL provide a `paragraph(_ text:)` method that emits a paragraph with a trailing blank line, and SHALL escape characters that would otherwise be interpreted as markdown syntax (asterisks, underscores, backticks, square brackets, pipes) inside the input text.

#### Scenario: Plain paragraph

- **WHEN** `paragraph("Hello world.")` is called
- **THEN** the output contains `Hello world.` followed by a blank line

#### Scenario: Special characters are escaped

- **WHEN** `paragraph("Use *emphasis* and _underscore_ literally.")` is called
- **THEN** the output contains `Use \*emphasis\* and \_underscore\_ literally.` so that the asterisks and underscores render as literal characters in CommonMark renderers

<!-- @trace
source: manuscript-review-markdown-export
updated: 2026-04-15
code:
  - packages/markdown-swift/Sources/MarkdownSwift/MarkdownBuilder.swift
-->

---

### Requirement: Table builder

The `MarkdownBuilder` SHALL provide a `table(headers:rows:)` method that accepts a non-empty array of header strings and an array of row arrays (zero or more rows), and SHALL produce a GitHub-flavored markdown pipe table where every row has the same number of cells as the headers.

#### Scenario: Standard table

- **WHEN** `table(headers: ["Name", "Count"], rows: [["alpha", "1"], ["beta", "2"]])` is called
- **THEN** the output contains a header row `| Name | Count |`, a separator row `| --- | --- |`, and two data rows `| alpha | 1 |` and `| beta | 2 |`, followed by a blank line

#### Scenario: Empty rows produces header-only table

- **WHEN** `table(headers: ["A"], rows: [])` is called
- **THEN** the output contains the header and separator rows but no data rows, followed by a blank line

#### Scenario: Row width mismatch fails fast

- **WHEN** `table(headers: ["A", "B"], rows: [["only one cell"]])` is called
- **THEN** the builder traps with a precondition failure indicating the row index and expected versus actual cell count

#### Scenario: Pipe characters in cell content are escaped

- **WHEN** a cell contains a literal `|` character
- **THEN** the emitted cell escapes it as `\|` so the table parses correctly

<!-- @trace
source: manuscript-review-markdown-export
updated: 2026-04-15
code:
  - packages/markdown-swift/Sources/MarkdownSwift/MarkdownBuilder.swift
-->

---

### Requirement: Bullet list and numbered list builders

The `MarkdownBuilder` SHALL provide `bulletList(_ items:)` and `numberedList(_ items:)` methods that accept arrays of strings and emit indented list blocks followed by a blank line.

#### Scenario: Bullet list

- **WHEN** `bulletList(["first", "second", "third"])` is called
- **THEN** the output contains three lines starting with `- ` followed by each item, then a blank line

#### Scenario: Numbered list

- **WHEN** `numberedList(["alpha", "beta"])` is called
- **THEN** the output contains lines starting with `1. ` and `2. ` respectively, then a blank line

#### Scenario: Empty list emits nothing

- **WHEN** `bulletList([])` or `numberedList([])` is called
- **THEN** the builder appends nothing to the output

<!-- @trace
source: manuscript-review-markdown-export
updated: 2026-04-15
code:
  - packages/markdown-swift/Sources/MarkdownSwift/MarkdownBuilder.swift
-->

---

### Requirement: Code block builder

The `MarkdownBuilder` SHALL provide a `codeBlock(_ code:language:)` method that emits a fenced code block with optional language identifier.

#### Scenario: Code block with language

- **WHEN** `codeBlock("let x = 1", language: "swift")` is called
- **THEN** the output contains a line ` ```swift `, the code line, a closing ` ``` ` line, and a trailing blank line

#### Scenario: Code block without language

- **WHEN** `codeBlock("plain text", language: nil)` is called
- **THEN** the output contains ` ``` ` opening fence with no language identifier, the code, the closing fence, and a trailing blank line

<!-- @trace
source: manuscript-review-markdown-export
updated: 2026-04-15
code:
  - packages/markdown-swift/Sources/MarkdownSwift/MarkdownBuilder.swift
-->

---

### Requirement: Builder is value-type and chainable

`MarkdownBuilder` SHALL be a Swift `struct` (value type) and each builder method SHALL return `Self` so that method calls can be chained without intermediate variables.

#### Scenario: Method chaining produces same result as sequential calls

- **WHEN** a caller chains `MarkdownBuilder().heading(level: 1, text: "T").paragraph("p").build()` and a second caller calls each method as separate statements on a `var` builder and calls `build()`
- **THEN** both produce identical output strings
