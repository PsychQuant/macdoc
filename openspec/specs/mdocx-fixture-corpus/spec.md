# mdocx-fixture-corpus Specification

## Purpose

Pin the structure, completeness, and verification contract of the `.mdocx` ↔ `.docx` golden fixture corpus that lives at `packages/ooxml-swift/Tests/OOXMLSwiftTests/Fixtures/mdocx/`. The corpus is the executable form of the [`mdocx-grammar`](../mdocx-grammar/spec.md) Requirements: every Requirement in the grammar SHALL have at least one fixture pair pinning its expected behavior with literal `.mdocx.swift` (DSL source) + `.docx` (golden expected output) + `.normalized.docx` (byte-diff target after identity-noise stripping) + `README.md` artifacts. Phase A enforces structure + Swift compile-pass at corpus level; Phase B (gated by an activation flag flipped by the change that lands the WordDSLSwift module) executes scripts and byte-diffs against goldens.

The corpus is consumed by `MdocxFixtureCorpusTests` and `MdocxFixtureNormalizer` (helper that strips RSIDs, default-theme bytes, default settings keys, and re-numbers UUID-shaped IDs while preserving cross-references). Built per the [`embedded-dsl-spec-pattern`](../embedded-dsl-spec-pattern/spec.md) discipline so the test corpus structure is itself spec-driven.

## Related rules and contracts

- [`mdocx-grammar`](../mdocx-grammar/spec.md) — the normative grammar each fixture pins.
- [`embedded-dsl-spec-pattern`](../embedded-dsl-spec-pattern/spec.md) — the meta-rule for shaping embedded-DSL specs (this corpus is one).
- `.claude/rules/extension-first-dsl.md` — file-extension contract for `.mdocx`.
- `docs/swift-as-document-source.md` — narrative DSL design rationale.
- Future Phase B activation: the change that lands `WordDSLSwift` implementation flips `MdocxFixtureCorpusTests.activatePhaseB = true` per the design.md Decision 5 hand-off contract.

## Requirements

### Requirement: Corpus completeness contract

The `.mdocx` fixture corpus at `packages/ooxml-swift/Tests/OOXMLSwiftTests/Fixtures/mdocx/` SHALL contain at least one fixture pair for every Requirement defined in `openspec/specs/mdocx-grammar/spec.md`. The test runner SHALL fail if any `mdocx-grammar` Requirement has no matching fixture, identified by the fixture directory's numeric prefix.

When a new Requirement is added to `mdocx-grammar` (via `/spectra-ingest mdocx-grammar` or a new sibling change that modifies it), the same change SHALL also add at least one fixture pair covering that Requirement before the change archives.

#### Scenario: missing fixture for a Requirement fails CI

- **WHEN** `mdocx-grammar/spec.md` contains a Requirement at ordinal position N
- **AND** no fixture directory under `Fixtures/mdocx/` has `NN` (zero-padded) as its numeric prefix
- **THEN** `MdocxFixtureCorpusTests` SHALL fail with a message naming the uncovered Requirement
- **AND** the test SHALL NOT be markable as expected-failure or skipped

#### Scenario: covering one Requirement with multiple fixtures is permitted

- **WHEN** Requirement N is non-trivial enough to warrant variant fixtures (e.g., table 1×1 vs table 3×3)
- **THEN** multiple fixture directories MAY share the prefix `NN` distinguished by letter suffix (`NNa-...`, `NNb-...`, `NNc-...`)
- **AND** the test runner SHALL count any one of them as satisfying coverage for Requirement N

##### Example: fixture-to-Requirement coverage table at change archive time

