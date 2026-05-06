## Context

`mdocx-grammar` (canonical at `openspec/specs/mdocx-grammar/spec.md`, 15 Requirements) is the normative grammar for the `.mdocx` Swift DSL. It contains 5 inline SBE `##### Example:` blocks — sufficient for human readers, insufficient for machine verification. There are no standalone files that:

1. Compile and execute the example DSL source.
2. Compare the produced docx against an expected golden.
3. Demonstrate every Requirement's behavior with a literal artifact pair.

`word-aligned-state-sync` Phase 4 (Script transcoder, target ooxml-swift v0.34.0, see Decision 9 of that change's design.md) needs concrete pairs to test:
- `ScriptExporter.exportSwift(log:)` — given an op log, the emitted `.mdocx.swift` source SHALL match the corresponding fixture's source.
- `ScriptImporter.parse(source:)` — given a fixture's `.mdocx.swift` source, the produced op log SHALL produce the fixture's docx on materialization.
- `macdoc word reverse <docx>` — given a fixture's docx, the reversed source SHALL match the fixture's `.mdocx.swift` (modulo formatting).

Sibling reference: Phase 0 of `word-aligned-state-sync` already established a separate "round-trip golden corpus" at `packages/ooxml-swift/Tests/OOXMLSwiftTests/Fixtures/` (see `TreeRoundTripCorpusTests.swift`, `TreeRoundTripGoldenTests.swift`). That corpus covers a different concern: byte-equal Reader / Writer round-trip on Word-authored documents (multi-section thesis, VML-rich, CJK settings, comments). The `mdocx` fixture corpus introduced by this change is structurally and semantically distinct: it covers DSL ↔ docx conversion, not Reader / Writer round-trip.

## Goals / Non-Goals

**Goals:**

- Establish a deterministic, machine-verifiable corpus that pins every `mdocx-grammar` Requirement to a literal `.mdocx.swift` ↔ `.docx` artifact pair.
- Define a normalization pipeline so byte-diff comparison is stable across Word versions, OS, and ooxml-swift release-to-release.
- Document the corpus structure (directory layout, file-set requirements, numbering convention) as a normative contract that future fixture additions follow without re-deciding.
- Surface and resolve `mdocx-grammar` ambiguity discovered during fixture authoring through `/spectra-ingest mdocx-grammar` follow-ups.
- Provide the test infrastructure (`MdocxFixtureNormalizer`, `MdocxFixtureCorpusTests`) that consumes the corpus.

**Non-Goals:**

- Replacing the Phase 0 byte-equal round-trip golden corpus. That serves a different purpose (Reader / Writer fidelity on real-world Word documents) and stays separate.
- Authoring fixtures for `.mpdf` / `.mbib` / `.mpptx` future DSLs. Out of scope; those get their own future fixture corpora.
- Building a fixture-generation CLI. Fixtures are hand-crafted (see Decision 1 below). Auto-generation would re-introduce the "implementation as oracle" anti-pattern.
- Verifying any Phase 4 implementation behavior. Phase 4 lives in `word-aligned-state-sync`; this change only ships the test corpus + infrastructure.
- Migrating the 5 inline SBE Examples in `mdocx-grammar/spec.md` out of the spec. They stay inline as quick-reference for human readers; the standalone fixture pairs are additive, not replacing.

## Decisions

### Decision 1: Hand-crafted XML for golden docx, not Word-saved or ooxml-swift-emitted

The expected `<slug>.docx` golden in each fixture pair SHALL be hand-crafted minimal OOXML, written directly in an XML editor and zipped. It SHALL NOT come from saving a document in Word, and SHALL NOT come from running the ooxml-swift writer.

**Why**:
- *Word-saved docx* carries Word-version-specific noise (RSIDs, theme1.xml fingerprint, paraId UUID format, settings.xml defaults). Different Word versions on different OS produce byte-different output for the same authoring action. Using Word-saved as golden would mean fixtures break on the team member's Word upgrade — a maintenance trap.
- *ooxml-swift-emitted docx* is a circular oracle: the implementation under test produces the expected output, so a regression in the implementation silently regenerates a wrong-but-self-consistent golden. The implementation cannot be its own truth.
- *Hand-crafted XML* is deterministic, reviewable in code review (the diff of the docx golden is the diff of the XML the human wrote), and scoped to exactly what each Requirement specifies. The author is forced to write only what the Requirement demands, which is the desired discipline.

**Cost**: hand-crafting a docx is tedious (correct ZIP structure, `[Content_Types].xml`, relationships). Mitigation: the corpus targets minimal docs (single paragraph, single table row, one section), so each fixture's docx is typically under 1 KB of XML.

**Alternatives considered**:
- *Hybrid: Word-saved + post-hoc normalization to strip noise*. Rejected: still version-coupled to whichever Word produced the seed. Normalization (Decision 2) handles the noise problem at compare time, so the seed source remains hand-crafted.
- *Auto-generate fixtures from `mdocx-grammar` spec parser*. Rejected: there is no spec parser; even if there were, this re-introduces "implementation as oracle" through the parser layer.
- *Use existing thesis fixture from Phase 0 corpus*. Rejected: that corpus targets Word-authored real-world docs, not minimal Requirement-pinned examples. Conflating them would lose the surgical scope each corpus provides.

### Decision 2: Normalize before byte-diff; normalizer is part of the test infrastructure

The test runner SHALL compare the docx produced by executing `<slug>.mdocx.swift` against `<slug>.normalized.docx` (the post-normalization form of the hand-crafted golden). The normalization pipeline SHALL strip:

- All RSID attributes: `w:rsidR`, `w:rsidRDefault`, `w:rsidP`, `w:rsidRPr`, `w:rsidTr`, and any `w:rsids` element in `word/settings.xml`.
- Default theme: `word/theme/theme1.xml` SHALL be removed if its content equals the canonical Word default theme bytes (a fixed file we vendor in `Fixtures/mdocx/_normalizer/word-default-theme.xml`); a non-default theme SHALL be preserved as-is.
- Default settings: every `word/settings.xml` element key whose value equals the Word default SHALL be removed; non-default keys SHALL be preserved.
- `paraId` / `textId` / `bookmarkId` UUID values SHALL be re-numbered to a deterministic monotonic sequence (`paraId="00000001"`, `paraId="00000002"`, ...). The relative ordering across the document SHALL be preserved so cross-references (anchors, bookmarks) remain valid; only the absolute UUID values change.

The normalizer is implemented in `packages/ooxml-swift/Tests/OOXMLSwiftTests/MdocxFixtureNormalizer.swift` and operates on the unzipped docx parts. It is deterministic, idempotent, and pure (no side effects, no I/O beyond reading the input).

**Why**: Without normalization, fixtures break on every change to ooxml-swift's UUID generation, theme defaults, or settings injection. The normalizer formalizes "the parts of the docx that this Requirement actually constrains" by stripping the parts it does not. The result is a byte-equal diff that is meaningful: any byte difference is a real semantic divergence, not noise.

**Why a separate normalized golden file** (`<slug>.normalized.docx`) instead of normalizing both sides at compare time:
- Normalized golden is reviewable in code review without running a tool.
- Future test-failure debugging has a stable reference point.
- The normalizer's behavior changes can be caught by regenerating goldens and reviewing the diff.

**Alternatives considered**:
- *Normalize both sides at compare time, no stored normalized golden*. Rejected: hides what "the test actually checks" behind tool execution; harder to debug.
- *Whitelist (only compare specified parts)*. Rejected: too permissive. A new `<w:hyperlink>` element introduced by a regression would be ignored if hyperlink wasn't whitelisted. Strip-known-noise is safer than allow-known-content.

### Decision 3: Fixture directory numbering tracks `mdocx-grammar` Requirement order, with letter suffix for variants

Each fixture pair lives in a subdirectory named `<NN>-<short-slug>/` where:

- `NN` is a two-digit number matching the order of the corresponding Requirement in `openspec/specs/mdocx-grammar/spec.md`. Requirement 1 ("File extension and dual-extension pattern") maps to `01-...`, Requirement 2 ("Flat Run with implicit String literal inline grammar") to `02-...`, etc.
- `<short-slug>` is a 2-4 word kebab-case description (e.g., `inline-grammar`, `tables-3x3`, `cross-paragraph-bookmark`).
- When one Requirement has multiple fixtures, append a single letter suffix to `NN`: `02a-plain-string/`, `02b-explicit-run-multi-format/`, `02c-mixed-string-and-run/`.

| Fixture # | Requirement | Slug |
|-----------|-------------|------|
| 01 | File extension and dual-extension pattern | dual-extension-recognition |
| 02a | Flat Run with implicit String literal inline grammar | plain-string |
| 02b | Flat Run with implicit String literal inline grammar | explicit-run-multi-format |
| 03 | Special-character inline atoms as standalone children | tab-break-nbhyphen |
| 04 | OOXML-mirror element naming | mirrored-element-set |
| 05 | No semantic shortcuts for OOXML-style attributes | heading-via-style |
| 06 | Section as DSL container with compile-time marker inversion | two-sections-marker-inversion |
| 07 | Component-aware op log via BeginComponent and EndComponent | summary-component |
| 08 | Mandatory explicit identifiers on structural elements | explicit-id-everywhere |
| 09 | Style references via typed enum with define-on-first-use | style-define-on-first-use |
| 10a | Table grammar mirrors OOXML three-layer structure | table-1x1 |
| 10b | Table grammar mirrors OOXML three-layer structure | table-3x3-with-formatting |
| 11 | Lists use Paragraph with numPr reference, not nested containers | bullet-and-numbered-lists |
| 12 | Hyperlinks are containers with target enum | hyperlink-url-anchor-mailto |
| 13a | Bookmarks default to container with paired-marker escape hatch | bookmark-container |
| 13b | Bookmarks default to container with paired-marker escape hatch | bookmark-cross-paragraph |
| 14 | save(to:) atomic three-file write | atomic-three-file-save |
| 15 | Reverse CLI shape — macdoc word reverse | reverse-cli-roundtrip |

**Why this scheme**:
- Numbering matches Requirement order in spec.md, so a reader can navigate spec ↔ corpus by ordinal lookup.
- Letter suffix accommodates variants without renumbering the whole corpus when a Requirement gains a second fixture.
- Total of 18 fixture directories for 15 Requirements (some have multiple) is a manageable corpus size — large enough to cover the surface, small enough to maintain.
- The two non-docx Requirements (14, 15) get their own special fixture shape (see Decision 4).

**Alternatives considered**:
- *Sequential numbering ignoring Requirement mapping*. Rejected: loses the spec-to-corpus traceability that makes the corpus useful as documentation.
- *Hierarchical directories (`requirement-04/fixture-a/`, `requirement-04/fixture-b/`)*. Rejected: adds depth without value. Flat with letter suffix is shorter and equally clear.

### Decision 4: Minimum file set per fixture pair, with optional additions for special Requirements

Every fixture pair SHALL contain at minimum:

- `<slug>.mdocx.swift` — the DSL source. Compilable Swift that, when executed against an empty `OperationLog`, produces the operations needed to materialize the expected docx. Must include the standard `import` for the WordDSLSwift module.
- `<slug>.docx` — the hand-crafted golden docx (per Decision 1). The "raw" form before normalization.
- `<slug>.normalized.docx` — the post-normalization form (per Decision 2). The byte-diff target. Generated once by running the normalizer on the raw golden and committed to the repo.
- `README.md` — short description (under 300 words) covering: which Requirement (cite by name + spec section anchor), what edge case the fixture pins, what to inspect when the test fails, any non-obvious choices made when authoring the fixture (e.g., "uses Calibri instead of default font because the spec example uses Calibri").

Optional additions per fixture, used only when the Requirement involves these artifacts:

- `<slug>.oplog.jsonl` — the expected op log content for fixtures that exercise op-log behavior (Requirement 7 component envelope, Requirement 9 define-on-first-use ordering).
- `<slug>.snapshot.json` — the expected snapshot file content for fixtures that exercise atomic-save semantics (Requirement 14 only).
- `<slug>.expected-source.mdocx.swift` — the expected reverse-direction output for fixtures that exercise `macdoc word reverse` (Requirement 15 only). Distinct from the input `<slug>.mdocx.swift` because formatting may differ after round-trip.

**Special-case Requirements 14 (atomic save) and 15 (reverse CLI)** do not have a single docx golden — they exercise a process or a command-line surface:

- Fixture 14 (`14-atomic-three-file-save`): the `mdocx.swift` script ends with `try doc.save(to: ...)`. The test asserts the three files (`<name>.docx`, `<name>.docx.oplog.jsonl`, `<name>.docx.snapshot.json`) all exist with the expected content (each compared against its own normalized golden). It also asserts the failure case: forcing a write error on file 2 SHALL leave files 1 and 3 unchanged.
- Fixture 15 (`15-reverse-cli-roundtrip`): two scripts — `input.mdocx.swift` (the source the test executes to produce a docx) and `expected-source.mdocx.swift` (the source `macdoc word reverse` SHOULD produce when run against the produced docx). The test asserts source equivalence after a canonicalization pass (whitespace normalization, parameter order normalization).

**Why minimum + optional**: enforcing a minimum set in spec form prevents fixtures from going stale (no `README.md` = no excuse for "I forgot why I added this fixture"). The optional set keeps fixtures focused — Requirement 2 has nothing to say about op log content, so its fixture should not include an `.oplog.jsonl` that adds maintenance burden without value.

**Alternatives considered**:
- *No `README.md`, rely on path slug for documentation*. Rejected: slug capacity is 2-4 words; cannot capture "why this edge case", "what to inspect when failing", or "non-obvious choices". Failed fixtures with no README waste reviewer time.
- *Single `.normalized.docx` only, drop the raw `.docx`*. Rejected: the raw form is the readable artifact a code reviewer inspects ("does this hand-crafted XML match the spec?"); the normalized form is the test target. Both serve distinct review functions.

### Decision 5: Phase-aware test runner — Phase A enforces structure, Phase B activates execution after WordDSLSwift implementation lands

`MdocxFixtureCorpusTests` runs in two phases gated by a single Boolean flag in the test file (default `false`, flipped to `true` by the change that lands the WordDSLSwift module). The phases are:

**Phase A (this change ships, active immediately):**
- Walks every directory under `Fixtures/mdocx/`.
- Validates directory name matches the layout pattern.
- Validates the minimum file set is present.
- Validates `<slug>.mdocx.swift` parses as Swift and compiles against the WordDSLSwift placeholder module (compile-pass is sufficient — no execution).
- Validates the corpus completeness contract (every `mdocx-grammar` Requirement has at least one matching fixture by NN prefix).

**Phase B (activated by the change that lands WordDSLSwift, gated by flipping `MdocxFixtureCorpusTests.activatePhaseB = true`):**
- Adds: executes each `<slug>.mdocx.swift` against `WordDocument` builder.
- Adds: runs the produced docx through `MdocxFixtureNormalizer`.
- Adds: byte-equality assertion against `<slug>.normalized.docx`.
- Adds: when `<slug>.oplog.jsonl` is present, byte-equality assertion against the produced op log.
- Adds: when `<slug>.snapshot.json` is present (Requirement 14 only), byte-equality assertion against the produced snapshot.
- Adds: when `<slug>.expected-source.mdocx.swift` is present (Requirement 15 only), source-equivalence assertion after canonicalization.

**Why phase-aware (and not "ship corpus + skip runner activation")**:
- Phase A delivers real value the day it ships: corpus completeness, file-set hygiene, naming convention enforcement, and Swift compile-pass on the .mdocx.swift design specs. Without this, the corpus is documentation people forget to read.
- Phase B activation is a one-line flip when WordDSLSwift lands. The full Phase B test code path is shipped in this change so the activating change does NOT need to add Phase B logic — it only flips the flag and runs.
- Phase A compile-pass requirement on `.mdocx.swift` forces the WordDSLSwift placeholder module to expose the **public surface symbols** (`WordDocument`, `Section`, `Paragraph`, `Run`, etc., with the parameter labels and types in `mdocx-grammar`) even before bodies are filled in. This is the same TDD discipline as the `Phase 1 task 2.1 RED scaffold` for `Paragraph`: pin the API surface in test source before the implementation lands.

**Why not just defer the whole corpus until WordDSLSwift exists**:
- Authoring 18 fixtures takes ~9 hours of hand-crafting work that is not blocked by WordDSLSwift; sequencing it after Phase 4 wastes 3-4 weeks of momentum.
- Phase A's compile-pass requirement on `.mdocx.swift` files exerts forward pressure on WordDSLSwift's API surface design — the placeholder module gets concrete usage examples to validate against, which catches API gaps earlier than waiting for Phase 4 implementation to discover them.
- The corpus + normalizer + Phase A runner are useful as documentation and structure enforcement on day one, even without execution verification.

**Why not Option γ (bootstrap minimum WordDSLSwift here)**:
- Bootstrap means partial Phase 4 work hidden inside a fixture change; future maintainers reading `mdocx-fixture-corpus` would need to know WordDSLSwift bootstrap also lives here. Surprising.
- The bootstrap would diverge from the eventual Phase 4 implementation, requiring a second migration when Phase 4 lands. Two implementations of the same surface = bugs hide in the seam.

**Activation contract for the future change that lands WordDSLSwift** (recorded here so the future author finds it):
1. Implement `WordDocument`, `Section`, `Paragraph`, etc. bodies + `@WordBuilder` per `mdocx-grammar` spec.
2. Confirm `<slug>.mdocx.swift` for fixture `01-dual-extension-recognition` executes and produces a docx that matches its `.normalized.docx` byte-equal.
3. Flip `MdocxFixtureCorpusTests.activatePhaseB = true`.
4. Run the full suite. All 18 fixtures should pass Phase B assertions; investigate any that don't.
5. Update this `mdocx-fixture-corpus` design doc with a "Phase B activated by change `<change-name>` on `<date>`" footnote.

## Risks / Trade-offs

- *Hand-crafting docx is tedious and error-prone* — Mitigation: each fixture targets minimal content (one paragraph, one table row, one section). The author can copy-paste the docx skeleton (`[Content_Types].xml`, `_rels/.rels`, `word/_rels/document.xml.rels`) from a template. The CI test runner catches malformed XML at first execution. Estimated cost per fixture: 30 minutes including README.
- *Normalizer behavior is itself untested* — Mitigation: dedicated `MdocxFixtureNormalizerTests.swift` (added in tasks 4.1) covering each strip rule with input / expected-output pairs.
- *Fixture corpus can fall out of sync with `mdocx-grammar` Requirements* — Mitigation: the spec scenario "fixture corpus covers every Requirement" enforces this; the test runner fails if any Requirement has no matching fixture. Adding a Requirement to the spec without adding a fixture pair is a CI failure.
- *`Fixtures/mdocx/` directory grows large over time* — Acknowledged: 18 fixtures at ~5 KB each = 90 KB today. Even doubled to 200 KB it stays under any concerning git size. If the corpus grows beyond ~5 MB (Phase 4 + downstream changes adding many variants), revisit storing goldens in git LFS.
- *Phase 4 implementation drift from the corpus* — Mitigation: Phase 4 task 5.1-5.7 reference the corpus; the Phase 4 release gate "all `mdocx-fixture-corpus` fixtures pass" is added in Phase 4 verification.

## Migration Plan

This change ships net-new artifacts. There is nothing to migrate from. The test corpus directory does not exist before this change; the normalizer and test runner do not exist before this change. Existing che-word-mcp tests, macdoc CLI tests, and the Phase 0 byte-equal round-trip corpus are unaffected.

Rollback: deleting `packages/ooxml-swift/Tests/OOXMLSwiftTests/Fixtures/mdocx/`, `MdocxFixtureNormalizer.swift`, and `MdocxFixtureCorpusTests.swift` removes everything this change adds, with no impact elsewhere.

## Open Questions

(no open decisions — all four user-flagged decisions resolved above; ready for spec plus tasks)
