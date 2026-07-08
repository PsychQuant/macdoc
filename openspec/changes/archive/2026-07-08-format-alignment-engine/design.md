## Context

The user's acceptance bar for the format-alignment pipeline is byte-equal rebuild ("我要看的是你仿作的能力", #130). Byte equality has a trivial solution — carry every part as a verbatim blob (copying, not imitation) — so the design must separate "output is correct" from "output was understood". word-aligned-state-sync (archived 2026-07-06) supplies the substrate: `macdoc word reverse`, the `.mdocx` transcoder with its `// @op` raw escape, the WordDSLSwift rebuild runtime, and a byte-faithful tree layer. Measured baseline on `90_template_ja.docx`: 96/96 paragraphs in DSL form but only text+styleId extracted; 12 of 13 parts absent from the script.

## Goals / Non-Goals

**Goals**
- One pipeline: `reference.docx → word reverse → script → execute → rebuilt.docx`, byte-equal at the part-set level (Stage B).
- A truthful imitation metric (DSL-form coverage %) that can only improve, never fake.
- CI-runnable fixtures despite the real templates being private documents.

**Non-Goals**: inferred template mode; Stage C zip-container equality; LibreOffice; any editing/sync surface.

## Decisions

### Decision 1: Stage C exemption — Stage B is the final acceptance

Zip-container byte equality is exempted (discuss decision, #130). Entry order, compression parameters, and timestamps are zip-library internals; Word itself does not produce zip-byte-equal output on a no-op resave. Acceptance stages: **Stage A** per-part XML byte-equal (per-part comparison of every XML part); **Stage B** full part-set equality (every part present and byte-equal, including rels and [Content_Types].xml) — final; **Stage C** documented as explicitly out of contract.

### Decision 2: Dual-track — raw channel is the floor, DSL coverage is the score

The rebuild script has two carrying channels:

```
reference.docx
   │  word reverse
   ▼
script (.mdocx.swift)
   ├── DSL channel:   Paragraph(id:…, style:…) { … }     ← semantic, upgradeable
   └── raw channel:   part-blob / // @op verbatim bytes   ← byte-exact, always available
   │  execute
   ▼
rebuilt.docx  ═ byte-equal (Stage A/B) ═  reference.docx
```

Phase A lands the raw channel for all parts first, so Stage A/B pass from day 1 (the honest "copy" baseline). Every later phase upgrades one content class from raw to typed DSL; byte-equal must stay green across every upgrade (regression floor). **DSL-form coverage % = bytes rebuilt via the DSL channel ÷ total XML bytes** — the imitation-ability score that motivated the feature. The metric is reported per part and aggregated.

### Decision 3: Typed-DSL byte equality is achieved via write-back projection, not canonical exemptions

For content upgraded to the DSL channel, byte-equal is preserved by the same mechanism the v1.0 IO surgery proved: serializer output is the only path to disk, and clean-node blob-copy keeps untouched bytes verbatim. Where a typed re-serialization would differ benignly (attribute order, empty-element form), the upgrade is only accepted when the serializer reproduces the source form — no canonical-form exemption clause is introduced. If a content class cannot reach byte-exact typed re-serialization, it stays on the raw channel and the coverage metric honestly reflects that. This keeps Stage A/B binary (no fuzzy pass), at the cost of slower coverage growth.

### Decision 4: One change, four phases

A(metrics foundation: PartFidelity byte-diff + coverage instrument + baseline record) → B(five-layer extraction: run/paragraph/section payload additive extensions + reverse deepening) → C(all-parts channel: styles/settings/theme/fontTable/rels ride the script) → D(content slots + visual diff). Single change follows the word-aligned-state-sync precedent — the phases have hard ordering dependencies (cannot measure coverage without A; cannot upgrade without B's payloads; slots need C's complete rebuild).

### Decision 5: Fixture policy — private real templates env-gated, one synthetic committed

`test-files/templates/` (already-gitignored tree) holds real reference documents; tests resolve them via `MACDOC_TEMPLATE_DIR` env-gate with `XCTSkip` fallback (the `OOXML_LOCAL_THESIS_FIXTURE` precedent from v1.0.1's privacy fix). One **synthetic CJK two-column template** is generated programmatically (`CJKTemplateFixtureGenerator`, following `NoteFixtureGenerator`) and exercised in CI — it reproduces the structural features of `90_template_ja.docx` (two sections with `w:cols num="2"`, CJK fonts incl. eastAsia, multiple styles, settings surface) without shipping anyone's document.

### Decision 6: Visual diff via Word AppleScript PDF export, gated

`docx → PDF` uses live Microsoft Word driven by osascript (`save as PDF`), gated behind `RUN_WORD_INTEGRATION=1` exactly like WordLiveRoundTripTests. Comparison renders PDF pages to bitmaps (CoreGraphics/PDFKit — native, per native-macos-compat) and computes a per-page pixel-difference ratio against a threshold. LibreOffice rejected: external dependency plus a different layout engine produces diff noise unrelated to document content.

## Risks / Trade-offs

- **Byte-exact typed re-serialization is demanding** (Decision 3): some classes (e.g., rsid-bearing attributes with interleaved order) may resist DSL upgrade for a long time. Mitigation: the coverage metric makes this visible instead of blocking; raw channel keeps correctness.
- **Payload additive growth** widens the JSONL wire; every new field must respect the #128 additive-only discipline and the envelope-key collision rule (v1.0.2 lesson: field names must not collide with op_id/ts/source/op_type).
- **rels/Content_Types on the raw channel** interacts with the known rels double-truth follow-up (verify-7x register #1); Phase C sequences the script channel first and defers rels tree-first unification to that register item.
- **Visual diff thresholds are heuristic** — the Residue in #130's diagnosis stands: aesthetic judgment is approximated, not captured.

## Migration Plan

Additive throughout — no breaking releases. ooxml-swift minor bumps per phase (v1.1.0 metrics+raw channel, v1.2.0 extraction, v1.3.0 slots); macdoc CLI gains flags without changing existing `word reverse` defaults until Phase C completes, then full-fidelity becomes the default with `--paragraphs-only` opt-out.

## Open Questions

- **Q1**: Coverage denominator — total bytes of all XML parts, or document.xml only for the headline number? *Working answer*: aggregate over all XML parts, with per-part breakdown; headline = aggregate.
- **Q2**: Slot syntax in the script — Swift function parameters vs `{{placeholder}}` string markers? *Working answer*: Swift parameters (type-safe, fits mdocx grammar's no-raw-string discipline); decided at Phase D task time.