- **GIVEN** `mdocx-grammar/spec.md` contains 15 Requirements ordered 1 through 15
- **WHEN** the corpus contains directories `01-dual-extension-recognition`, `02a-plain-string`, `02b-explicit-run-multi-format`, ..., `15-reverse-cli-roundtrip`
- **THEN** the coverage check SHALL pass with the mapping:
  ```
  Requirement 1  → 01-...                  (1 fixture)
  Requirement 2  → 02a-..., 02b-...        (2 fixtures)
  Requirement 3  → 03-...                  (1 fixture)
  ...
  Requirement 15 → 15-...                  (1 fixture)
  ```


<!-- @trace
source: mdocx-fixture-corpus
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093300.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-143733.log
-->

---
### Requirement: Fixture directory layout and naming

Each fixture pair SHALL live in its own subdirectory under `packages/ooxml-swift/Tests/OOXMLSwiftTests/Fixtures/mdocx/`. The directory name SHALL match the pattern `<NN>[<letter>]-<short-slug>` where:

- `NN` is a two-digit zero-padded integer matching the ordinal position of the corresponding Requirement in `mdocx-grammar/spec.md`.
- `<letter>` is an optional single lowercase letter (`a`, `b`, `c`, ...) used when one Requirement has multiple variant fixtures.
- `<short-slug>` is a 2-4 word kebab-case description of what the fixture pins.

Directory names SHALL NOT contain spaces, uppercase letters, or punctuation other than the separator hyphen.

#### Scenario: directory name parses cleanly into Requirement number

- **WHEN** a fixture directory is named `02b-explicit-run-multi-format`
- **THEN** the test runner SHALL parse it as Requirement 2, variant `b`, slug `explicit-run-multi-format`
- **AND** the corpus completeness check SHALL credit Requirement 2 with this fixture

#### Scenario: malformed directory name fails test discovery

- **WHEN** a fixture directory is named `tables` (missing `NN` prefix) or `2-tables` (missing zero-padding) or `02 tables` (containing space)
- **THEN** the test runner SHALL fail with a message naming the malformed directory
- **AND** the test runner SHALL NOT silently skip the directory


<!-- @trace
source: mdocx-fixture-corpus
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093300.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-143733.log
-->

---
### Requirement: Minimum file set per fixture pair

Every fixture directory SHALL contain at minimum these four files:

1. `<slug>.mdocx.swift` — compilable Swift source representing the DSL script.
2. `<slug>.docx` — the hand-crafted golden docx (raw, pre-normalization form).
3. `<slug>.normalized.docx` — the post-normalization form of the golden, used as the byte-diff target.
4. `README.md` — under 300 words, naming the covered Requirement, the edge case pinned, and what to inspect when the fixture fails.

The slug in each filename SHALL match the slug in the directory name (e.g., directory `02a-plain-string` contains `plain-string.mdocx.swift`, `plain-string.docx`, `plain-string.normalized.docx`, `README.md`).

A fixture directory missing any of the four files SHALL cause the test runner to fail with a message naming the missing file.

#### Scenario: complete minimum set passes the file-set check

- **GIVEN** a directory `02a-plain-string/` containing `plain-string.mdocx.swift`, `plain-string.docx`, `plain-string.normalized.docx`, `README.md`
- **WHEN** the test runner walks the corpus
- **THEN** the directory passes the file-set check

#### Scenario: missing README fails the file-set check

- **GIVEN** a directory `02a-plain-string/` containing `plain-string.mdocx.swift`, `plain-string.docx`, `plain-string.normalized.docx` only
- **WHEN** the test runner walks the corpus
- **THEN** the test runner SHALL fail with a message indicating `02a-plain-string/README.md` is missing


<!-- @trace
source: mdocx-fixture-corpus
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093300.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-143733.log
-->

---
### Requirement: Optional file additions for special Requirements

Fixture directories MAY contain additional files when the covered Requirement exercises behavior beyond docx output:

