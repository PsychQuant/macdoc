## 1. Public mode and dependency contract

- [x] 1.1 Add RED package tests for **Markdown-to-Word exposes an opt-in native math mode** and **Public math mode is converter configuration with a literal default**: an ordinary `import MDToWord` client can construct `.omath`, while default and explicit `.literal` preserve `$x^2$`; verify the focused `MarkdownOMathConversionTests` first fails for missing public symbols rather than test syntax.
- [x] 1.2 Wire `latex-math-swift` v0.2.0 into `packages/md-to-word-swift/Package.swift`, add `MarkdownMathMode` and `MarkdownToWordConverter(mathMode:)`, and make the task 1.1 tests green while `swift package show-dependencies` proves one compatible `OOXMLSwift` resolution.

## 2. Conservative source tokenizer

- [x] 2.1 Add RED table-driven tests for **OMath mode recognizes conservative dollar delimiters** and **A conservative lexical tokenizer runs before the Markdown AST builder**, covering inline/display recognition, escaped dollars, currency-like text, unmatched delimiters, code spans, fenced code, autolinks, link/image destinations, mixed display content, and source locations; verify the focused scanner tests fail before implementation.
- [x] 2.2 Implement the single-pass `MarkdownMathScanner` with collision-checked placeholders and explicit lexical states so every task 2.1 boundary becomes green without changing `.literal` input; verify focused scanner tests and existing `MarkdownToWordConverterTests` pass.

## 3. Parser and native OMML carriers

- [x] 3.1 Add RED conversion tests for **Recognized formulas use the versioned LaTeX parser**, **Inline and display math use native Word carriers**, and **Tokens become direct paragraph children with carrier-specific wrappers**, asserting parser-subset fraction output, source-order `w:r/m:oMath/w:r`, display `m:oMathPara`, exact carrier counts, no delimiters, and valid `xmlns:m`; verify failures precede production emission changes.
- [x] 3.2 Connect scanned tokens to `LaTeXMathParser`, `MathComponent.toOMML()`, inline `Run.rawXML`, display `Paragraph.unrecognizedChildren`, and conditional streaming namespace emission; verify task 3.1 tests parse both streaming XML and archived `word/document.xml` successfully.

## 4. Stable errors and destination safety

- [x] 4.1 Add RED tests for **Formula failures occur before destination replacement** and **Recognized formula failures are stable, located, and pre-write**, covering unsupported and malformed expressions, one-based line/column, absent output, and an existing `KEEP` destination; verify focused tests fail for missing typed errors or unsafe behavior.
- [x] 4.2 Implement public `MarkdownMathConversionError` normalization and complete all scanning/parsing before `DocxWriter` is called, so unsupported/malformed/misplaced display errors are stable and both absent/existing destination assertions pass; verify task 4.1 tests are green and the full package run has exactly the clean `origin/main` baseline's 42 pre-existing `E2ETests`/`RoundTripTests` failures with zero new failures.

## 5. Route-scoped compiled CLI

- [x] 5.1 Add RED compiled-binary tests for **Compiled Markdown OMath route coverage** and **CLI option is route-scoped and fail-loud**, covering default literal, inline/display `--math omath`, explicit literal, invalid value, incompatible route, empty stdout on failure, and `KEEP` destination preservation; verify the focused CLI suite fails because the option is not implemented.
- [x] 5.2 Add the ArgumentParser `--math literal|omath` surface and Markdown-to-DOCX route validation in `Sources/MacDocCLI/MacDoc+Convert.swift`, then update `Package.resolved`; verify all task 5.1 compiled invocations pass and incompatible routes never call the converter.

## 6. User-facing boundary documentation

- [x] [P] 6.1 Fulfill **Documentation states the native math boundary** in `README.md`: show opt-in `--math omath`, literal default, supported parser-subset link, and explicit non-parity with full TeX/Pandoc; verify a content assertion finds all four claims.
- [x] [P] 6.2 Fulfill **Documentation states the native math boundary** in `CONVERSIONS.md`: annotate Markdown→Word native math mode and subset/non-goals without marking other routes as supported; verify the conversion matrix and notes contain the scoped command and no OMath claim on HTML/PDF routes.

## 7. Contract and regression verification

- [x] 7.1 Verify the design **Behavior**, **Interface and data shape**, **Failure modes**, **Acceptance criteria**, and **Scope boundaries** end to end: run focused scanner/converter/CLI tests, full `packages/md-to-word-swift` and root `swift test`, a non-`@testable` client build, dependency inspection, the repository's CRLF-aware `git -c core.whitespace=cr-at-eol diff --check`, `spectra analyze markdown-omath-conversion --json`, and `spectra validate markdown-omath-conversion`; every new/focused test passes, full runs introduce zero failures beyond the documented clean baseline, and the analyzer has no Critical or Warning findings. Plain `git diff --check` is not the gate for the pre-existing CRLF-formatted `Sources/MacDocCLI/MacDoc+Convert.swift`, because Git otherwise reports every newly added CRLF line as trailing whitespace.
- [x] 7.2 Close the first verification round's blockers with RED-then-GREEN regressions: archived OMath now declares `xmlns:m`; display math sharing a CommonMark logical paragraph fails before replacing the destination; multiline/container reference destinations and container/indented code remain literal without generated placeholders; dense 400-formula conversion is linear enough for the release regression budget. Final evidence: focused package 37/37, compiled CLI 8/8, root 53 total with 0 failures and 3 environment skips, package 121 total with only the documented 42 parent-baseline failures, release dense conversion 0.013 seconds, external non-`@testable` client build PASS, Spectra 0 Critical/Warning.
- [x] 7.3 Close the second verification round's blockers with RED-then-GREEN regressions: multiline inline-link and image destinations plus reference-definition titles remain literal; display placement is decided from the parsed CommonMark paragraph tree rather than adjacent physical lines; marker collision avoidance pre-indexes caller text once instead of rescanning it per token. Final evidence: focused package 38/38, compiled CLI 10/10, root 55 total with 0 failures and 3 environment skips, package 127 total with only the documented 42 parent-baseline failures, release 10,000-marker and 400-formula regressions both 0.004 seconds, external non-`@testable` type-check PASS, dependency graph resolves one OOXMLSwift 1.5.0 identity, both configured and ordinary diff checks PASS, and Spectra reports 0 Critical/Warning with 1 Suggestion.
