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

### A conservative lexical tokenizer uses the original Markdown AST

An internal `MarkdownMathScanner` will produce a transformed Markdown string plus a token table. It replaces recognized math spans with collision-resistant placeholders before `swift-markdown` parses the document. This preserves surrounding emphasis, headings, lists, quotes, and tables while preventing the Markdown parser from interpreting LaTeX punctuation.

The converter first parses the original source with `swift-markdown` and converts source ranges into character offsets using the parser's UTF-8 line/column semantics. Text-node ranges define where inline math is eligible. When cmark normalizes visible text and reports a child range that does not cover its raw spelling, the scanner recovers only exact dollar-span signatures present in that normalized `Text`, matched from the suffix of the same plain-text paragraph. Normalized candidate pairing advances delimiter-to-delimiter rather than rescanning suffixes; the raw pairing pass skips backslash-escaped characters in one forward traversal, so odd or even backslash spellings cannot create repeated candidate openers. It never makes the whole paragraph or a metadata prefix eligible. A bounded raw pairing pass may mask an opening HTML spelling only when an original `InlineHTML` closing node anchors the same tag, the complete opening spelling satisfies the CommonMark tag-and-attribute grammar, and the recovered dollar text lies inside a quoted attribute. The pass advances monotonically to a discovered tag or physical-line boundary so malformed prefixes cannot trigger suffix rescans. Unpaired or grammatically invalid HTML-like text remains governed by its original `Text` range and stays math-eligible. Paragraph ranges whose descendants contain only plain text and line-break nodes define where display math is eligible. Code, HTML, autolink, destination, reference metadata, and formatting-container ranges are therefore opaque without making a free-standing raw angle heuristic override the CommonMark tree.

The scanner then performs a bounded linear replacement pass over source characters. Physical line/content ends are computed once when the cursor enters each line and reused by every delimiter on that line, including opaque code/HTML/destination delimiters. It recognizes:

- inline math: one unescaped `$`, non-whitespace first and last formula characters, no newline, and a valid closing `$`;
- display math: `$$...$$` occupying an entire logical paragraph, either on one trimmed line or with standalone opening and closing delimiter lines.

Unmatched dollars remain literal. Standalone unmatched display delimiters use one forward pending state only to reject a later visible delimiter in the same original paragraph/container; mixed-text delimiters never become pending, opaque code/HTML/destination delimiters are ignored, and a later independently complete display remains its own formula. A matched display token found alongside non-whitespace paragraph content or spanning more than one original eligible paragraph is rejected rather than silently converted inline. A token placeholder is generated only after a linear pre-index proves its numeric suffix is absent from caller input. The placeholder is wrapped in a private-use Unicode sentinel that cannot turn invalid HTML-like visible text into an HTML attribute, tag, autolink, or processing instruction when the transformed source is parsed again.

Alternatives rejected:

- A regular expression cannot reliably exclude code, escapes, or link destinations.
- Scanning only decoded `Text.string` values loses enough source spelling to distinguish escaped dollars; source ranges retain the raw spelling while the AST supplies eligibility.
- Reimplementing reference definitions, HTML blocks, nested destinations, and container identity as scanner states drifts from CommonMark and permits placeholders to reach metadata.
- Invoking Pandoc introduces a subprocess and a second conversion pipeline instead of using the maintained Swift parser.

### Tokens become native children with carrier-specific wrappers

Inline tokens are emitted as `Run.rawXML` containing one `<m:oMath>...</m:oMath>` fragment. In ordinary paragraph text, `Run.rawXML` is serialized verbatim as a direct paragraph child; inside a Markdown link label, it is serialized as a direct child of that paragraph's `<w:hyperlink>` carrier so the formula remains clickable. In neither case is OMath wrapped in an invalid `<w:r>` container.

Display tokens create a paragraph whose `unrecognizedChildren` contains one direct `<m:oMathPara><m:oMath>...</m:oMath></m:oMathPara>` child and no synthetic text run. Both wrappers use `MathComponent.toOMML()` for their interior. The streaming XML route adds the standard math namespace whenever generated body XML contains an `m:` element; the DOCX writer route uses the OOXML writer's namespace-aware document serializer.

Surrounding Markdown run properties do not alter OMML nodes in v1. A formula remains structurally positioned inside the surrounding paragraph, but bold or italic Markdown wrappers do not rewrite `m:rPr`.

