## Why

`mdocx-grammar` (archived `2026-05-06-mdocx-syntax`) pins 15 normative Requirements in `openspec/specs/mdocx-grammar/spec.md` with 5 inline SBE Examples — but those examples are markdown blocks inside the spec, not standalone files that can be compiled, executed, or byte-diffed against a real `.docx`. Phase 4 of `word-aligned-state-sync` (Script transcoder, target ooxml-swift v0.34.0) needs concrete `.mdocx.swift` ↔ `.docx` pairs as test inputs for `ScriptExporter` (op log → DSL source) and `ScriptImporter` (DSL source → op log), and as the round-trip oracle for `macdoc word reverse <docx>`.

Without a fixture corpus, Phase 4 implementation is blind: there is no concrete "this DSL source SHALL produce this docx" assertion. Equally, the new Swift placeholder files at `packages/ooxml-swift/Sources/WordDSLSwift/` (14 types: WordDocument, Section, Paragraph, Run, Tab, Break, NoBreakHyphen, Hyperlink, Bookmark, Table, TableRow, TableCell, WordComponent, WordBuilder) cannot be safely filled in until each Requirement has a fixture pair that pins the expected behavior.

This change builds that corpus once, scoped to `mdocx-grammar`'s 15 Requirements. Each fixture pair pins one Requirement (or one variant of one Requirement) with a literal `.mdocx.swift` source plus an expected `.docx` golden plus an English README explaining what the pair covers and why.

The corpus also forces clarification of ambiguity in the spec: drafting `02-inline-grammar/multi-format-run.mdocx.swift` reveals whether the `Run` initializer parameter for color is `color`, `textColor`, or `foregroundColor` — a detail the spec does not pin. Such discoveries feed back into `mdocx-grammar` as Requirement amendments via a follow-up `/spectra-ingest mdocx-grammar`.

## What Changes

- **NEW**: Test fixture directory tree at `packages/ooxml-swift/Tests/OOXMLSwiftTests/Fixtures/mdocx/`, one subdirectory per fixture pair, named `<NN>-<short-slug>/` where `NN` matches the order of the corresponding Requirement in `mdocx-grammar/spec.md` (with `a`/`b`/... suffix when one Requirement gets multiple fixtures).
- **NEW**: 13 fixture pairs covering every applicable `mdocx-grammar` Requirement. Two Requirements ("save(to:) atomic three-file write" and "Reverse CLI shape — macdoc word reverse") generate file-system / CLI artifacts rather than docx output and get their own special fixture shape.
- **NEW**: Each fixture pair contains at minimum: `<slug>.mdocx.swift` (script source), `<slug>.docx` (expected golden), `README.md` (which Requirement it covers, what edge case it pins, what to inspect when it fails). Optional additions per pair: `<slug>.oplog.jsonl` (when component-aware op log is exercised), `<slug>.snapshot.json` (when atomic-save triple is exercised), `<slug>.normalized.docx` (the post-normalization form the byte-diff actually compares against).
- **NEW**: `MdocxFixtureNormalizer` Swift helper that strips identity-noise from a docx before diff: RSID attributes (`w:rsidR`, `w:rsidRDefault`, `w:rsidP`, `w:rsidRPr`, `w:rsidTr`), default theme files (`word/theme/theme1.xml` if equal to the Word default), default `word/settings.xml` keys, and Word-version-specific `paraId` / `textId` UUIDs. Used by the test runner to compare actual output against `<slug>.normalized.docx`.
- **NEW**: `MdocxFixtureCorpusTests` **phase-aware** parameterized test suite that walks the fixture directory and asserts a graduated set of contracts based on whether `WordDSLSwift` implementation has landed. **Phase A (now, before WordDSLSwift implementation):** runner enforces directory layout, naming pattern, minimum file-set presence, README presence, and `<slug>.mdocx.swift` Swift compile-pass against the placeholder module (compile-pass is sufficient at this stage). **Phase B (activated after `word-aligned-state-sync` Phase 4 lands the WordDSLSwift module):** runner additionally executes each `.mdocx.swift` script, runs the output through `MdocxFixtureNormalizer`, and asserts byte-equality against `<slug>.normalized.docx`; also runs op-log + snapshot + reverse-CLI assertions for the special-shape Requirements.
- **NEW**: Capability `mdocx-fixture-corpus` defining the corpus completeness contract: every `mdocx-grammar` Requirement SHALL have at least one fixture pair; every fixture pair SHALL have the minimum file set; the normalizer SHALL be deterministic; the runner SHALL be phase-aware so this change can apply and ship its corpus + normalizer + Phase A runner immediately, with Phase B activation deferred to the change that ships the WordDSLSwift module.
- **REVERSE-DIRECTION CROSS-REFERENCE**: The corpus also supplies the input to `macdoc word reverse <docx>` round-trip tests once Phase 4 task 5.7 lands the CLI.

## Non-Goals

- **Implementing the `WordDSLSwift` module**. The 14 placeholder Swift types at `packages/ooxml-swift/Sources/WordDSLSwift/` are filled in by `word-aligned-state-sync` Phase 4 (tasks 5.1-5.7). This change SHALL NOT bootstrap any WordDSLSwift body, builder, or docx-emit logic, even if smoke fixtures cannot run end-to-end without it. Doing so would silently smuggle Phase 4 work into a fixture change and violate scope.
- **Producing executable `.mdocx.swift` scripts in this change**. The hand-crafted `.mdocx.swift` files this change ships are **design-frozen surface specs**: they document what each `mdocx-grammar` Requirement looks like in DSL form, and they MUST compile against the WordDSLSwift placeholder module (compile-pass is sufficient). They do NOT execute to produce docx output until the WordDSLSwift implementation lands.
- **Activating Phase B byte-diff verification within this change**. Phase B (script execution + normalized docx byte-diff + op-log assertions + reverse-CLI assertions) is activated by a one-line flag in `MdocxFixtureCorpusTests` flipped by the change that lands the WordDSLSwift module. This change ships everything else needed for Phase B (corpus + normalizer + Phase A runner + Phase B test code path), so activation is mechanical.

## Capabilities

### New Capabilities

- `mdocx-fixture-corpus`: Normative coverage + structure contract for the `.mdocx` ↔ `.docx` golden fixture corpus. Defines the directory layout, file-set requirements per fixture pair, the normalizer's behavior, the numbering convention that maps fixture directories to `mdocx-grammar` Requirements, and the test-runner contract that drives the corpus.

### Modified Capabilities

(none)

## Impact

- Affected specs: NEW `mdocx-fixture-corpus` capability.
- Affected code:
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/Fixtures/mdocx/` directory tree (13 fixture pair subdirectories, each with the minimum file set described above)
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/MdocxFixtureNormalizer.swift` (the normalization helper)
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/MdocxFixtureCorpusTests.swift` (the parameterized test suite)
  - Modified: `openspec/specs/mdocx-grammar/spec.md` may receive Requirement amendments via follow-up `/spectra-ingest` if fixture authoring surfaces spec ambiguity
  - Removed: (none)
- Affected dependencies:
  - ooxml-swift Tests target: gains a new file pattern under `Tests/OOXMLSwiftTests/Fixtures/mdocx/`. No new external dep required (XML parsing reuses existing `XmlTreeReader`).
  - `word-aligned-state-sync` Phase 4 (tasks 5.1-5.7): becomes able to assert against this corpus once it lands. Phase 4 verification tasks gain "all `mdocx-fixture-corpus` fixtures pass" as an acceptance criterion.
  - No che-word-mcp surface change. Corpus is internal to ooxml-swift's test target.
