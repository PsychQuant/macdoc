## Context

Slot designation today has two forms, both anchored to paragraph-granular ops in the OperationLog: DSL-form slots (script-text parameters on DSL-spellable paragraphs) and op-level slots (`// @slot <name> <paraId>` directives substituting into a paragraph's `setRuns`/`appendParagraph` op). A table-bearing document fails the DSL upgrade trial in `ReverseExtractor.documentUpgrade`, so its entire `word/document.xml` enters the log as a single `.carryPart(partPath:xml:)` op. No paragraph-level ops exist; `ScriptExporter.exportSwift(log:slots:)` scans only `.appendParagraph` entries, so every slot designation on such a document fails with `no body paragraph with id ... in the log` — even though the paraId is present inside the carryPart XML string.

Official forms (the flagship swiftify use case) almost always contain tables, so the flagship scenario fails on its most typical input. The `template-content-slots` spec's existing requirement does not exempt raw-channel documents, and the swiftify SKILL.md promises raw-channel slot support. A caller-side Python workaround (run-level XML surgery on the REC amendment form) has already proven the substitution semantics viable. (PsychQuant/macdoc#171)

Constraints: the reverse-side byte-equal upgrade gate is the foundation of the whole closed loop and must not change; the existing `--verify-against` byte-equal acceptance must keep working for slotted raw-channel scripts without a new verification mode.

## Goals / Non-Goals

**Goals:**

- Slot designation by paraId works on documents whose `word/document.xml` rides the raw channel (CLI `--slot` and, by code-path parity, MCP `export_script(slots:)`).
- A slotted raw-channel script executed with all-default values reproduces the reference byte-equal — the existing `--verify-against` gate passes unchanged.
- Substituted values replace the designated paragraph's text while preserving the paragraph's pPr and the dominant run's rPr; everything outside the designated paragraphs stays byte-identical.
- Failure modes are loud and specific: unknown paraId now distinguishes "not in DSL log AND not in raw XML" and hints at the raw-channel cause; duplicate paraId occurrences in the blob refuse rather than guess.

**Non-Goals:**

- No changes to `ReverseExtractor` / the DSL upgrade gate (no partial upgrade of raw parts).
- No run-diff mapping to preserve intra-paragraph run formatting across substitution (collapse-to-dominant-run is the accepted semantic for form filling).
- No raw-channel slots on parts other than `word/document.xml` (headers/footers deferred until a real need).
- No style-based selectors for raw-channel slots (paraId only).
- No independent MCP-side changes (`che-word-mcp-script-pipeline-tools` parity rides the shared transcoder entry points).

## Decisions

1. **Validation fallback in `exportSwift`, not reverse-side upgrade.** When the `.appendParagraph` scan misses, scan the `word/document.xml` carryPart XML for `w14:paraId="<id>"`. Why: touching `documentUpgrade` risks the byte-equal foundation for every document, slotted or not; the fallback is scoped to slot designation only.
2. **Directive representation extends the existing mechanism: `// @slot-raw <name> <paraId>`.** Why: op-level slots already established the directive + pre-pass-parse pattern (`// @slot`); a parallel directive reuses the parser shape and keeps the script format self-describing. A header-JSON slot table was rejected as a structural departure.
3. **Substitution is run-level surgery at import/execute time.** Locate the paragraph by paraId inside the blob, keep its pPr, take the rPr of the dominant text run (longest text), and collapse the paragraph's text to a single `<w:t xml:space="preserve">` run. Why: proven by the caller-side Python workaround on a real official form; run-diff preservation adds large complexity with no form-filling benefit. Substituting at export time was rejected because changing a slot value must not require re-export.
4. **Default identity shortcut.** The exported default for a raw-channel slot is the paragraph's concatenated `<w:t>` text. At execute time, if the provided value equals the default, the blob is left untouched entirely. Why: this makes all-default replay bit-identical by construction, so the existing byte-equal verification applies with zero changes — the same contract shape as DSL slots' verbatim-rebuild defaults. A "substitute then compare" route would fail on multi-run paragraphs (run structure changes) and a strip-text verification mode would touch the acceptance architecture.
5. **Duplicate paraId in the blob fails loudly.** `slotDesignationFailure` with a duplicate-occurrence reason. Why: strict mode already refuses ambiguity (duplicate names, double designation); silently picking the first occurrence risks filling the wrong cell of an official form — the worst failure mode this tool can have.

## Implementation Contract

**Behavior:** An operator runs `macdoc word reverse form.docx --to-mdocx form.mdocx.swift --slot applicant=<paraId>` on a table-bearing document (0% DSL coverage). The command succeeds, emitting a script containing `// @slot-raw applicant <paraId>` ahead of the document.xml carryPart op, with the paragraph's current text as the default value. Rendering the script unmodified and verifying against the source passes byte-equal. Editing the slot default in the script and rendering produces a docx where only the designated paragraph's text changed (pPr preserved, dominant-run rPr applied); every other byte of document.xml and all other parts are unchanged.

**Interface / data shape:**

- Script format: `// @slot-raw <name> <paraId>` directive lines, emitted adjacent to the existing `// @slot` directives; parsed by the same pre-pass that collects op-level slot directives.
- `ScriptExporter.exportSwift(log:slots:)`: existing signature unchanged; `SlotDesignation` unchanged. The validation path gains the carryPart fallback; the emitted defaults dictionary includes raw-channel slots.
- `ScriptImporter` / execute path: applies raw-channel substitutions to the carryPart XML string before the op is appended/executed; identity shortcut compares value == default before any surgery.
- Substitution target: the first (and only) `<w:p>` element whose `w14:paraId` attribute equals the designation; its run children are replaced by a single run carrying the dominant run's rPr and one `<w:t xml:space="preserve">` element.

**Failure modes:**

- paraId absent from both the DSL log and the carryPart XML → `slotDesignationFailure` with reason text extended to mention the raw-channel case ("paragraph <id> not found in the DSL log nor in the raw document.xml part").
- paraId occurring more than once in the carryPart XML → `slotDesignationFailure`, reason names the duplicate count. No first-match guessing.
- Slot on a document with neither DSL document ops nor a `word/document.xml` carryPart (degenerate package) → existing error path, unchanged.
- Substitution producing malformed XML is prevented by construction (surgery only replaces the run children of a located, well-formed `<w:p>` element and XML-escapes the substituted text).

**Acceptance criteria:**

- REC-O-01 fixture (table-bearing official form): slot designation succeeds; all-default render passes `--verify-against` byte-equal; new-value render changes exactly the designated paragraph (verified by excising the designated paragraph's fragment from both reference and output and comparing the remainders byte-equal, plus asserting the new text present — note the collapse-to-dominant-run semantic changes the run structure inside the paragraph, so a strip-text comparison would not hold there by design).
- Duplicate-paraId fixture: designation refuses with the duplicate reason.
- Unknown-paraId on a raw-channel document: error message names both lookup domains.
- Existing DSL-slot and op-level-slot test suites pass unchanged.
- MCP parity suite (`export_script` with slots on a table-bearing fixture) passes without MCP-side code changes.
