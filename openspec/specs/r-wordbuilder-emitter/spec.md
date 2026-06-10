# r-wordbuilder-emitter Specification

## Purpose

TBD - created by archiving change 'r-wordbuilder-emitter'. Update Purpose after archive.

## Requirements

### Requirement: r-wordbuilder is a standalone R package in its own GitHub repo

The `r-wordbuilder` R package SHALL be distributed as a top-level GitHub repository `PsychQuant/r-wordbuilder`, NOT as a subfolder of `macdoc` or any other repo. The repo root SHALL be a valid R package per the standard R package layout (containing `DESCRIPTION`, `NAMESPACE`, `R/`, `tests/`, `man/`).

This establishes the founding pattern for PsychQuant R packages. Future R packages in the org SHALL follow the same shape.

#### Scenario: Installable via devtools::install_github

- **GIVEN** a fresh R session with `devtools` installed
- **WHEN** the user runs `devtools::install_github("PsychQuant/r-wordbuilder")`
- **THEN** the package MUST install and load via `library(rwordbuilder)` without requiring the user to clone the macdoc Swift monorepo

#### Scenario: Repo root is the R package root

- **WHEN** R reads `DESCRIPTION` from the repo's top-level directory
- **THEN** the file MUST parse as a valid R package manifest with package name `rwordbuilder` (or equivalent — final spelling locked at apply time)
- **AND** `Rcmd check` MUST succeed on the repo root without `--as-cran` failures specific to package-root location

---
### Requirement: R API uses tidyverse-style pipeline with wb_ prefix

The R API SHALL expose document construction via a tidyverse-style `%>%` pipeline composed of constructor functions whose names start with the `wb_` prefix. The constructors SHALL take typed R values (strings, integers, structured types) and return an opaque document-state object that subsequent pipeline steps consume.

The pipeline SHALL terminate with `wb_export(state, path)` which writes the emitted Swift source to `path`.

#### Scenario: Minimum pipeline produces a Swift source file

- **GIVEN** the package is loaded
- **WHEN** the user runs:
  ```r
  wb_document() %>%
    wb_paragraph("Hello, World!") %>%
    wb_export("hello.swift")
  ```
- **THEN** the file `hello.swift` MUST be created at the working directory
- **AND** the file MUST contain `import WordBuilderSwift`
- **AND** the file MUST contain a string literal `"Hello, World!"` (post-escape-on-construction)
- **AND** the file MUST be syntactically valid Swift (passes `swift -parse hello.swift` when WordBuilderSwift is available)

##### Example: Minimum pipeline emit

- **GIVEN** the call above
- **WHEN** the emitted file is inspected
- **THEN** it MUST contain the literal lines `import Foundation` and `import WordBuilderSwift` near the top
- **AND** somewhere in the body it MUST contain `Paragraph(text: "Hello, World!")` OR an equivalent `WordEdit.applyInsertParagraph(...content: "Hello, World!")` call (depending on whether the empty-document seed path or insertParagraph path is used; both are conformant)

#### Scenario: Pipeline accepts both magrittr %>% and base R |>

- **WHEN** the user composes the pipeline with `%>%` (magrittr)
- **THEN** the output MUST be identical to the same pipeline expressed with `|>` (R 4.1+ native pipe)
- (Both pipe operators are evaluated as function-call composition; constructor return types are pipe-agnostic.)

---
### Requirement: Phase 1 step-type coverage matches docx-workflow-cli's shipped + pending split

The R API SHALL emit these step types as runtime-functional Swift code (each maps to a shipped `OOXMLEdit` Reducer case per ooxml-swift Phase 2c):

- `wb_paragraph(text, style)` → `OOXMLEdit.insertParagraph(after:, content:, styleId:)`
- `wb_remove_paragraph(anchor)` → `OOXMLEdit.removeParagraph(target:)`
- `wb_link(text, url, anchor)` → `OOXMLEdit.wrapWithHyperlink(target:, href:)`
- `wb_run_bold(text, anchor)` → `OOXMLEdit.setBold(target:, value: true)`

The R API SHALL accept these step types but emit Swift code wrapped in `try?` with an explanatory comment naming `ooxml-swift#71` (Phase 2c Reducer-pending):

- `wb_run_italic(text, anchor)`
- `wb_run_underline(text, anchor)`
- `wb_set_paragraph_style(anchor, style_id)`
- `wb_replace_text(find, replace)`
- `wb_image(path, anchor)`
- `wb_table(rows, columns, anchor)`
- `wb_cell(row, col, text, table_anchor)`
- `wb_equation(omml, anchor)`

#### Scenario: Runtime-functional step emits non-`try?` Edit call

- **GIVEN** a pipeline containing `wb_paragraph("Body text.")`
- **WHEN** the user runs `wb_export(path)`
- **THEN** the emitted Swift source MUST contain an `OOXMLEdit.insertParagraph(after: ..., content: "Body text.", styleId: ...)` call NOT wrapped in `try?`
- **AND** the call MUST be inside a `try ... lens.apply(...)` chain that propagates errors

