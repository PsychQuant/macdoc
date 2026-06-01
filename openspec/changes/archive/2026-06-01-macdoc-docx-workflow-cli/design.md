## Context

word-builder-swift v1.0.0 lens-model migration shipped on 2026-06-01 (commit eb8958a in PsychQuant/word-builder-swift). Its surface (`LensDocument` + `@_exported import OOXMLSwift`) is the Layer 3 ergonomic adapter for the foundation Edit-algebra runtime (`ooxml-edit-isomorphism-foundation`). Phase 2c Reducer cases functional today: 5 `OOXMLEdit` (`setBold` / `setItalic` / `setUnderline` / `setParagraphStyle` / `insertParagraph` / `removeParagraph` / `applyLink`) + 3 `WordEdit` (`applyBold` / `applyItalic` / `applyUnderline` / `wrapWithHyperlink`). Table-mutation cases tracked under ooxml-swift#71 follow-up.

`MacDocCLI` already has 5 subcommands (`Convert`, `PDF`, `Bib`, `Config`, `OCR`) following the ArgumentParser pattern. `MacDoc+PDF.swift` shows the multi-step-pipeline shape (`ocr` / `chapters` / `consolidate` etc.) — that pattern matches what `Docx` subcommand needs (`apply` / `plan` / `verify` / `diff`).

