## Why

R is the dominant language for statistical analysis but cannot natively produce well-styled `.docx` reports. Today, R users producing publication-quality Word documents from analysis pipelines either: (a) call out to `officer` (heavyweight, R-specific implementation that doesn't share semantics with the rest of the macdoc OOXML toolchain), or (b) export to LaTeX and round-trip through `pandoc`. Both paths produce documents whose authoring contract diverges from the macdoc ecosystem's `OOXMLEdit` / `WordEdit` algebra.

Per `ooxml-edit-isomorphism-foundation` ADR-009 (PsychQuant/macdoc#99), `#88` is a **Layer 4 caller** — R generates `.swift` source that uses `WordEdit` / `OOXMLEdit` cases from the foundation's shipped Edit-algebra runtime. With word-builder-swift v1.0.0 lens-model migration shipped (2026-06-01, commit `eb8958a`), the ergonomic adapter layer (`LensDocument` + `@_exported import OOXMLSwift`) is stable and ready for Layer 4 emitters to consume.

The prior PR #96 attempt at this work was **closed without merging** on 2026-05-25 with HIGH-severity security findings around free-form R→Swift string interpolation that could enable code injection. This proposal authors a fresh design on top of the now-shipped foundation, with typed escape-on-construction discipline that closes the injection-class bugs identified in PR #96 review.

The change also establishes the **founding pattern** for PsychQuant R packages — the org currently has zero R repos. `r-wordbuilder` becomes the reference for how future R packages in this org structure their dependency on Swift toolchain components.

## What Changes

- **NEW capability `r-wordbuilder-emitter`**: declarative R API surface (`wb_document() %>% wb_paragraph(...) %>% wb_export()`) that generates Swift source code consuming `WordBuilderSwift` v1.0.0's lens-model API. Defines the manifest of Phase 1 step types, the typed escape-on-construction safety model, and the two-phase `R → .swift → swift run → .docx` execution flow.
- **NEW separate repo `github.com/PsychQuant/r-wordbuilder`**: R package with standard layout (`DESCRIPTION`, `NAMESPACE`, `R/`, `tests/testthat/`, `man/`, plus a `Swift/` helper directory for any generated-source examples). NOT a subfolder of macdoc — preserves CRAN-eventual distribution path + decouples R contributors from the Swift monorepo.
- **MODIFIED capability `word-builder-swift`** (light touch): add a reference scenario showing how a Layer 4 caller (e.g., the R emitter) consumes `LensDocument` + Edit cases. No API surface change; no requirement removal.
- The emitted Swift source SHALL produce a runnable `.swift` file that imports `WordBuilderSwift` and uses `LensDocument` + `WordEdit` / `OOXMLEdit` cases directly. No parallel `RWordBuilderShim` Swift module is added (per ADR-009 Layer 4 framing).

## Non-Goals

- **No CRAN submission in Phase 1.** The R package ships as `devtools::install_github("PsychQuant/r-wordbuilder")` first; CRAN submission is a later Phase once the API has stabilized.
- **No standalone R-only mode** that bypasses Swift compilation. Generated `.swift` source is the authoritative artifact; running it via `swift run` produces the `.docx`. An R-internal-only path would require reimplementing the `WordEdit` algebra in R — defeats the purpose of Layer 4 framing.
- **No image / table / equation / hyperlink step types in Phase 1 runtime-functional set.** Same Phase 2c Reducer-pending set as `docx-workflow-cli` (see ooxml-swift#71). Pending step types are emitted as Swift code wrapped in `try?` with explanatory comments naming the tracker, matching the v1.0.0 examples + the `docx-workflow-cli` precedent.
- **No `.docx` reader-side** (parsing existing docs from R). This change is emit-only. Reading is a future capability.
- **No string-interpolation API.** All step constructors take typed R values (string, integer, structured types like `wb_anchor()`); typed-to-Swift-literal escape happens at one centralized helper. Free-form `paste0("...", x, "...")` of Swift code is the HIGH finding from PR #96 — explicitly forbidden by the spec.
- **No magrittr backport** for R < 4.1. The `%>%` operator is treated as part of the R API contract; users on older R versions install `magrittr` directly. (R 4.1+ ships `|>` natively; `%>%` works on R 3.5+ via magrittr.)
- **No SwiftPM dependency management** from R. The generated Swift source carries its own `Package.swift` snippet OR assumes `WordBuilderSwift` is already on the user's `~/bin` / `swift package` resolved deps. R doesn't manage Swift toolchain.

## Capabilities

### New Capabilities

- `r-wordbuilder-emitter`: R API + Swift-source emission contract + escape rules + Phase 1 step-type mapping.

### Modified Capabilities

- `word-builder-swift`: add a Layer 4 consumer reference scenario (R-emitter is the canonical Layer 4 caller).

## Impact

- Affected specs:
  - NEW: `openspec/specs/r-wordbuilder-emitter/spec.md`
  - MODIFIED: `openspec/specs/word-builder-swift/spec.md` (add one reference scenario for Layer 4 consumer pattern)
- Affected code:
  - NEW (in a separate repo `github.com/PsychQuant/r-wordbuilder`):
    - `DESCRIPTION` — R package metadata
    - `NAMESPACE` — exported symbols
    - `R/document.R` — `wb_document()` constructor + state struct
    - `R/paragraph.R` — `wb_paragraph()` / `wb_run_bold()` / inline formatting builders
    - `R/anchor.R` — `wb_anchor()` typed-anchor constructors (`before_text`, `after_text`, `paragraph_index`)
    - `R/edit_planner.R` — R-side equivalent of Phase 1 step-type registry; produces `WordEdit` / `OOXMLEdit` Swift expressions
    - `R/escape.R` — `escape_swift_string()` + typed literal helpers (the security envelope)
    - `R/export.R` — `wb_export()` writes the Swift source to a target path
    - `tests/testthat/test-escape.R` — security tests for `escape_swift_string()` (quote/backslash/Unicode/newline)
    - `tests/testthat/test-emit.R` — golden-file tests for emitted Swift source per step type
    - `tests/testthat/test-roundtrip.R` — integration test that runs `swift run` on emitted source against a fixture and checks `.docx` output
    - `man/` — generated docs via `roxygen2`
  - NEW (in macdoc repo):
    - `openspec/specs/r-wordbuilder-emitter/spec.md`
  - Modified (in macdoc repo):
    - `openspec/specs/word-builder-swift/spec.md` (add Layer 4 reference scenario)
  - Removed: (none — `r-wordbuilder` package is new; macdoc has no R code to remove)
