## Context

`ooxml-edit-isomorphism-foundation` ADR-009 (PsychQuant/macdoc#99, archived) frames `#88` as a **Layer 4 caller** to the foundation Edit-algebra runtime. R generates `.swift` source consuming `WordEdit` / `OOXMLEdit` cases, which the user runs via `swift run` to produce a `.docx`.

Foundation state as of 2026-06-01:
- `word-builder-swift v1.0.0` shipped (commit `eb8958a`, tag `v1.0.0`) — provides `LensDocument` + `@_exported import OOXMLSwift`.
- `ooxml-swift` Phase 2c Reducer cases shipped for 4 `OOXMLEdit` cases: `insertParagraph` / `insertParagraphBefore` / `setBold` / `wrapWithHyperlink` / `removeParagraph`. Other cases (`setItalic`, `setUnderline`, `setParagraphStyle`, `replace_text`, table-mutation, image-insertion, equation-insertion) are tracked under `ooxml-swift#71` follow-up.
- Phase 1 of the sister capability `docx-workflow-cli` (archived 2026-06-01) ships against the same Phase 2c runtime set. R-wordbuilder uses identical step-type coverage to keep the two Layer 3/4 front-ends in lockstep.

Stakeholders:
- R analysts producing publication-quality `.docx` reports from analysis pipelines (primary use case).
- The PsychQuant org (no existing R repos — this becomes the founding pattern for R packaging conventions in the org).
- Future R-emitter contributors who need a stable contract to write against.

Constraints:
- **Privacy** (CLAUDE.md global rule): generated Swift source SHALL contain no PII. Since the R code processes user data, escape-on-construction discipline catches the obvious accidental-leak surface, but the user remains responsible for not paste'ing real PII into anchor strings or paragraph text. (Not a spec-enforceable boundary; documented in the README's security section.)
- **Two-language toolchain**: R users must have Swift available to run the emitted source. Documented as a precondition. CRAN distribution is post-Phase-1.
- **Closed PR #96 review surfaced HIGH-severity finding** around free-form R→Swift string interpolation enabling code injection. The design SHALL force typed escape-on-construction (no `paste0()` of Swift source from user data).

## Goals / Non-Goals

### Goals

1. Provide a tidyverse-idiomatic R API (`%>%` pipeline of `wb_*` constructors) that emits well-formed Swift source consuming `LensDocument` + Edit cases.
2. Make injection impossible-by-construction: all user data goes through `escape_swift_string()` at the typed-literal-construction boundary. No `paste0()` of Swift code from user input.
3. Establish the founding pattern for PsychQuant R packages: separate repo, standard R package layout, `devtools::install_github` initial distribution.
4. Match Phase 1 step-type coverage of `docx-workflow-cli` (the sister Layer 3 front-end) so the two stay in lockstep.
5. Forward-compatible step-type registry: Phase 2c-pending cases emit `try?`-wrapped Swift code with `ooxml-swift#71` reference comments, matching the precedent set in word-builder-swift v1.0.0 `examples/` and `docx-workflow-cli`'s `EditPlanner`.

### Non-Goals

- R-only execution path (no `WordEdit` algebra reimplementation in R).
- `.docx` reader-side (emit-only in this capability).
- CRAN submission in Phase 1.
- Image / table / equation step types runtime-functional in Phase 1.
- Parallel Layer 4 Swift shim module.
- SwiftPM dependency management from R.

## Decisions

### Decision 1: Separate repo `github.com/PsychQuant/r-wordbuilder`, not a macdoc subfolder

`r-wordbuilder` ships as a top-level repo, not under `macdoc/r/`. R contributors clone just `r-wordbuilder` + install Swift toolchain; they don't need the macdoc Swift monorepo. CRAN-eventual distribution requires R-package root = repo root.

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| Subfolder `macdoc/r/wordbuilder/` | REJECTED — CRAN expects repo root = package root; subfolder breaks `devtools::install_github` semantics + couples R-pkg releases to macdoc submodule bumps |
| New top-level `PsychQuant/r-wordbuilder` repo | CHOSEN — founding pattern for PsychQuant R packages; decouples R contributors from Swift monorepo |
| Subfolder of another existing PsychQuant repo | REJECTED — no existing PsychQuant R repos; no natural home |

**Rationale**: founding-pattern decision. PsychQuant org currently has zero R repos. `r-wordbuilder` becomes the reference structure: standard R package layout, `devtools::install_github` initial distribution, CRAN later. Other future R packages follow the same shape.

### Decision 2: Emit `WordEdit` / `OOXMLEdit` cases DIRECTLY, not through a Swift shim module