- `<slug>.oplog.jsonl` — expected op log content. Used when the fixture covers Requirements that constrain op-log shape (`mdocx-grammar` Requirement 7 component envelope, Requirement 9 define-on-first-use ordering).
- `<slug>.snapshot.json` — expected snapshot file content. Used only when the fixture covers `mdocx-grammar` Requirement 14 (atomic three-file save).
- `<slug>.expected-source.mdocx.swift` — expected reverse-direction source. Used only when the fixture covers `mdocx-grammar` Requirement 15 (reverse CLI). This file SHALL differ from `<slug>.mdocx.swift` only when the reverse direction produces a non-identical canonical form (formatting normalization).

Fixture directories that include any optional file SHALL include a corresponding section in the `README.md` explaining why that optional file is present.

#### Scenario: oplog fixture for component Requirement

- **GIVEN** a fixture directory `07-summary-component/` covering Requirement 7 (component-aware op log)
- **WHEN** the directory contains `summary-component.oplog.jsonl`
- **THEN** the test runner SHALL parse the file and use it as the expected op-log content for the test
- **AND** the README SHALL contain a section explaining why op-log assertion is part of this fixture

#### Scenario: optional file in irrelevant fixture is rejected

- **GIVEN** a fixture directory `02a-plain-string/` covering Requirement 2 (inline grammar)
- **WHEN** the directory contains `plain-string.snapshot.json`
- **THEN** the test runner SHALL fail with a message indicating Requirement 2 does not use snapshot assertions
- **AND** the test runner SHALL list which Requirements legitimately use `<slug>.snapshot.json`


<!-- @trace
source: mdocx-fixture-corpus
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093300.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-143733.log
-->

---
### Requirement: Hand-crafted golden source

The `<slug>.docx` golden in each fixture pair SHALL be authored by hand (in an XML editor, then zipped into a docx container). It SHALL NOT be produced by saving a document in Microsoft Word, nor by running `ooxml-swift`'s `DocxWriter`, nor by any auto-generation tool that derives docx output from the corresponding `<slug>.mdocx.swift` source.

This contract SHALL be enforced by review at change-time: each pull request adding or modifying a `<slug>.docx` SHALL be reviewed for hand-authoring evidence (e.g., the diff is human-readable XML, no RSID UUIDs are present in the raw file before normalization that would betray Word-origin).

#### Scenario: hand-crafted docx passes review

- **GIVEN** a `<slug>.docx` whose unzipped `word/document.xml` is a minimal hand-written XML file with no RSID attributes, no theme references beyond what the fixture explicitly tests, and no `w:rsids` element in `word/settings.xml`
- **WHEN** the change adding the fixture is reviewed
- **THEN** the reviewer SHALL accept the fixture

#### Scenario: Word-saved docx fails review

- **GIVEN** a `<slug>.docx` whose unzipped `word/document.xml` contains RSID attributes (`w:rsidR="..."`), a non-default `word/theme/theme1.xml` matching a Word-version-specific fingerprint, or a `word/settings.xml` containing a `w:rsids` element
- **WHEN** the change adding the fixture is reviewed
- **THEN** the reviewer SHALL reject the fixture with a request to hand-craft a minimal version


<!-- @trace
source: mdocx-fixture-corpus
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093300.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-143733.log
-->

---
### Requirement: Normalization pipeline behavior

`MdocxFixtureNormalizer` SHALL transform a docx through a deterministic, idempotent, pure (no I/O beyond reading the input) pipeline that strips:

1. All RSID attributes (`w:rsidR`, `w:rsidRDefault`, `w:rsidP`, `w:rsidRPr`, `w:rsidTr`) from every element.
2. The `w:rsids` element from `word/settings.xml` if present.
3. `word/theme/theme1.xml` if and only if its content equals the canonical Word default theme bytes vendored at `Fixtures/mdocx/_normalizer/word-default-theme.xml`. A non-default theme SHALL be preserved.
4. Every element key from `word/settings.xml` whose value equals the Word default. Non-default keys SHALL be preserved.
5. UUID-shaped attribute values for `w14:paraId`, `w14:textId`, `w:bookmarkId` SHALL be re-numbered to a deterministic monotonic sequence (`00000001`, `00000002`, ...) in document order. Cross-references that target these IDs (anchors, bookmarks) SHALL be updated to the new IDs so referential integrity is preserved.

