## Why

The word-imitation line has landed two layers: #130 format-alignment-engine (step 1 — copying: the raw channel guarantees a byte-equal floor with zero understanding) and #131 word-canonical-forms (step 2 — legitimate serialization: real Word documents' document.xml rebuilds from typed operations, proven by the trial-rebuild byte-equal gate). Both gates prove *faithful re-serialization*, not *rendering comprehension*: the system can spell `docGrid linePitch="286"` but has no model of what that value does to line spacing on the page. The existing visual-diff harness (Word → PDF → per-page pixel ratio) is an independent regression check, not part of the acceptance semantics, and pixel ratios can only say "something changed" — they cannot say *what* changed or *by how much*.

This third layer makes "understanding a setting" operational and testable: the system understands a setting when it can predict a measurable rendering consequence of changing that setting, and a gated probe verifies the prediction against actual Microsoft Word rendering. Without this layer, slot-substituted documents (the submission-document workflow from #131) carry no rendering guarantee: new slot text could overflow a line grid or shift pagination and nothing in the acceptance would notice.

## What Changes

1. **Geometry measurement in the visual-diff harness** — the harness gains PDF geometry extraction on top of pixel ratios: per-page text-line boxes (baseline positions and heights via PDFKit line selections), page count, page box, and derived observables (median baseline-to-baseline distance = measured line pitch; first-line x-offset; text-area bounds). Native frameworks only (PDFKit/CoreGraphics), unit-testable on committed PDF fixtures without Word.
2. **Render-effect registry** — a documented table mapping typed payload fields to predicted rendering effects (observable, direction, expected magnitude with unit conversion, tolerance). Starter set = the vocabulary the JPA template actually exercises: `SectionPayload.docGridLinePitch`, `ParagraphPayload.spacingBefore`/`spacingAfter`, `ParagraphPayload.spacingLine` (auto rule), `ParagraphPayload.indentFirstLineChars`, `RunPayload.sizeHalfPoints`, and `SectionPayload` page size/margins. Each entry carries measured evidence from a probe run; an entry without a green probe is marked *unverified* — the registry never claims understanding it has not demonstrated.
3. **Perturbation probes** (gated behind `RUN_WORD_INTEGRATION=1`) — for each registry entry, a probe builds a minimal baseline docx via typed operations, perturbs exactly one setting, renders both through live Word, measures the observable, and asserts the predicted direction and magnitude within tolerance. A probe failure names the registry entry.
4. **Rendering acceptance for slotted rebuilds** — the slot workflow gains a render-level acceptance scenario (env-gated + Word-gated): executing the slotted JPA-template script with new content SHALL preserve page count and section geometry (page box, margins, measured line pitch) relative to the reference; pixel equality is required only where content is untouched.

## Non-Goals

- Full effect coverage of all 38 operations / every payload field — the registry grows entry-by-entry behind the probe gate, exactly as DSL vocabulary grew behind the byte-equal gate.
- Cross-renderer equivalence (LibreOffice, Pages, Word for Windows) — Word for Mac via the existing AppleScript harness is the single rendering oracle.
- Text-shaping-level semantics (kerning, ligatures, font fallback) — observables are line/box geometry, not glyph rasterization.
- thesis-fixture's out-of-scope structures (drawings, math, textboxes) — same Non-Goal boundary as #131.
- Making rendering probes run on CI — they require live Word and skip loudly without it, same policy as the existing harness.

## Capabilities

### New Capabilities

- `docx-render-semantics`: operational definition of rendering understanding — a render-effect registry whose entries are each verified by a gated perturbation probe, plus render-level acceptance for slotted rebuilds.

### Modified Capabilities

- `docx-visual-diff-testing`: harness extends from pixel-ratio comparison to geometry measurement (text-line boxes, page count, page box, derived line pitch) usable by probes and acceptance tests.

## Impact

- Affected specs: `docx-render-semantics` (new), `docx-visual-diff-testing` (modified)
- Affected code:
  - New: packages/ooxml-swift/Tests/OOXMLSwiftTests/Helpers/RenderGeometry.swift, packages/ooxml-swift/Tests/OOXMLSwiftTests/RenderGeometryTests.swift, packages/ooxml-swift/Tests/OOXMLSwiftTests/RenderEffectProbeTests.swift, docs/render-effect-registry.md
  - Modified: packages/ooxml-swift/Tests/OOXMLSwiftTests/VisualDiffTests.swift, packages/ooxml-swift/Tests/OOXMLSwiftTests/RealTemplateUpgradeTests.swift, docs/format-alignment-baselines.md, CLAUDE.md
  - Removed: (none)
