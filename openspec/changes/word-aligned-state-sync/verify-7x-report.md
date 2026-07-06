# 7.x Release verifies — working report（2026-07-06）

Panel per tag: 2 Claude reviewers (sonnet; correctness + spec-conformance) + 1 Codex (gpt-5.5 xhigh).
**Degradation record**: all 6 Codex runs hit OpenAI usage limit (resets 20:48); 9 of 12 Claude
reviewers hit the account session limit (resets 21:00 Asia/Taipei). Completed before the wall:
v30-spec, v32-spec (full reports), v30-correctness (report requested). Remaining 9 + codex
re-run after reset.

## Status

| Round | Tag | correctness | spec-conformance | codex |
|-------|-----|-------------|------------------|-------|
| 7.1 | v0.30.0 | ✅ CONCERNS（3 real defects — **fixed in v1.0.1**）| ✅ CONCERNS | ⏳ limit, re-run |
| 7.2 | v0.31.5 | ⏳ limit | ⏳ limit | ⏳ limit |
| 7.3 | v0.32.0 | ⏳ limit | ✅ CONCERNS | ⏳ limit |
| 7.4 | v0.33.1 | ⏳ limit | ⏳ limit | ⏳ limit |
| 7.5 | v0.34.1 | ⏳ limit | ⏳ limit | ⏳ limit |
| 7.6 | v1.0.0 | ⏳ limit | ⏳ limit | ⏳ limit |

## Findings so far

### v0.30.0 correctness — CONCERNS → 3 real defects, FIXED in v1.0.1（same day）

1. **[P1] Unbounded parse recursion** — 60k-level nesting empirically SIGSEGVed (uncatchable);
   primary parse path, DoS surface for consumers opening third-party docx.
   → Fixed: depth guard (limit 1024) throwing catchable `nestingTooDeep`.
2. **[P2] UTF-8 BOM unfhandled** — BOM-prefixed parts (LibreOffice et al.) failed the whole parse.
   → Fixed: BOM skip in skipProlog.
3. **[P2] Attribute control chars unescaped** — literal \n/\r/\t pass through; conformant
   readers (libxml2 — which the v1.0 read projection feeds) normalize to spaces, corrupting
   values on dirty re-serialize. → Fixed: character-reference escaping (&#10;/&#13;/&#9;).
4. [P3] Test file hardcoded a personal path to a third party's thesis (privacy + CI).
   → Fixed: env-gated (OOXML_LOCAL_THESIS_FIXTURE) + XCTSkip.
5. [Info] CDATA collapses to text-kind on dirty re-emit (contract not violated; noted).
6. [Info] deepClone marks all nodes dirty → clone→serialize canonicalizes empty-tag forms
   (design consequence, noted for reducer awareness).

Verified sound by the same panel: entity round-trip, attribute order, namespace scoping,
comment/PI, mixed content, empty-tag forms on clean nodes, subtree-dirty propagation,
fingerprint canonicalization, DTD byte-skip (no XXE).

All fixes shipped as **ooxml-swift v1.0.1** (4 new pinning tests; 1178 green).

### （doc/test-coverage class findings）

### v0.30.0 spec-conformance — CONCERNS

1. **[P1] Golden-corpus acceptance criteria never met as written** — ooxml-tree-io spec names
   committed fixtures (multi-section-thesis 3×sectPr, vml-rich with mc:AlternateContent, …) and
   byte-equal assertions on header*/footer*/[Content_Types].xml. Reality: programmatic builders
   (CorpusFixtureBuilder), 2×sectPr, zero AlternateContent, header/footer/Content_Types never
   byte-equal-asserted. Persisted unchanged v0.30.0→v1.0.0. (Consistent with the task-1.8
   overmark disclosed during the apply phase.)
2. **[P1] Task 2.4 overmarked** — "SectionProperties tree-backed view verified against
   multi-section-thesis" — no test connects SectionPropertiesTreeProjectionTests (synthetic
   nodes only) to that fixture; the matching-named test file at v0.31.0 was an XCTSkip stub
   from an unrelated change.
3. [P2] Tree reader/writer never exercised against header*/footer* parts in any fixture test
   (customXml covered since v0.31.5).
4. [P2] Fingerprint attribute identity keyed by (localName, prefix), not resolved URI —
   contradicts spec's literal "prefix variations on same URI" scope for attributes
   (self-documented in code comment).
5. [P3] API naming drift (spec prose: read/write/id; shipped: parse/serialize/stableID).
6. [P3] "Pure-Swift" requirement has no automated pin (manual dependency check only).

Clean/well-pinned: lossless tree (mixed content/comments/PIs/entities), untouched-subtree
identity, stableID, text-as-child; byte-faithful design wording already correctly hedged.

### v0.32.0 spec-conformance — CONCERNS

1. **[P1] Taxonomy count drift in archived spec** — `openspec/specs/ooxml-operation-log/spec.md`
   still says "21 cases"; reality: 24 at v0.32.0 (Phase 2c +3), 32 at v1.0.0 (§4b +8). Spec
   never updated as additive extensions landed.
2. **[P2] Change delta spec's JSONL prose stale** — describes `timestamp`/nested `payload`/
   snake_case op_types; shipped wire (and archived spec) is flat `ts`/`op_id`/`source`/`op_type`
   with camelCase. Never reconciled.
3. [P3] Delta/tasks ElementID chain prose omits `w:bookmarkId` step (code + archived spec have it).
4. [P3] Reducer spec Purpose wording implies later shipping; actually shipped in v0.32.0.

Clean: sidecar stem naming exact per spec; tasks.md section 3 spot-check — no overmarking;
reducer + JSONL codec match archived normative spec.

## Disposition queue（fix after panel completes）

- Fix archived op-log spec case-count (scope as baseline + pointer to additive extensions).
- Reconcile change delta JSONL/ElementID prose with shipped wire.
- Golden-corpus spec: reword to programmatic-builder reality OR expand corpus
  (AlternateContent + header/footer round-trip + Content_Types assertion — small test adds).
- tasks.md 2.4 annotation (overmark correction).