Stakeholders:
- Authors of project repos that want replicable docx-edit pipelines checked into `scripts/edit/manifest.json` (the primary use case in #92).
- `che-word-mcp` maintainers who want declarative E2E test coverage that supplements the existing `RealWorldDocxRoundTripSmokeTests` (use case 4 in #92).
- Future Layer 4 callers (R package per #88, others) that may generate manifests as their output format.

Constraints:
- `Date.now()` / `Math.random()` / `argless new Date()` not available in this codebase (per the patterns used in word-builder-swift v1.0.0 examples — UUID-based temp path naming instead).
- Phase 2c Reducer gap means a subset of plausible step types (`insert_table`, `insert_image`, `insert_equation`, `set_cell_text`) have no runtime support today. Spec must document the gap honestly, executor must wrap pending steps in `try?` with explanatory comments (precedent: `examples/03-table-3x3.swift` in word-builder-swift v1.0.0).

## Goals / Non-Goals

### Goals

1. Ship a declarative manifest-driven docx-edit CLI on top of word-builder-swift v1.0.0, with deterministic anchor resolution that makes manifests replayable across docx baselines without runtime drift.
2. Provide `DocxWorkflowLib` Swift package as the library boundary, so che-word-mcp integration tests (and any future Swift consumer) can import the executor + verifier programmatically.
3. Lock the Phase 1 manifest schema as `Codable`-decodable JSON; YAML deferred until real usage proves the dep cost is worth paying.
4. Document Phase 2c Reducer-pending step types in the spec (call shape + tracker reference) so the manifest schema is forward-compatible; runtime wraps these in `try?`.
5. Wire `Docx` as a `MacDocCLI` subcommand cluster (`macdoc docx apply / plan / verify / diff`), not a standalone binary — preserves one-binary-many-subcommands invariant.

### Non-Goals

- Standalone `dxedit` binary (a future change can extract).
- YAML manifest support (deferred).
- Table / image / equation runtime support (deferred to Phase 2c Reducer landings).
- `archive-first` auto-snapshot integration (deferred to Phase 3).
- `che-word-mcp` MCP transport changes (separate Spectra per ADR-009).
- Spec-driven replacement of `LensDocument`'s existing 5-method surface (out of scope; `DocxWorkflowLib` consumes the surface as-is).

## Decisions

### Decision 1: Integrated `macdoc docx` subcommand, not standalone `dxedit` binary

`Docx` ships as a `MacDocCLI` subcommand with 4 inner subcommands (`apply` / `plan` / `verify` / `diff`). Mirrors `MacDoc+PDF.swift`'s shape. The CLI target stays thin: argparse parsing + `DocxWorkflowLib` call + result printing.

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| Standalone `dxedit` binary in a new `Sources/dxedit/main.swift` executableTarget | REJECTED — duplicates install/marketplace surface; macdoc already owns "one CLI for document workflows"; no use case demands a separate binary in Phase 1 |
| Subcommand under `Convert` (`macdoc convert --to docx <manifest.json>`) | REJECTED — Convert's `--to <format>` model is single-input-single-output by format-pair; manifest-driven editing is fundamentally different (multi-step, in-place against baseline) |
| **Top-level subcommand `Docx` peer to `Convert` / `PDF` / `Bib` / `Config` / `OCR`** | **CHOSEN** — matches established subcommand pattern; PDF's multi-step pipeline (`pdf ocr / chapters / consolidate`) is the closest precedent |

**Rationale**: Adding a top-level subcommand has zero new distribution cost. Standalone binary requires its own marketplace plugin, `~/bin` install path, and breaks the user mental model. Extractable later via Spectra change if a CLI-toolkit family emerges.

### Decision 2: JSON-Codable manifest in Phase 1, YAML deferred

Manifest schema is decoded via `JSONDecoder` from a JSON document. Manifest root type is a Swift `struct Manifest: Codable`. UTF-8 byte-encoded JSON handles CJK anchor text natively (the historical YAML-for-CJK argument is moot once tooling preserves UTF-8).

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| YAML first via `Yams` | REJECTED — adds external dep before usage justifies it; the CJK argument is empirically resolved by UTF-8 JSON |
| **JSON-Codable first; YAML adapter deferred** | **CHOSEN** — Swift's native `Codable` gives zero-cost decoding; reversible if YAML proves ergonomically necessary |
| TOML or custom DSL | REJECTED — no existing usage data; speculative |

**Rationale**: Foundation-stable + reversible. A future change can add a YAML adapter that decodes via `Yams` into the same `Manifest` struct without breaking JSON consumers.

### Decision 3: New `DocxWorkflowLib` Swift package; MacDocCLI Docx subcommand stays thin

Library lives in `packages/docx-workflow-swift/` (sibling-clone style — gitignored at root, has own GitHub remote, follows the `packages/` convention). `MacDocCLI` declares it as a dependency via `path:` (development) or `url:` (release). The `Docx` subcommand file (`Sources/MacDocCLI/MacDoc+Docx.swift`) contains ~100 lines of ArgumentParser wiring + `DocxWorkflowLib` calls; no business logic.

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| Put executor logic directly under `Sources/MacDocCLI/DocxWorkflow*.swift` | REJECTED — couples library to CLI target; che-word-mcp tests can't `import DocxWorkflowLib` to drive declarative assertions |
| Put executor under `mcp/che-word-mcp/Sources/` | REJECTED — wrong direction; che-word-mcp is a *consumer* of the library, not its owner |
| **New `packages/docx-workflow-swift/` package with `DocxWorkflowLib` library target** | **CHOSEN** — matches existing `packages/` convention; importable by any Swift consumer |

**Rationale**: Library boundary is non-negotiable for the integration-test use case. Package placement under `packages/` matches the established pattern (word-builder-swift, ooxml-swift, etc.).

### Decision 4: Anchor model — text-based with multi-match = FAIL, zero-match = FAIL

Each step's `anchor` field is one of `before_text` / `after_text` / `paragraph_index`. Text anchors resolve via exact-substring search across paragraph text. Resolution semantics:

- **Exact-zero matches** → executor fails with `AnchorError.notFound(anchor: ..., step: ..., scanned: <paragraph count>)`.
- **Exact-one match** → resolution succeeds, executor proceeds.
- **Multiple matches** → executor fails with `AnchorError.ambiguous(anchor: ..., step: ..., matches: <list of paragraph indices>)`. User must disambiguate by lengthening the anchor substring.

No first-match-wins fallback. The "replicable pipelines" use case demands deterministic resolution; first-match-wins changes behavior silently as the source docx evolves.

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| First-match-wins | REJECTED — silently changes behavior across docx versions, breaks replicability |
| Multi-match = succeed-on-all | REJECTED — semantics of "insert before all matches" are step-type-specific (some steps make sense, some don't); breaks one-step-one-effect mental model |
| **Multi-match = FAIL; zero-match = FAIL; exact-one = succeed** | **CHOSEN** — deterministic, explicit error surface, user controls disambiguation |
| Regex-based anchors | REJECTED in Phase 1 — incremental scope; deferred to future Phase if needed |
| XPath / structural anchors (paragraph by Heading style + index within section) | REJECTED in Phase 1 — more complex than current foundation surface justifies; deferred |

**Rationale**: Determinism over flexibility. Errors are explicit. User disambiguates by lengthening anchor substring (no schema change needed). Regex / XPath are future Phases.

### Decision 5: Phase 1 step type coverage = runtime-functional + spec-documented `try?` gap

Spec lists the full intended step-type catalog. Executor implements runtime-functional cases against shipped Reducer cases; pending cases compile but wrap their Edit construction in `try?` with a comment naming the tracker.

**Phase 1 runtime-functional step types**:

| Step type | Compiles to (Edit case) | Reducer status |
|---|---|---|
| `replace_text` | `WordEdit.applyReplaceText(range:, with:)` *(if exists; else `OOXMLEdit.removeRun` + `OOXMLEdit.insertRun` composite)* | Phase 2c |
| `insert_paragraph` | `WordEdit.applyInsertParagraph(after:, content:)` | Phase 2c ✓ |
| `set_paragraph_style` | `OOXMLEdit.setParagraphStyle(target:, styleId:)` | Phase 2c ✓ |
| `wrap_link` | `WordEdit.wrapWithHyperlink(range:, url:)` | Phase 2c ✓ |
| `set_bold` / `set_italic` / `set_underline` | `WordEdit.applyBold/applyItalic/applyUnderline` | Phase 2c ✓ |
| `remove_paragraph` | `OOXMLEdit.removeParagraph(target:)` | Phase 2c ✓ |

**Phase 1 spec-documented but `try?`-wrapped step types** (tracker: ooxml-swift#71 follow-up):

| Step type | Intended Edit case | Status |
|---|---|---|
| `insert_image` | `OOXMLEdit.insertImage(at:, data:, dimensions:)` *(case TBD by Reducer landing)* | pending |
| `insert_table` | `OOXMLEdit.insertTable(at:, rows:, columns:)` | pending |
| `set_cell_text` | `OOXMLEdit.setCellText(at:, row:, col:, text:)` | pending |
| `insert_equation` | `OOXMLEdit.insertEquation(at:, omml:)` *(case TBD)* | pending |

Pending steps emit a warning at executor time: `"warn: step type 'insert_image' has no Reducer support yet (pending ooxml-swift#71); skipping"`. The exit code stays 0 — Phase 1 contract is "execute what's runnable, surface what's not".

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| Refuse to compile manifests containing pending step types | REJECTED — too brittle; users authoring manifests for "current Phase 2c + future Phase 2c additions" would see false failures |
| Silently skip pending steps | REJECTED — silent degradation breaks replicability assumptions |
| **`try?` pending steps with explicit warning** | **CHOSEN** — matches word-builder-swift v1.0.0 example precedent; honest about gaps |
| Refuse manifests with any pending step + flag for "lenient mode" | REJECTED — adds CLI flag noise for Phase 1 |

**Rationale**: Honest gap documentation; user always knows what was applied vs skipped. Failure exit code reserved for hard errors (anchor mismatch, manifest decode failure, foundation runtime error from a runtime-functional step).

### Decision 6: Verify post-condition catalog

`verify` step block in manifest supports the following post-conditions in Phase 1:

- `expected_images: <int>` — count `<a:blip>` references after apply
- `expected_paragraphs_min: <int>` — minimum paragraph count
- `expected_bookmarks_min: <int>` — minimum bookmark count
- `libxml2_valid: <bool>` — load output through `libxml2` parser, assert no errors (uses macOS Foundation `XMLParser` initially; native libxml2 binding deferred)
- `byte_preserved_parts: [<part-pattern>]` — assert byte-equality (post-c14n) on listed `.xml` parts of the OOXML container (e.g., `word/header*.xml`, `word/footer*.xml`, `word/theme/*.xml`)

`byte_preserved_parts` is the most important verify mode because it's exactly the "I changed body, prove nothing else changed" invariant.

Out of scope for Phase 1 verify modes (deferred):

- `assert_text_present` / `assert_text_absent` (string-level body assertions — niceish but Phase 1's executor already gives observability)
- Custom predicate hooks (Swift closure registration — over-engineering)
- Cross-baseline diff verification (handled by separate `diff` subcommand)

## Risks / Trade-offs

- **Reducer-pending step types may shift call shapes**: the spec documents intended call shape, but if ooxml-swift#71 lands with a different signature, the spec needs amendment + executor needs revision. Mitigation: cite the tracker explicitly; treat the call shape as informative-only for pending steps; bind the manifest schema to a stable JSON shape (independent of Swift signature evolution).
- **Anchor strictness may surprise users**: multi-match = FAIL is a quality choice but may produce errors in manifests authored against slightly-changed baselines. Mitigation: error message includes the matched paragraph indices + first-line preview, so user can disambiguate quickly.
- **`libxml2_valid` via Foundation `XMLParser`**: macOS Foundation's parser is more permissive than `xmllint`. Risk: docx files that pass Foundation parsing but fail strict libxml2 validation. Mitigation: Phase 1 uses Foundation; Phase 2 can swap to a native libxml2 binding when there's evidence Foundation misses real cases.
- **Spec authoring drift from foundation**: if foundation's Edit-algebra spec (ooxml-edit-algebra-runtime) evolves, this spec must track. Mitigation: spec's normative requirements cite the foundation capability + use SHALL/MUST language only where this capability adds new contracts, not where it restates foundation contracts.
- **Phase 2c Reducer landing reshuffles step type registry**: when table-mutation cases land, the manifest schema may want to expose richer table-step options. Mitigation: spec scopes step types as enum-tagged Codable; additions are backward-compatible JSON additions.

## Migration Plan

No data migration. New package + new subcommand are additive. Word-builder-swift v1.0.0 is a hard dep, but it shipped today so no version-gating concerns.

Phased shipping:

1. Phase 1 (this Spectra change apply): `DocxWorkflowLib` package + `Docx` subcommand + spec + runtime-functional step types + `verify` Phase 1 modes.
2. Phase 2 (separate Spectra change after ooxml-swift#71 lands): activate pending step types; remove `try?` wrapping.
3. Phase 3 (separate Spectra change): YAML adapter, `archive-first` integration, richer verify modes.

## Open Questions

(none — discuss-stage locked all 5 decisions; design covers the 6 architectural choices that follow.)