### Original CommonMark ranges gate every token and placeholder

Inline delimiter pairs are accepted only when the entire raw span belongs to one original eligible `Text` node. Display delimiter pairs are accepted only when the entire raw span belongs to one original eligible `Paragraph` and the transformed paragraph contains no other visible content. Delimiters split by `Emphasis`, `Strong`, links, HTML, or another inline node remain literal.

After building the transformed CommonMark tree, the converter records placeholder consumption. Success requires a bijection between scanned tokens and allowed output carriers: each inline token appears exactly once in visible text processing, and each display token appears exactly once as the sole content of one paragraph. With no tokens, ordinary text bypasses placeholder lookup entirely. With tokens, inline recovery searches only the full private-use sentinel plus generated nonce prefix and bounds any closing-sentinel lookup by the longest generated placeholder; repeated public marker-prefix text therefore cannot trigger suffix searches. A placeholder in a relationship target, HTML node, reference metadata, or unconsumed location is an integrity failure before the DOCX writer is invoked.

Alternatives rejected:

- Validating only the transformed tree cannot recover original block boundaries after a scanner has collapsed them.
- Treating missing tokens as harmless would allow hidden HTML, destinations, or malformed metadata to suppress formulas or leak internal placeholders.

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
- `\$5`, inline/fenced code, HTML, autolinks, link/reference/image destinations, formatting-node-spanning delimiters, and unmatched dollars remain non-math content.
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
- Original range or placeholder-consumption mismatch: conversion fails before writing and never emits a generated placeholder or modifies an existing destination.

### Acceptance criteria

- Package tests inspect generated XML for exact inline/display wrapper counts and no surviving formula delimiters.
- Boundary tables cover escaped dollar, currency-like text, code span, fenced code, HTML blocks/tags, inline/reference/image destinations, formatting-node spans, unmatched delimiters, and malformed supported-span cases.
- Negative display tests cover blank-separated paragraphs, different list items, and blockquote/container changes; all fail before destination replacement.
- Relationship assertions cover multiline reference labels and angle-bracket destinations containing `)` and prove generated placeholders never enter targets.
- Public API type-checks from a client target without `@testable` imports.
- Compiled CLI tests cover default literal, opt-in inline/display OMath, invalid route, invalid value, and existing-destination preservation on parser failure.
- ~~`swift test` passes in `packages/md-to-word-swift` and at the repository root, and Spectra validation has no Critical or Warning findings.~~
- Apply-time baseline qualification: a clean `origin/main` checkout executes 89 package tests with 42 pre-existing `E2ETests`/`RoundTripTests` failures. This change adds focused math coverage while retaining exactly those same 42 failures. Acceptance therefore requires every new and directly affected test to pass, the full package run to introduce zero failures beyond that documented clean baseline, the root suite to introduce no regression, and Spectra validation to have no Critical or Warning findings. Repairing the unrelated round-trip baseline is outside this change.

### Scope boundaries

In scope: Markdown-to-DOCX library and CLI behavior, parser dependency wiring, package/root tests, route documentation, and specs. Out of scope: parser macro expansion, OOXML math model changes, Pandoc parity, other output formats, downstream bestOCR changes, and formula styling beyond native default math formatting.

## Risks / Trade-offs

- [A custom scanner can drift from CommonMark edge cases] → Use original CommonMark source ranges as the eligibility authority, keep replacement to bounded linear passes, and lock exclusions with table-driven tests.
- [Placeholder text could collide with user content] → Generate a per-conversion marker and verify absence before substitution.
- [Parser and OOXML dependency versions can select incompatible `MathComponent` definitions] → Pin `latex-math-swift` from v0.2.0 and verify SwiftPM resolves one compatible `ooxml-swift` graph.
- [Raw OMML could be emitted under an undeclared prefix] → Test both streaming XML and archived `word/document.xml` with XML parsing and the standard math namespace.
- [Fail-loud behavior is stricter than literal fallback] → Make it opt-in only and preserve the literal default.

## Migration Plan

No caller migration is required because the default remains `.literal`. Release notes document the opt-in mode and supported subset. Rollback removes the CLI option and dependency while existing literal calls remain source-compatible.

## Open Questions

(none)