The normalizer's output SHALL be byte-identical when run twice on the same input (idempotence) and SHALL be byte-identical when run on inputs that differ only in the stripped fields (determinism).

#### Scenario: idempotence

- **WHEN** the normalizer is run on input docx D producing N1
- **AND** the normalizer is run again on N1 producing N2
- **THEN** N1 and N2 SHALL be byte-equal

#### Scenario: RSID stripping

- **GIVEN** a docx whose `word/document.xml` contains `<w:p w:rsidR="00ABC123" w14:paraId="0AB7C123">...</w:p>`
- **WHEN** the normalizer runs
- **THEN** the output `word/document.xml` SHALL contain `<w:p w14:paraId="00000001">...</w:p>` (RSID stripped, paraId re-numbered to monotonic 00000001)

#### Scenario: cross-reference preservation through ID re-numbering

- **GIVEN** a docx with two paragraphs: `<w:p w14:paraId="0ABC1234">...</w:p>` followed by `<w:p w14:paraId="0XYZ7890">...</w:p>`, and a hyperlink elsewhere `<w:hyperlink w:anchor="0XYZ7890">...</w:hyperlink>`
- **WHEN** the normalizer runs
- **THEN** the paragraphs become `paraId="00000001"` and `paraId="00000002"` in document order
- **AND** the hyperlink anchor SHALL be updated to `w:anchor="00000002"` to preserve the cross-reference

##### Example: stripped attributes table

| Stripped | Reason |
|----------|--------|
| `w:rsidR` | Word session UUID, varies per save |
| `w:rsidRDefault` | Same |
| `w:rsidP` | Same |
| `w:rsidRPr` | Same |
| `w:rsidTr` | Same |
| `w:rsids` element in settings.xml | Container of all session UUIDs |
| `theme1.xml` if equal to vendored default | Word-version-default theme adds bytes without semantic content |
| settings.xml keys equal to Word default | Same reason as theme |


<!-- @trace
source: mdocx-fixture-corpus
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093300.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-143733.log
-->

---
### Requirement: Phase-aware parameterized test runner contract

`MdocxFixtureCorpusTests` SHALL walk every directory under `Fixtures/mdocx/` (excluding `_normalizer/` and any directory beginning with `_`) and execute one parameterized test per fixture directory. The runner SHALL operate in two phases gated by a single Boolean flag `MdocxFixtureCorpusTests.activatePhaseB` (default `false`, flipped to `true` by the change that lands the `WordDSLSwift` module implementation). Each parameterized test SHALL execute the Phase A assertions unconditionally, and SHALL execute the Phase B assertions if and only if `activatePhaseB == true`.

**Phase A assertions (always run, this change ships them active):**

1. Validate the directory name matches the layout pattern (per the layout Requirement above) — failure halts the test for that fixture with a clear error.
2. Validate the minimum file set is present (per the file-set Requirement) — failure halts.
3. Validate that `<slug>.mdocx.swift` parses as Swift and compiles against the `WordDSLSwift` module (whatever its current implementation state — placeholder or full). Compile-pass is sufficient at Phase A; no execution is performed.
4. Validate the corpus completeness contract (per the completeness Requirement above) reports green coverage for the corpus as a whole.

**Phase B assertions (run only when `activatePhaseB == true`):**

5. Execute the `<slug>.mdocx.swift` script through the `WordDSLSwift` module to produce an output docx.
6. Run the output docx through `MdocxFixtureNormalizer`.
7. Compare the normalized output against `<slug>.normalized.docx` byte-equal.
8. When `<slug>.oplog.jsonl` is present, compare the produced op log byte-equal against it.
9. When `<slug>.snapshot.json` is present (Requirement 14 only), compare the produced snapshot byte-equal against it.
10. When `<slug>.expected-source.mdocx.swift` is present (Requirement 15 only), execute `macdoc word reverse` against the produced docx and compare the reversed source against `<slug>.expected-source.mdocx.swift` after canonicalization (whitespace + parameter order normalization).

