## Context

Steps 1–2 of the word-imitation line prove *faithful re-serialization*: #130's raw channel guarantees Stage B byte equality with zero understanding, and #131's typed DSL channel proves the system can spell every byte of the JPA template's document.xml through named operations. Neither gate says anything about what those settings *do* on the page. The visual-diff harness (VisualDiffTests, gated behind `RUN_WORD_INTEGRATION=1`) compares Word-rendered PDFs by per-page pixel ratio — a change detector, not an effect model: it cannot distinguish "line pitch grew by 2pt" from "a paragraph moved".

The slot workflow from #131 makes this gap user-visible: a submission document produced by substituting slot text carries no rendering guarantee. New text could overflow the line grid or re-paginate the document and no acceptance test would notice, because byte-level checks only cover the untouched bytes.

Constraint carried from #130: Word's sandboxed save-as authorization is bound to the fixed directory `~/.cache/ooxml-swift-visual-diff` (a one-time TCC grant). All new probe files MUST be written under that same directory — a new path would re-trigger the blocking Grant Access dialog.

## Goals / Non-Goals

**Goals:**

- Make "the system understands setting X" operational: a render-effect registry entry (observable, direction, expected magnitude, tolerance) verified by a gated perturbation probe against live Word rendering.
- Extend the visual-diff harness with geometry measurement (text-line boxes, page count, page box, derived line pitch) so probes assert *what* changed and *by how much*, not just *that* pixels differ.
- Give slotted rebuilds a render-level acceptance: new slot content must not silently change page count or section geometry.

**Non-Goals:**

- Full effect coverage of every payload field (registry grows entry-by-entry, like DSL vocabulary grew behind the byte-equal gate).
- Cross-renderer equivalence (LibreOffice/Pages/Word-for-Windows); Word for Mac is the single oracle.
- Glyph-level semantics (kerning, ligatures, font fallback) — observables are line/box geometry.
- CI execution of probes (live Word required; loud skip without it).
- Shipping geometry helpers as library API — they live in the test target this change (see Decision 6).

## Decisions

**Decision 1 — Understanding is defined by a probe-verified registry entry.** Mirroring the byte-equal upgrade gate from #130/#131: a claim of understanding is admitted only when demonstrated by a green probe. A registry entry without a green probe is marked *unverified* in the registry table. Alternative rejected: prose documentation of ECMA-376 semantics without measurement — that is transcription of the standard, not verified understanding, and drifts silently when Word's actual behavior differs from the spec.

**Decision 2 — Geometry via PDFKit line selections, not pixel analysis.** `PDFPage.selectionsByLine()` bounds give text-line boxes; median baseline-to-baseline distance is the measured line pitch; page box comes from `PDFPage.bounds(for: .mediaBox)`. Native frameworks only (native-macos-compat: PDFKit is the PDF base layer). Unit-testable without Word on committed PDF fixtures generated via CoreGraphics text drawing. Alternative rejected: raster analysis of pixel rows (fragile against anti-aliasing, cannot name units).

**Decision 3 — Probe fixtures are built from typed operations, not hand-edited XML.** Each probe constructs baseline and perturbed docx via `WordDocument.emptyAuthoringDocument()` + `apply(operations:)`, differing in exactly one payload field. This reuses step 2's vocabulary as the perturbation surface, so a probe simultaneously verifies the reducer's serialization of the field AND its rendering effect. Alternative rejected: string-templated XML fixtures (bypasses the op layer; a probe could pass while the typed op mis-serializes).

**Decision 4 — Word for Mac via the existing AppleScript bridge is the single rendering oracle**, reusing the fixed granted directory `~/.cache/ooxml-swift-visual-diff` for all probe I/O. Expected magnitudes derive from ECMA-376 units (twips = 1/20 pt; `sz` in half-points; `docGrid linePitch` in twips; `spacingLine` with rule `auto` in 240ths of a line), but the *assertion* is against Word's measured output, with the measured value recorded in the registry as evidence.

**Decision 5 — Tolerance policy: direction exact, magnitude within ±10% or ±1.0 pt (whichever is larger).** Rendering involves rounding to device space and Word's own grid snapping; exact-point equality would be flaky. Direction (grew/shrank/moved right) must match the prediction exactly — a direction miss means the effect model is wrong, not noisy. First probe run calibrates each entry's recorded magnitude; subsequent runs regression-pin it.

