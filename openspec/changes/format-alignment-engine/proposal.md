## Why

Given a reference docx, the user wants a **single pipeline** that reverse-engineers it into an executable rebuild script and regenerates the file — with **byte-equal output** as the acceptance bar ("我要看的是你仿作的能力", PsychQuant/macdoc#130). This is Word template induction: extract page/paragraph/run/table/structural formatting into a reusable template form, then align new content into that form.

macdoc already ships the skeleton (word-aligned-state-sync, archived 2026-07-06): `macdoc word reverse` produces `.mdocx.swift` scripts, the WordDSLSwift runtime rebuilds docx files, and the tree layer is byte-faithful. But the measured baseline on the real-world Japanese academic template (`90_template_ja.docx`) shows the gap: 96/96 paragraphs project to DSL form, yet only text + styleId survive — run/paragraph/section formatting is dropped and 12 of 13 XML parts never enter the script.

## What Changes

Per the five confirmed discuss decisions (#130):

1. **Dual-track acceptance architecture**: a raw byte channel (script carries verbatim part bytes) makes byte-equal rebuild pass from day 1 and becomes a never-regress floor; a typed DSL channel is upgraded layer by layer, measured as **DSL-form coverage %** (the real "imitation ability" score). Every raw→DSL upgrade must keep byte-equal green.
2. **Acceptance stages**: Stage A = per-part XML byte-equal; Stage B = full part-set byte-equal (final acceptance); Stage C (zip container byte-equal) is **exempted** by decision (zip library internals; Word itself does not zip-byte-equal on resave).
3. **Four phases in one change**: A metrics foundation → B five-layer extraction → C all-parts channel → D content slots + visual diff.
4. **Template fixtures**: gitignored `test-files/templates/` for real documents (env-gated, privacy-safe for the public repo), plus one **committed synthetic CJK two-column template** so CI can run the pipeline.
5. **Visual diff channel**: Word AppleScript PDF export (gated behind `RUN_WORD_INTEGRATION`, following the live round-trip test precedent; no LibreOffice dependency).

## Non-Goals

- Inferred template mode (automatic structural-role deduction) — deferred; strict template mode ships first per the source discussion.
- Stage C zip-container byte equality — exempted by discuss decision 1.
- Editing/sync features — this change is the reverse+rebuild pipeline only; bidirectional sync already shipped in word-aligned-state-sync.
- LibreOffice-based PDF conversion — rejected in favor of Word AppleScript export (native-macos-compat).

## Capabilities

### New Capabilities

- `format-alignment-pipeline`: the single-path contract — reverse → script → rebuild → byte-equal; dual-track acceptance (byte-equal floor + DSL coverage metric); stage definitions and the Stage C exemption; template fixture policy.
- `template-content-slots`: strict template mode — parameterize a rebuild script with named content slots so new content aligns into the extracted format.
- `docx-visual-diff-testing`: gated visual regression harness — docx → PDF via Word AppleScript export → image comparison.

### Modified Capabilities

- `ooxml-script-transcode`: all-parts raw channel (sibling parts ride the script verbatim), DSL-form coverage measurement, and reverse extraction deepened across the five format layers.
- `ooxml-operation-log`: additive payload extensions (run-level formatting fields, paragraph spacing/indent/numbering fields, section properties payload) per the #128 additive-only discipline.

## Impact

- Affected specs: `format-alignment-pipeline` (new), `template-content-slots` (new), `docx-visual-diff-testing` (new), `ooxml-script-transcode` (modified), `ooxml-operation-log` (modified)
- Affected code:
  - New: `packages/ooxml-swift/Sources/OOXMLSwift/Transcode/PartFidelity.swift` (byte-diff + coverage metrics), `packages/ooxml-swift/Tests/OOXMLSwiftTests/FormatAlignmentBaselineTests.swift`, `Tests/MacDocCLITests/Fixtures/CJKTemplateFixtureGenerator.swift` (synthetic committed template), `packages/ooxml-swift/Tests/OOXMLSwiftTests/VisualDiffTests.swift`
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Transcode/ScriptTranscoder.swift` (all-parts channel + five-layer projection), `packages/ooxml-swift/Sources/OOXMLSwift/OpLog/Operation.swift` (payload additive fields), `packages/ooxml-swift/Sources/OOXMLSwift/OpLog/OperationLog+JSONL.swift`, `packages/ooxml-swift/Sources/OOXMLSwift/OpLog/OperationReducer.swift`, `packages/ooxml-swift/Sources/WordDSLSwift/WordDocument.swift` (slot parameterization), `Sources/MacDocCLI/MacDoc+Word.swift` (reverse depth options)
  - Removed: (none)
