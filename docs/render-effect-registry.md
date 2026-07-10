# Render-Effect Registry

The understanding ledger of the word-imitation line's layer 3
(`docx-render-semantics`, Spectra change `render-effect-semantics`).
Layers 1–2 proved *faithful re-serialization* (raw byte-equal floor, typed
DSL channel); this registry records what the system *understands about
rendering*: a typed payload field is `verified` only while a gated
perturbation probe demonstrates its predicted effect against live Microsoft
Word rendering (design Decision 1 — no probe, no claim).

**Probe protocol** (design Decisions 3–5): build baseline and perturbed docx
via typed operations differing in exactly one field; render both through
Word (`RUN_WORD_INTEGRATION=1`, I/O under the TCC-granted
`~/.cache/ooxml-swift-visual-diff`); measure the observable with
`RenderGeometry` (PDFKit); assert direction exactly and magnitude within
tolerance (±10% or ±1.0 pt, whichever is larger). Run:

```bash
cd packages/ooxml-swift && RUN_WORD_INTEGRATION=1 swift test --filter RenderEffectProbeTests
```

## Registry

Units: twips = 1/20 pt; `sz` in half-points; `spacingLine` with rule `auto`
in 240ths of a single line.

| # | Payload field | Perturbation | Observable | Predicted direction | Expected magnitude | Evidence (measured) | Probe | Status |
|---|---------------|--------------|------------|---------------------|--------------------|---------------------|-------|--------|
| 1 | `SectionPayload.docGridLinePitch` (type `lines`) | 360 → 480 twips | median line pitch, page 1 | increases | +6.0 pt = (480−360)/20 | Δ 6.96 pt (20.88 → 27.84; absolute pitch ≈ nominal ×1.16 in Word's render, delta within tolerance) — 2026-07-10, Word 16.110.3 | `testProbeDocGridLinePitch` | verified |
| 2 | `ParagraphPayload.spacingBefore` | 0 → 240 twips on ¶2 (all other spacing fields pinned to explicit 0) | gap: last line box of ¶1 → first line box of ¶2 | increases | +12.0 pt = 240/20 | Δ 12.0 pt exactly (gap 20.88 → 32.88) — 2026-07-10, Word 16.110.3 | `testProbeSpacingBefore` | verified |
| 3 | `ParagraphPayload.spacingAfter` | 0 → 240 twips on ¶1 (all other spacing fields pinned to explicit 0) | gap: last line box of ¶1 → first line box of ¶2 | increases | +12.0 pt = 240/20 | Δ 12.0 pt exactly (gap 20.88 → 32.88) — 2026-07-10, Word 16.110.3 | `testProbeSpacingAfter` | verified |
| 4 | `ParagraphPayload.spacingLine` (rule `auto`) | 240 → 360 | median line pitch | increases | ×1.5 = 360/240 | ratio 1.507 (pitch 18.0 → 27.12 pt) — 2026-07-10, Word 16.110.3 | `testProbeSpacingLineAuto` | verified |
| 5 | `ParagraphPayload.indentFirstLineChars` | 0 → 100 (1 char) | first-line x-offset vs following lines | shifts right | ≈ run font size in pt (one character advance) | Δ 10.5 pt exactly (= sz 21 half-points → 10.5 pt full-width advance; CJK line detection stable) — 2026-07-10, Word 16.110.3 | `testProbeIndentFirstLineChars` | verified |
| 6 | `RunPayload.sizeHalfPoints` | 21 → 42 | line-box height AND median line pitch | both increase | pitch ≈ ×2 | pitch ratio 2.0 exactly (18.0 → 36.0 pt); line height 11.69 → 23.38 pt — 2026-07-10, Word 16.110.3 | `testProbeSizeHalfPoints` | verified |
| 7 | `SectionPayload` page size + margins | `marginTop` 1440 → 2007 twips (+1 cm) | page box (must not change); y of first line box | box unchanged; first line moves down | box ≈ nominal twips/20 (±0.15 pt, see discovered behavior); Δy = 567/20 = 28.35 pt | box 595.2×841.92 pt unchanged; Δy 28.32 pt — 2026-07-10, Word 16.110.3 | `testProbePageMargins` | verified |

## Probe-discovered behavior (evidence beyond the predictions)

- **Word collapses adjacent before/after spacing (max, not sum).** The first
  spacing-probe run left ¶ spacing to style defaults: adding
  `spacingBefore` 240 to ¶2 moved the gap by only ≈4 pt, because Word took
  max(default `spacingAfter` ≈ 8 pt, new 12 pt) instead of adding them. The
  probe fixture now pins every spacing field to explicit 0 so a perturbation
  is the only difference; the additive prediction then holds exactly.
- **docGrid `lines` renders line pitch at ≈ nominal ×1.16**, not the raw
  twips value (registry #1 evidence: 18 pt nominal → 20.88 pt measured;
  24 → 27.84). Deltas track predictions within tolerance; absolute values
  carry the factor.
- **Word quantizes the A4 page box.** `w:pgSz` 11906×16838 twips renders as
  595.2 × 841.92 pt, not the raw arithmetic 595.3 × 841.9 (registry #7).
  The margin probe's core claim (box unchanged under margin perturbation)
  holds exactly; absolute box size vs nominal carries ±0.15 pt slack.

## Status semantics

- **verified** — the probe passes on the maintainer machine; the Evidence
  column records the measured value, measurement date, and Word version.
  Regression: a later probe failure demotes the row back to `unverified`.
- **unverified** — no passing probe. Either not yet attempted, or the
  documented failure mode prevents a stable measurement (per the spec's
  honest-registry scenario the tolerance is never loosened to force green).

## Boundaries

Word for Mac (AppleScript bridge) is the single rendering oracle — measured
magnitudes are environment-specific evidence, direction predictions are not.
Observables are line/box geometry only; glyph-level semantics (kerning,
ligatures, font fallback) are out of scope, as are cross-renderer oracles
and CI execution (probes skip loudly without the gate or Word).