**Decision 6 — Geometry helpers live in the ooxml-swift test target** (`Tests/OOXMLSwiftTests/Helpers/RenderGeometry.swift`), not library source. No public API surface, no version-bump obligation, no consumers to migrate. Promotion to library API is deferred until a non-test consumer exists (e.g., a future `macdoc word render-check` CLI). Alternative rejected: new Sources module now — YAGNI plus release overhead for test-only capability.

**Decision 7 — Slotted-rebuild render acceptance compares structure, not pixels, where content changed.** Criteria: page count equal; page box equal; measured line pitch on the substituted page within tolerance of the reference page. Pixel-ratio equality applies only to pages with no substituted content. Alternative rejected: whole-document pixel threshold (new text legitimately changes pixels on its page; a threshold loose enough to pass would be too loose to catch drift elsewhere).

## Implementation Contract

**Behavior.** After this change, a maintainer with Word installed can run:
1. `swift test --filter RenderGeometryTests` (no Word, no gate) — geometry extraction verified on committed PDF fixtures: line boxes, page count, page box, median line-pitch computation.
2. `RUN_WORD_INTEGRATION=1 swift test --filter RenderEffectProbeTests` — one probe per registry entry; each renders a baseline and a single-field-perturbed docx through Word, measures the observable, asserts predicted direction and magnitude within Decision 5 tolerance. A failing probe names its registry entry.
3. `RUN_WORD_INTEGRATION=1 MACDOC_TEMPLATE_DIR=<dir> swift test --filter RealTemplateUpgradeTests` — gains scenario (d): the slotted JPA rebuild with sentinel content preserves page count, page box, and substituted-page line pitch versus the reference render.

**Interface / data shape.** Test-target helper `RenderGeometry` exposing: `pageCount(pdf:)`, `pageBox(pdf:page:)`, `lineBoxes(pdf:page:) -> [CGRect]`, `medianLinePitch(pdf:page:) -> CGFloat?`. Registry document `docs/render-effect-registry.md`: one table row per entry — payload field, observable, predicted direction, expected magnitude (with unit conversion), tolerance, measured evidence (value + date), probe test name, status (verified/unverified).

**Failure modes.** Probes and the acceptance scenario skip loudly (XCTSkip) without `RUN_WORD_INTEGRATION=1`, without Word, or (for the template scenario) without `MACDOC_TEMPLATE_DIR`. `medianLinePitch` returns nil for pages with fewer than 2 text lines; probes MUST fail (not skip) on nil for pages designed to have text.

**Acceptance criteria.** All three invocations above green on the maintainer machine; registry has ≥6 verified starter entries (docGridLinePitch, spacingBefore/After, spacingLine-auto, indentFirstLineChars, sizeHalfPoints, page size/margins); `docs/format-alignment-baselines.md` gains a render-semantics section; delta specs applied for `docx-render-semantics` (new) and `docx-visual-diff-testing` (modified).

**Scope boundaries.** In: geometry helpers (test target), starter registry + probes, slotted-rebuild render acceptance, docs. Out: library API, CLI subcommands, CI execution, non-starter registry entries, thesis-fixture structures, cross-renderer oracles.

## Risks / Trade-offs

- [Word rendering nondeterminism (font availability, version differences) makes magnitudes machine-dependent] → registry records evidence with environment note (Word version); tolerance policy absorbs device-space rounding; direction assertions are environment-independent.
- [`selectionsByLine()` merges or splits lines unexpectedly on grid-snapped CJK text] → RenderGeometryTests pin behavior on committed fixtures first; if line detection proves unstable for a probe, that entry stays *unverified* with the failure mode documented rather than loosening tolerance to force green.
- [Probe suite runtime (2 Word renders per entry × 7 entries)] → probes share one Word session per test run (existing harness pattern); acceptable for a gated maintainer-only suite.
- [New files under a different directory re-trigger Word's sandbox Grant Access dialog] → all probe I/O uses the already-granted `~/.cache/ooxml-swift-visual-diff`; pinned in a helper constant.

## Migration Plan

Test-target and documentation change only: no library API, no version bump, no downstream consumers. Land in ooxml-swift as test additions (RenderGeometry helper + two test files + RealTemplateUpgradeTests extension); macdoc side is docs only (registry + baselines + CLAUDE.md note). Nothing to roll back beyond reverting the commits.

## Open Questions

- None blocking. Magnitude calibration values for each registry entry are measured at first probe run (Decision 5) rather than predicted a priori.
