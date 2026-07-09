## Context

format-alignment-engine (#130, archived 2026-07-08) shipped the dual-track pipeline: raw channel = byte-equal floor (Stage B green on all fixtures including real Word documents), typed DSL channel = imitation score gated by trial-rebuild byte equality (Decision 3: a content class upgrades only when `apply(ops)` → serialize reproduces the source bytes exactly; no canonical-form exemptions). Measured baselines (docs/format-alignment-baselines.md): authoring-built synthetic 57.5% DSL, all Word-authored documents 0.0% — `ReverseExtractor` bails on Word's XML forms before the trial even runs. Known bail classes on `90_template_ja.docx`: root element carries ~15 namespace declarations + `mc:Ignorable` (extractor requires exactly the 2-namespace root that `emptyAuthoringDocument` emits), every `<w:p>` carries rsid attributes (extractor requires exactly one `w14:paraId` attribute), `<w:t>` may carry `xml:space="preserve"`, and rPr/pPr carry long-tail elements (szCs, rFonts hint/hAnsi/cs, lang). This change extends the vocabulary so the gate can pass on real documents; the gate itself is untouched.

## Goals / Non-Goals

**Goals:**

- `90_template_ja.docx` document.xml upgrades to the DSL channel (per-part coverage 100%, aggregate = document.xml bytes ÷ total XML bytes) and `--slot` works on it end-to-end (title/body scenario with new content, formatting intact).
- A form-gap report that names the exact first-bail path (element/attribute) per document, so vocabulary work is measurement-driven, not guesswork.
- Stage A/B stay green throughout (existing guard tests extended per new upgrade class).
- Wire compat: all payload extensions additive (#128 discipline); v1.x JSONL sidecars decode unchanged.

**Non-Goals:**

- thesis-fixture full upgrade (comments/bookmarks/headers structures — measurement + no-regress sanity only).
- Sibling-part (styles/settings/numbering) typed channel — later phase.
- Any weakening of the byte-equal gate to inflate coverage.
- Word version compatibility matrix / corpus collection beyond the two gated real documents + committed synthetic fixture.

## Decisions

### Decision 1: Form-gap report is the work queue, not documentation

`ReverseExtractor`'s `Unsupported` bail carries only a class tag today. Extend it to carry a structured gap record: part path, XML path to the first offending node (e.g. `w:document/@mc:Ignorable`, `w:body/w:p[3]/@w:rsidR`, `w:p[7]/w:pPr/w:widowControl`), and the class tag. `FormGapReport` aggregates records per document (first-bail only per extraction attempt — the extractor stops at the first unsupported form; iterating requires re-running after each fix, which is exactly the intended workflow loop). Rationale: the long tail is unbounded; without measurement the change cannot honestly claim "done when 90_template_ja upgrades" — the report defines the remaining work at every point.

### Decision 2: Document root rides a typed op, not a carryPart special case

New op `setDocumentRoot(attributes: [RootAttribute])` where `RootAttribute {prefix, localName, value}` preserves declaration order. Reducer replaces the root element's attribute list wholesale (order-preserving stamping); `emptyAuthoringDocument` keeps its minimal 2-namespace default so all existing behavior is unchanged when the op is absent. Extraction emits the op first (before any paragraph ops) when the reference root differs from the default. Rejected alternative — parameterizing `emptyAuthoringDocument(rootAttributes:)`: the rebuild path is `script → ops → apply`, so root state must travel inside the op stream to survive script round-trip; a constructor parameter would need a side channel.

### Decision 3: rsid fields are opaque strings, stamped in Word's attribute order

`ParagraphPayload` gains `rsidR/rsidRDefault/rsidP/rsidRPr: String?`; `RunPayload` gains `rsidR/rsidRPr/rsidDel: String?` (exact field set confirmed against the form-gap report in the first task; add only what the corpus needs). Reducer stamps them as attributes on `<w:p>`/`<w:r>` in the order Word emits (observed order captured in the report; `w:rsidR` before `w:rsidRDefault` etc.). They are never interpreted — pure round-trip freight. Rationale: rsids are revision-session bookkeeping with no semantic value to the DSL, but they gate byte equality on virtually every Word paragraph.

### Decision 4: Long-tail vocabulary lands one class at a time behind the existing gate

Each new rPr/pPr/sectPr element follows the Phase B pattern: payload field (additive) → reducer stamping in schema order → extraction recognition → UpgradeClassGuardTests entry. The order of classes is dictated by the form-gap report on 90_template_ja (re-run after each landing; the report shrinks monotonically). No class is special-cased in the serializer: if a form cannot re-serialize byte-equal (e.g. unusual attribute order within an element), it stays raw and the report keeps naming it.

### Decision 6: Inline-interleaved markers ride an opaque passthrough op (added task 1.2, user scope decision 2026-07-09)

The task 1.2 measurement revealed 90_template_ja's document.xml carries `bookmarkStart`/`bookmarkEnd`/`proofErr` — elements interleaved between `<w:r>` siblings inside paragraphs. The five-layer model ("paragraph = optional pPr + a run sequence") cannot represent them, and because the upgrade gate is per-part all-or-nothing, their presence pins the whole document.xml at 0%. Rather than model each marker semantically (unbounded), a single bounded mechanism: paragraph inline content becomes an ordered sequence of items, each either a run OR an **opaque inline passthrough** carrying the marker element's verbatim serialized bytes. Extraction records passthrough items in position; the reducer stamps them back verbatim between runs; byte equality holds because the exact source bytes are reproduced (Decision 3 unchanged — this is a carry, not a re-serialization). This covers bookmarks + proofErr and any future inline marker (commentRangeStart/End, etc.) without per-marker work. It does NOT cover inline content that is not a self-contained leaf/paired marker — `hyperlink` (wraps runs), `drawing`/`oMath`/`fldChar`/`sdt` (thesis-fixture's structures) stay out of scope (Non-Goals). The mechanism is a new op (`appendInlineMarker` or an additive field on the run sequence); exact shape decided at implementation behind the existing trial-rebuild gate.

### Decision 5: Acceptance is two-track per #131 Clarity Surface row 1

(a) Functional: `RealTemplateUpgradeTests` (env-gated) asserts `dslParts` contains word/document.xml for 90_template_ja AND a slotted script with new title/body content executes to a docx whose non-slot parts byte-match and whose formatting survives. (b) Numeric: per-part coverage for document.xml = 100% (dslBytes == totalBytes for that part). No aggregate-percentage threshold is pinned — aggregate follows arithmetically and honestly reflects raw siblings.

## Implementation Contract

**Behavior**: `macdoc word reverse` (default full-fidelity mode, unchanged CLI surface) on a Word-authored docx whose document.xml uses only the supported vocabulary now emits typed ops for document.xml instead of a carryPart blob; `--coverage` shows `word/document.xml  dsl … DSL 100.0%`; `--slot name=paraId` works on such documents. Documents with still-unsupported forms behave exactly as today (raw fallback, Stage B green), with the gap report available to tests.

**Interface / data shape**:
- `ReverseExtractor.Result` gains `formGaps: [FormGap]` where `FormGap {partPath: String, xmlPath: String, contentClass: String}` (empty when upgraded).
- New op `Operation.setDocumentRoot(attributes: [RootAttribute])`; `RootAttribute {prefix: String?, localName: String, value: String}` — Codable, order-significant array. JSONL discriminator `setDocumentRoot`, field `attributes`.
- `ParagraphPayload`/`RunPayload` additive optional fields per Decision 3; `RunPayload.preserveSpace: Bool?` ↔ `xml:space="preserve"` on `<w:t>`.
- Operation taxonomy grows 35 → 36 (setDocumentRoot); OperationLogTests/ScriptTranscodeTests pins updated.

**Failure modes**: unsupported forms never error — they bail to raw channel with a FormGap record (surfaced, not silent). `setDocumentRoot` applied to a document whose root is absent throws `ReducerError.malformedOp` (reducer never swallows). Old JSONL decodes with new fields absent (additive discipline); unknown `setDocumentRoot` on old binaries round-trips via the `.unknown` fallback.

**Acceptance criteria**:
1. `RealTemplateUpgradeTests` (MACDOC_TEMPLATE_DIR-gated): 90_template_ja upgrades, slot round-trip with new content passes, per-part document.xml coverage 100%.
2. thesis-fixture: extraction does not regress (still Stage B green raw fallback); its form-gap report is recorded in the baselines doc.
3. Full ooxml-swift suite green including every existing guard test; new upgrade classes each pinned in UpgradeClassGuardTests.
4. docs/format-alignment-baselines.md updated with post-change measured coverage for all four fixtures.

## Risks / Trade-offs

- **Attribute-order dependence**: Word's attribute order within an element is stable in practice but unspecified; if a corpus document deviates, that element stays raw (report names it). Mitigation: order is captured per-element from measurement, not assumed.
- **rsid explosion on wire**: every paragraph gains up to 4 optional string fields; JSONL lines grow. Accepted — sortedKeys encoding keeps it deterministic, and absent fields cost nothing.
- **Fixture privacy**: 90_template_ja stays env-gated (Decision 5 of #130); tests print byte counts and coverage only, never content. The baselines doc references the fixture by name, not by local path (#132).

## Migration Plan

Additive throughout; no breaking release. ooxml-swift minor bump (v1.4.0) when the change completes; macdoc bumps its dependency and gains no new CLI flags (existing `--slot`/`--coverage` just start working on real documents). Cross-major stale-artifact caution: run swift package clean in macdoc after the bump (payload struct layouts change).

## Open Questions

- **Q1**: Does 90_template_ja's document.xml contain any element the five-layer vocabulary cannot represent even in principle (e.g. field codes, smartTag)? *RESOLVED (task 1.2, 2026-07-09)*: it carries `bookmarkStart`/`bookmarkEnd`/`proofErr` — inline-interleaved markers the five-layer model doesn't structurally handle (though not opaque like thesis-fixture's drawing/oMath/fldChar). Escalated to the user per this clause; user chose to extend scope with the inline-passthrough mechanism (Decision 6) so the real template reaches full upgrade. Everything else 90_template_ja uses is attribute/companion-level (rsid family, root namespace cloud, xml:space, font themes, bCs/iCs/szCs, docGrid) — within the original scope.
- **Q2**: rsid field set — exact list to add. *Working answer*: decided by the first form-gap report; Decision 3 names the likely set.