R generates `.swift` source containing literal `WordEdit.applyBold(range: ...)` / `OOXMLEdit.insertParagraph(after: ..., content: ..., styleId: nil)` / `LensDocument(reading: ...).apply(...).emit(to: ...)` chains. The emitted file imports `WordBuilderSwift` (which re-exports OOXMLSwift) and compiles standalone.

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| Add a `RWordBuilderShim` Swift module to word-builder-swift with helper functions like `writeReportDocx(<args>)` | REJECTED — duplicates the Layer 3 surface and creates the same coexistence problem the v1.0.0 migration just dismantled; violates ADR-009 "no parallel algebra" rule |
| Emit through `LensDocument`'s 5-method surface directly | CHOSEN — the just-shipped LensDocument is the stable Layer 3 contract; Layer 4 callers consume it as-is |
| Generate raw `WordDocument` + `DocxWriter.writeData()` (skip LensDocument) | REJECTED — matches `docx-workflow-cli`'s runtime path but inconsistent with the Layer 4 framing (LensDocument is the documented public Swift API for authoring) |

**Rationale**: ADR-009 explicitly forbids parallel Layer 4 algebras. The Edit protocol + LensDocument IS the contract. R-wordbuilder writes against THAT, not a wrapper.

### Decision 3: Phase 1 step-type coverage mirrors `docx-workflow-cli`'s shipped + pending split

Same buckets as `docx-workflow-cli` (per its archived design.md Decision 5):

**Phase 1 runtime-functional** (Reducer cases shipped):
- `wb_paragraph(text, style = NULL)` → `OOXMLEdit.insertParagraph(after: ..., content: ..., styleId: ...)`
- `wb_remove_paragraph(anchor)` → `OOXMLEdit.removeParagraph(target: ...)`
- `wb_link(text, url, anchor)` → `OOXMLEdit.wrapWithHyperlink(target: ..., href: ...)`
- `wb_run_bold(text, anchor)` → `OOXMLEdit.setBold(target: ..., value: true)`

**Phase 1 spec-documented but Reducer-pending** (`try?`-wrapped at emit, tracker `ooxml-swift#71`):
- `wb_run_italic(text, anchor)` / `wb_run_underline(text, anchor)`
- `wb_set_paragraph_style(anchor, style_id)`
- `wb_replace_text(find, replace)`
- `wb_image(path, anchor)` / `wb_table(rows, columns, anchor)` / `wb_cell(row, col, text, table_anchor)` / `wb_equation(omml, anchor)`

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| Ship only `insert_paragraph` + `set_bold` (smallest viable subset) | REJECTED — forces later expansion churn; users hit "this step isn't supported" friction quickly |
| Ship full step-type catalog including non-functional ones with no `try?` wrapping | REJECTED — generated Swift code wouldn't compile / would throw at runtime in confusing ways |
| Mirror `docx-workflow-cli`'s functional + pending split | CHOSEN — lockstep with sister Layer 3 capability; same Reducer-gap handling pattern |

**Rationale**: lockstep with `docx-workflow-cli` keeps the documentation + user-facing step type list consistent across the two Layer 3/4 front-ends. Same Phase 2c Reducer gaps surface the same way (warn-and-skip OR `try?`-wrap).

### Decision 4: Typed escape-on-construction (no `paste0()` of Swift code from user data)

All step constructors take typed R values (strings, integers, structured `wb_anchor()` etc.). The internal `escape_swift_string(s)` helper produces Swift-literal-safe escapes for `"`, `\`, newlines, Unicode control chars, etc. ALL user data flows through this helper at the Swift-literal-construction boundary. No `paste0("WordEdit.applyInsertParagraph(content: \\\"", user_data, "\\\")")` pattern anywhere in the codebase.

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| Best-effort `paste0()` + manual escaping in each constructor | REJECTED — the closed PR #96 HIGH-finding pattern; brittle, error-prone, easy to drift |
| Centralized `escape_swift_string()` helper + typed constructors | CHOSEN — one chokepoint, audit-friendly, security tests cover the helper |
| Generate Swift via a real AST builder library | REJECTED — no R-side Swift AST library exists; building one is out of scope |
| Generate Swift via templating engine (e.g. `glue` or `whisker`) | REJECTED — templates accept raw strings; same injection surface unless escape is enforced inside |

**Rationale**: closed PR #96 review surfaced this exact failure mode (HIGH severity). The escape envelope at typed-literal construction is the fix. R-side security tests in `tests/testthat/test-escape.R` cover quote/backslash/newline/Unicode edge cases.

### Decision 5: Tidyverse `%>%` pipeline API + `wb_*` naming convention

```r
wb_document() %>%
  wb_paragraph("Q1 Report", style = "Heading1") %>%
  wb_paragraph("Revenue grew 15%.") %>%
  wb_paragraph("Cost held flat.") %>%
  wb_export("scripts/render-report.swift")