The test runner SHALL produce a clear diagnostic on failure naming: which fixture, which phase, which assertion failed, the path to both compared files (when applicable), and a short hint pointing to the README of that fixture.

The `activatePhaseB` flag SHALL be flipped from `false` to `true` exclusively by the change that lands the `WordDSLSwift` module implementation (`word-aligned-state-sync` Phase 4). That activating change SHALL also confirm fixture `01-dual-extension-recognition` passes its Phase B assertions before flipping the flag, so activation does not surface unrelated regressions.

#### Scenario: Phase A runs unconditionally and enforces compile-pass

- **GIVEN** a corpus with 18 fixture directories and `MdocxFixtureCorpusTests.activatePhaseB == false`
- **WHEN** the test runner runs
- **THEN** 18 parameterized test cases SHALL execute, each asserting layout pattern, file-set presence, and `.mdocx.swift` Swift compile-pass against the current `WordDSLSwift` module
- **AND** no Phase B assertion (script execution, docx byte-diff, op-log diff, snapshot diff, reverse-CLI diff) SHALL execute

#### Scenario: Phase B activated by flag flip

- **GIVEN** a corpus with 18 fixture directories, `WordDSLSwift` implementation has landed, and the activating change sets `MdocxFixtureCorpusTests.activatePhaseB = true`
- **WHEN** the test runner runs
- **THEN** 18 parameterized test cases SHALL execute, each asserting Phase A assertions PLUS the applicable Phase B assertions for that fixture (script execution + docx byte-diff always; op-log diff when `.oplog.jsonl` present; snapshot diff for fixture 14; reverse-CLI diff for fixture 15)

#### Scenario: Phase A compile-pass against placeholder module

- **GIVEN** a fixture `02a-plain-string/plain-string.mdocx.swift` that uses `WordDocument { Section(id: ...) { Paragraph(id: ...) { "Hello" } } }`
- **AND** the `WordDSLSwift` module is in its placeholder state (types declared, builder bodies empty)
- **WHEN** Phase A's compile-pass assertion runs against this fixture
- **THEN** the assertion SHALL pass if the placeholder module exposes the public surface symbols `WordDocument`, `Section(id:)`, `Paragraph(id:)`, the `@WordBuilder` result builder attribute, and a `String`-to-`Run` implicit conversion that allow the source to compile, even if those builder bodies do nothing at runtime
- **AND** SHALL fail if any required public surface symbol is missing or has the wrong parameter labels

#### Scenario: Phase B inactive when WordDSLSwift bodies are empty

- **GIVEN** the `WordDSLSwift` module in placeholder state and `activatePhaseB == false`
- **WHEN** the test runner runs
- **THEN** no fixture SHALL fail due to "WordDSLSwift produced no docx output" — Phase B execution is gated by the flag, not by trying execution and tolerating failure

#### Scenario: corpus walk discovers all fixtures

- **GIVEN** a corpus with 18 fixture directories
- **WHEN** the test runner runs (in either phase)
- **THEN** 18 parameterized test cases SHALL execute, one per fixture directory

#### Scenario: failure diagnostic includes README pointer

- **GIVEN** a fixture `02a-plain-string` whose Phase B normalized output diverges from the golden, and `activatePhaseB == true`
- **WHEN** the test fails
- **THEN** the failure message SHALL contain: the fixture directory name, the phase (`Phase B`), the assertion type (`docx byte-diff`), the paths of both compared files, and a line `See: Tests/OOXMLSwiftTests/Fixtures/mdocx/02a-plain-string/README.md`

<!-- @trace
source: mdocx-fixture-corpus
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093300.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-143733.log
-->