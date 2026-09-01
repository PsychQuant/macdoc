## Why

The Markdown-to-DOCX route currently serializes `$...$` and `$$...$$` as literal Word text, so academic Markdown loses native equation semantics. The repository already has a versioned LaTeX-subset parser and OMML emitters; this change connects them through an explicit, backward-compatible conversion mode.

## What Changes

- Add a public `MDToWord` math mode whose default preserves the current literal behavior and whose opt-in OMath mode converts supported inline and display LaTeX delimiters to native Word OMML.
- Add a delimiter scanner that excludes escaped dollar signs, inline code, fenced code, and formulas crossing Markdown formatting-node boundaries.
- Derive formula-eligible source ranges from the original CommonMark tree before substitution, so block/container boundaries, HTML regions, code, destinations, reference metadata, and formatting-node splits cannot be erased by placeholders.
- Require every generated placeholder to be consumed exactly once by an allowed visible text or display carrier before conversion can succeed.
- Reuse `LaTeXMathParser` from `latex-math-swift`; unsupported or malformed formulas fail loudly before any destination DOCX is replaced.
- Add `macdoc convert --to docx ... --math literal|omath`, with route validation that rejects the option on incompatible source/target pairs.
- Expand package-level and compiled-CLI acceptance coverage to inspect `word/document.xml`, distinguish inline from display carriers, and prove failure leaves an existing destination unchanged.
- Document the supported LaTeX subset and the intentional gap from complete TeX or Pandoc texmath compatibility.

## Non-Goals

- Implementing a second LaTeX parser inside macdoc or `md-to-word-swift`.
- Claiming complete TeX, MathJax, KaTeX, or Pandoc texmath compatibility.
- Converting math embedded in code spans, fenced code, URLs, image destinations, or delimiters split across separate Markdown AST text nodes.
- Changing the default output of existing `MarkdownToWordConverter()` or `macdoc convert --to docx` calls.
- Adding OMath support to non-DOCX conversion routes.

## Capabilities

### New Capabilities

- `markdown-omath-conversion`: Public Markdown-to-DOCX math-mode semantics, delimiter recognition, OMML carrier rules, fail-loud behavior, and package-level acceptance.

### Modified Capabilities

- `e2e-conversion-routes`: Add compiled CLI coverage for the `--math` flag, native OMML output, route validation, and destination-preserving failures.

## Impact

- Affected specs: `markdown-omath-conversion`, `e2e-conversion-routes`
- Affected code:
  - New:
    - `packages/md-to-word-swift/Sources/MDToWord/MarkdownMathScanner.swift`
    - `packages/md-to-word-swift/Tests/MDToWordTests/MarkdownOMathConversionTests.swift`
    - `Tests/MacDocCLITests/MarkdownOMathRouteTests.swift`
  - Modified:
    - `packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift`
    - `packages/md-to-word-swift/Package.swift`
    - `Sources/MacDocCLI/MacDoc+Convert.swift`
    - `Package.resolved`
    - `README.md`
    - `CONVERSIONS.md`
  - Removed: (none)