```

The `wb_export()` step writes the Swift source file. User then runs it via `swift run` (or compiles via SwiftPM) to produce the `.docx`.

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| One-shot `r_to_docx(<args>)` function | REJECTED — loses the inspectable intermediate Swift source; user can't audit what gets compiled |
| R6-class-based OOP (`doc <- Document$new(); doc$add_paragraph(...)`) | REJECTED — R6 OOP loses pipe ergonomics that R users prefer for analysis workflows |
| Tidyverse `%>%` pipeline with `wb_*` prefix | CHOSEN — R-idiomatic; matches tidyverse conventions; pipeable into existing analysis chains |
| `|>` native pipe (R 4.1+ only) | DEFER — accept both `%>%` and `|>` semantically (they're equivalent for our constructors); examples + docs use `%>%` for R-3.5+ compat |

**Rationale**: tidyverse pipe is the dominant R API idiom. Pipeline composition reads top-to-bottom as "document construction recipe". `wb_*` prefix maps to the package name (`r-wordbuilder`). Two-phase `R → .swift → .docx` flow lets users inspect the emitted Swift before running — supports "replicability + auditability" from the original #88 body.

### Decision 6: `wb_export()` writes a SELF-CONTAINED `.swift` source file

The emitted file:
- Starts with `import WordBuilderSwift`
- Reads the baseline `.docx` (if `wb_document(baseline = ...)` was called) via `LensDocument(reading: ...)`
- For empty-document case (`wb_document()` with no baseline), creates a fresh `WordDocument` + uses `appendParagraph` to seed initial content (per word-builder-swift v1.0.0 examples), then round-trips through a temp file into a `LensDocument`
- Applies each step's Edit case (functional via `lens.apply(edit)`, pending via `try? lens.apply(edit)` with a comment naming `ooxml-swift#71`)
- Emits via `lens.emit(to: outputURL)` to the user-specified output path

The file is standalone — user runs it via `swift -I <path-to-WordBuilderSwift-module>` OR includes it in a SwiftPM project alongside `WordBuilderSwift` dependency. Documentation explains both paths in the R package README.

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| Emit a `Package.swift` snippet alongside the source so user can `swift run` directly | DEFER — useful for the SwiftPM-friendly path; out of Phase 1 scope |
| Just emit a `WordEdit` script body (caller wraps in their own scaffolding) | REJECTED — too much friction; user has to know the import + Edit chain shape |
| Emit ready-to-`swift run` source | CHOSEN — minimal friction, matches the spec.md scenario for "Layer 4 consumer" |

**Rationale**: friction-minimization. The R user is an analyst, not a Swift developer; they should be able to run the emitted source with a single command after `wb_export()`.

## Risks / Trade-offs

- **R user has to install Swift toolchain**: documented as precondition. Mitigation: README's "Installation" section walks through `xcode-select --install` / `apt install swift` / etc. + the homebrew tap for `swift` on Linux. Not spec-enforceable.
- **R-Swift type marshaling**: passing rich R types (data.frames, lists) into typed Swift literals requires careful escape + structure preservation. Mitigation: Phase 1 sticks to scalar / string / integer types; structured types (e.g., table cells from a data.frame) deferred to a future Phase or `wb_table_from_dataframe()` helper.
- **Generated Swift compilation errors**: if R-emitter has a bug, the emitted Swift may fail to compile. Mitigation: `tests/testthat/test-emit.R` golden tests assert emitted source against committed Swift snippets that ARE known-to-compile; `tests/testthat/test-roundtrip.R` runs `swift -typecheck` on emitted source.
- **NoteCore-style format drift**: `WordEdit` enum cases evolve. If R-emitter targets a case signature that changes upstream, generated Swift stops compiling. Mitigation: pin `WordBuilderSwift` version in the README's "Compatibility" section; CI rebuilds against latest main monthly.
- **Closed PR #96 baggage**: the prior attempt had unresolved security findings. Mitigation: this design EXPLICITLY closes the injection class via Decision 4 (typed escape-on-construction); spec.md has dedicated Requirements for the security envelope; tests assert no user data reaches `paste0()` of Swift code.

## Migration Plan

No data migration. New repo + new R package — additive. word-builder-swift v1.0.0 hard dep shipped today.

Phased shipping:
1. **Phase 1** (this Spectra change apply): repo bootstrap + R package with the 4 runtime-functional step types + `try?`-wrapped pending cases + security tests + emit golden tests + roundtrip integration test.
2. **Phase 2** (separate Spectra change after ooxml-swift#71 Reducer cases land): activate pending step types; remove `try?` wrapping.
3. **Phase 3** (separate Spectra change): CRAN submission, `wb_table_from_dataframe()` helper, `Package.swift` snippet emission alongside source.

## Open Questions

(None — discuss-stage locked all 5 decisions; design covers the 6 architectural choices that follow.)