#### Scenario: Pending step emits `try?`-wrapped Edit call with tracker comment

- **GIVEN** a pipeline containing `wb_image(path = "fig.png", anchor = wb_anchor(after_text = "Figure 1"))`
- **WHEN** the user runs `wb_export(path)`
- **THEN** the emitted Swift source MUST contain a `try?` wrap around the would-be `OOXMLEdit.insertImage(...)` call
- **AND** the source MUST contain a comment string `"ooxml-swift#71"` near the wrapped call

---
### Requirement: Typed escape-on-construction prevents Swift code injection from user data

All user-supplied string data (paragraph text, anchor strings, style IDs, URLs, etc.) SHALL pass through an internal `escape_swift_string()` helper before being composed into Swift source. The helper SHALL escape:

- Double-quote character `"` → `\"`
- Backslash character `\` → `\\`
- Newline `\n` → `\\n`
- Carriage return `\r` → `\\r`
- Tab `\t` → `\\t`
- ASCII control characters (0x00–0x1F, 0x7F) → Unicode escape sequence `\\u{<hex>}`
- Unicode line / paragraph separators (U+2028, U+2029) → Unicode escape sequence

The R API SHALL NOT contain any `paste0()` / `sprintf()` / `glue()` calls that interpolate user-supplied strings into Swift source code without passing through `escape_swift_string()` first. This is the security envelope that closes the HIGH-severity finding from closed PR #96.

#### Scenario: Quote in user input is escaped at construction

- **GIVEN** a pipeline with `wb_paragraph(text = 'She said "hello"')`
- **WHEN** the emitted Swift source is generated
- **THEN** the source MUST contain `"She said \\\"hello\\\""` (i.e., the inner quotes are backslash-escaped)
- **AND** the source MUST be syntactically valid Swift that, when compiled and run, produces a paragraph whose text content is `She said "hello"`

##### Example: Escape boundary

- **GIVEN** `text = 'A\\B"C'` (R string literal: A backslash B quote C)
- **WHEN** `escape_swift_string(text)` runs
- **THEN** the result MUST be the literal string `A\\\\B\\\"C` (R escapes that decode to: `A\\B\"C` in the emitted Swift file)
- **AND** when Swift parses `"A\\\\B\\\"C"` it MUST yield the original 5-character string `A\B"C`

#### Scenario: Injection attempt is neutralized

- **GIVEN** a malicious user-supplied string `'"); deleteAllFiles(); var x = ("'`
- **WHEN** the pipeline emits Swift source containing this as paragraph text
- **THEN** the emitted Swift MUST contain the value as ONE escaped string literal, not as executable Swift code
- **AND** compiling + running the emitted Swift MUST NOT result in `deleteAllFiles()` being called

---
### Requirement: wb_export writes a self-contained runnable Swift source file

The `wb_export(state, path)` function SHALL write a complete `.swift` source file at the user-specified `path`. The file SHALL be self-contained in the sense that, given access to the `WordBuilderSwift` Swift package (either via local `~/bin` install or SwiftPM dependency), the file SHALL be runnable as a script via `swift <path>` to produce a `.docx`.

The file SHALL begin with `import Foundation` and `import WordBuilderSwift` (in either order). The body SHALL construct or read a document, apply the pipeline's accumulated Edit sequence, and emit via `LensDocument.emit(to: url)` OR `DocxWriter.writeData(...).write(to: url)`.

#### Scenario: Emitted file passes Swift type-check

- **GIVEN** any valid R pipeline
- **WHEN** the user runs `wb_export(state, path)`
- **THEN** the emitted file MUST be syntactically valid Swift
- **AND** if `WordBuilderSwift` is installed in the user's Swift environment, the emitted file MUST type-check via `swift -typecheck <path>` (or equivalent)

#### Scenario: Emitted file produces a .docx when run

- **GIVEN** a pipeline that constructs a single-paragraph document and exports to `/tmp/script.swift`
- **WHEN** the user runs `swift /tmp/script.swift` (with WordBuilderSwift on PATH)
- **THEN** a `.docx` file MUST be created at the path specified in the pipeline's `output` step
- **AND** opening the `.docx` in Microsoft Word or Apple Pages MUST show the synthesized paragraph

---
### Requirement: Generated Swift source declares Layer 4 caller annotation

The emitted Swift source file SHALL contain a header comment block identifying it as generated by `r-wordbuilder` for ADR-009 Layer 4 framing. The comment SHALL include:

- Generator name: `r-wordbuilder`
- Generator version (from the R package's `DESCRIPTION` file)
- Reference to `WordBuilderSwift` v1.0.0+ as the consumed Layer 3 contract
- Reference to `PsychQuant/macdoc#99` ADR-009 as the architectural framing

#### Scenario: Header annotation is present

- **WHEN** any `wb_export()` call writes a Swift source file
- **THEN** the file MUST contain a comment line containing `r-wordbuilder` (the generator name)
- **AND** the file MUST contain a comment line referencing `ADR-009`
- **AND** the file MUST contain a comment line referencing `WordBuilderSwift`
