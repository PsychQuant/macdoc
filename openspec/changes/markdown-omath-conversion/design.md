## Context

`MarkdownToWordConverter` currently parses Markdown with `swift-markdown` and turns inline AST nodes into `OOXMLSwift.Run` values. Dollar-delimited math has no dedicated AST node in this parser configuration, so delimiters remain ordinary text. The repository already maintains two suitable lower layers: `latex-math-swift` v0.2.0 parses a frozen LaTeX subset into `[MathComponent]`, and `ooxml-swift` serializes those components as OMML.

The integration must preserve the existing output for callers that do not opt in, must not parse Markdown code or link destinations as equations, and must fail before replacing an output file when a recognized formula is unsupported.

## Goals / Non-Goals

**Goals:**

- Add a stable public `MarkdownMathMode` with `.literal` and `.omath` cases.
- Convert conservative inline and display dollar delimiters to the correct native Word OMML carriers.
- Reuse the versioned `LaTeXMathParser` and expose stable MDToWord-layer errors with source locations.
- Preserve Markdown structure around formulas and exclude code, destinations, and escaped dollars.
- Prove package API and compiled CLI behavior, including destination preservation on formula failure.

**Non-Goals:**

- Full TeX, MathJax, KaTeX, or Pandoc texmath compatibility.
- A new LaTeX parser or changes to the existing `latex-math-parsing` contract.
- Math conversion in Markdown-to-HTML, PDF, or unrelated routes.
- Formulas crossing fenced-code, inline-code, link-destination, HTML-tag, or Markdown block boundaries.
- Automatic fallback from an invalid recognized formula to literal text in `.omath` mode.

## Decisions

### Public math mode is converter configuration with a literal default

`MDToWord` will expose:

```swift
public enum MarkdownMathMode: String, Sendable {
    case literal
    case omath
}

public init(mathMode: MarkdownMathMode = .literal)
```

The mode belongs to `MarkdownToWordConverter`, not shared `ConversionOptions`, because it is input-format-specific and no other converter consumes it. Existing initializers and calls retain literal behavior. The CLI defines an ArgumentParser-facing enum with the same two raw values and passes it to the converter only for Markdown-to-DOCX.

Alternatives rejected:

- Adding math fields to `CommonConverterSwift.ConversionOptions` would impose an irrelevant public option on every converter.
- Enabling OMath by default would change existing documents and turn previously harmless dollar text into parse errors.

### A conservative lexical tokenizer runs before the Markdown AST builder

An internal `MarkdownMathScanner` will produce a transformed Markdown string plus a token table. It replaces recognized math spans with collision-resistant placeholders before `swift-markdown` parses the document. This preserves surrounding emphasis, headings, lists, quotes, and tables while preventing the Markdown parser from interpreting LaTeX punctuation.

The scanner is a single forward pass with explicit states for fenced code, equal-length backtick code spans, escaped characters, angle-bracket HTML/autolink regions, and Markdown link/image destinations. It recognizes:

- inline math: one unescaped `$`, non-whitespace first and last formula characters, no newline, and a valid closing `$`;
- display math: `$$...$$` occupying an entire logical paragraph, either on one trimmed line or with standalone opening and closing delimiter lines.

Unmatched dollars remain literal. A matched display token found alongside non-whitespace paragraph content is rejected rather than silently converted inline. A token placeholder is generated only after proving it does not already occur in the source.

Alternatives rejected:

- A regular expression cannot reliably exclude code, escapes, or link destinations.
- Scanning decoded `Text.string` values loses enough source spelling to distinguish escaped dollars.
- Invoking Pandoc introduces a subprocess and a second conversion pipeline instead of using the maintained Swift parser.

### Tokens become direct paragraph children with carrier-specific wrappers

Inline tokens are emitted as `Run.rawXML` containing one `<m:oMath>...</m:oMath>` fragment. Since `Run.rawXML` is serialized verbatim as a paragraph child, it is not wrapped in an invalid `<w:r>` container.

Display tokens create a paragraph whose `unrecognizedChildren` contains one direct `<m:oMathPara><m:oMath>...</m:oMath></m:oMathPara>` child and no synthetic text run. Both wrappers use `MathComponent.toOMML()` for their interior. The streaming XML route adds the standard math namespace whenever generated body XML contains an `m:` element; the DOCX writer route uses the OOXML writer's namespace-aware document serializer.

Surrounding Markdown run properties do not alter OMML nodes in v1. A formula remains structurally positioned inside the surrounding paragraph, but bold or italic Markdown wrappers do not rewrite `m:rPr`.

### Recognized formula failures are stable, located, and pre-write

`MDToWord` will expose a public `MarkdownMathConversionError` that reports the one-based line and column of a recognized formula and a stable reason category: malformed or unsupported. Internal `LaTeXParseError` details are normalized into this type so callers do not depend on transitive parser implementation.

The converter scans and parses every recognized formula while building the complete in-memory `WordDocument`. `convertToFile` calls `DocxWriter` only after that succeeds. Therefore a formula error creates no destination and leaves an existing destination byte-identical. Unmatched currency-like dollar text is not an error because it is not a recognized formula span.

### CLI option is route-scoped and fail-loud

`macdoc convert` accepts `--math literal|omath`, defaulting to `literal`. `--math omath` is valid only for Markdown or `.markdown` input with DOCX output. Invalid enum values and use on any other route fail argument validation before conversion and do not create or replace a destination.

The success path continues to write the normal one-line destination message to stderr. Formula errors are rendered through ArgumentParser's existing diagnostic path and do not write formula output to stdout.

## Implementation Contract

### Behavior

- Existing `MarkdownToWordConverter()` and CLI calls without `--math` preserve literal dollar text.
- `.omath` converts `$x^2$` to one inline `<m:oMath>` and converts a standalone `$$\frac{a}{b}$$` block to one `<m:oMathPara>` containing one `<m:oMath>`.
- `\$5`, inline/fenced code, autolinks, link destinations, and unmatched dollars remain non-math content.
- A recognized but unsupported expression, such as `$\overbrace{x}$`, fails the entire conversion without partial output.

### Interface and data shape

- Public library types: `MarkdownMathMode` and `MarkdownMathConversionError`.
- Public converter initializer: `MarkdownToWordConverter(mathMode:)`, with `.literal` default.
- CLI surface: `macdoc convert --to docx <input.md> --math literal|omath --output <path>`.
- Output remains a DOCX package; native math appears only in `word/document.xml` using the standard OMML namespace.

### Failure modes

- Invalid CLI mode or incompatible route: argument-validation failure, non-zero exit, empty stdout, destination unchanged.
- Matched unsupported or malformed formula: typed library error and non-zero CLI exit; source location is included; destination unchanged.
- Unmatched delimiter: preserved as literal text, not treated as a parser failure.
- Scanner placeholder collision: scanner selects another placeholder; caller input is never overwritten by a reserved literal.

### Acceptance criteria

- Package tests inspect generated XML for exact inline/display wrapper counts and no surviving formula delimiters.
- Boundary tables cover escaped dollar, currency-like text, code span, fenced code, link destination, unmatched delimiter, and malformed supported-span cases.
- Public API type-checks from a client target without `@testable` imports.
- Compiled CLI tests cover default literal, opt-in inline/display OMath, invalid route, invalid value, and existing-destination preservation on parser failure.
- ~~`swift test` passes in `packages/md-to-word-swift` and at the repository root, and Spectra validation has no Critical or Warning findings.~~
- Apply-time baseline qualification: a clean `origin/main` checkout executes 89 package tests with 42 pre-existing `E2ETests`/`RoundTripTests` failures. This change adds focused math coverage while retaining exactly those same 42 failures. Acceptance therefore requires every new and directly affected test to pass, the full package run to introduce zero failures beyond that documented clean baseline, the root suite to introduce no regression, and Spectra validation to have no Critical or Warning findings. Repairing the unrelated round-trip baseline is outside this change.

### Scope boundaries

In scope: Markdown-to-DOCX library and CLI behavior, parser dependency wiring, package/root tests, route documentation, and specs. Out of scope: parser macro expansion, OOXML math model changes, Pandoc parity, other output formats, downstream bestOCR changes, and formula styling beyond native default math formatting.

## Risks / Trade-offs

- [A custom scanner can drift from CommonMark edge cases] → Keep recognition conservative, use a single forward state machine, and lock exclusions with table-driven tests.
- [Placeholder text could collide with user content] → Generate a per-conversion marker and verify absence before substitution.
- [Parser and OOXML dependency versions can select incompatible `MathComponent` definitions] → Pin `latex-math-swift` from v0.2.0 and verify SwiftPM resolves one compatible `ooxml-swift` graph.
- [Raw OMML could be emitted under an undeclared prefix] → Test both streaming XML and archived `word/document.xml` with XML parsing and the standard math namespace.
- [Fail-loud behavior is stricter than literal fallback] → Make it opt-in only and preserve the literal default.

## Migration Plan

No caller migration is required because the default remains `.literal`. Release notes document the opt-in mode and supported subset. Rollback removes the CLI option and dependency while existing literal calls remain source-compatible.

## Open Questions

(none)
