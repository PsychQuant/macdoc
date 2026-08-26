## 1. Slot designation fallback (export side)

- [x] 1.1 Deliver the requirement "Raw-channel slot designation by paraId": extend `ScriptExporter.exportSwift(log:slots:)` validation so a paraId missed by the `.appendParagraph` scan falls back to scanning the `word/document.xml` carryPart XML for `w14:paraId="<id>"`; exactly one occurrence classifies the designation as a raw-channel slot. Verified by a new unit test designating a slot on a table-bearing fixture (export succeeds where it previously threw).
- [x] 1.2 Refuse with `slotDesignationFailure` when the paraId occurs more than once in the carryPart XML, the reason naming the occurrence count; and extend the not-found reason to name both searched domains (DSL log and raw part). Verified by two unit tests asserting both refusal messages.
- [x] 1.3 Extract the raw-channel slot default: the designated paragraph's concatenated `<w:t>` text. Verified by a unit test asserting the default for a known fixture paragraph equals its visible text.

## 2. Script representation (directive emit + parse)

- [x] 2.1 Emit `// @slot-raw <name> <paraId>` directive lines ahead of the document.xml carryPart op, alongside existing `// @slot` emission, with the default recorded the same way op-level slot defaults are. Verified by asserting the exported script for a slotted table-bearing fixture contains the directive and round-trips through the importer.
- [x] 2.2 Extend the importer's directive pre-pass to collect `// @slot-raw` designations and associate them with the carryPart op; malformed directive lines are skipped exactly like the existing `// @slot` pre-pass (comment lines never break parsing). Verified by parse unit tests (well-formed line round-trips; malformed line is ignored and execution stays byte-equal).

## 3. Substitution at execute time

- [x] 3.1 [P] Deliver the requirement "Raw-channel slot substitution preserves everything outside the designated paragraph": implement run-level surgery on the carryPart XML for a raw-channel slot whose value differs from its default: locate the single `<w:p>` with the designated `w14:paraId`, keep its `pPr`, replace its run children with one run carrying the dominant text run's `rPr` and a single `<w:t xml:space="preserve">` element with the XML-escaped value. Verified by a unit test asserting the substituted part differs from the reference only inside the designated paragraph (excise-paragraph comparison byte-equal + new text present).
- [x] 3.2 [P] Implement the identity shortcut: a slot value equal to its default leaves the carried XML untouched (string-identical, no parse/serialize round trip). Verified by a unit test asserting all-default execution produces a byte-identical part.

## 4. End-to-end acceptance on the fixture corpus

- [x] 4.1 Add an end-to-end test on the REC-O-01 table-bearing fixture: designate a slot, export, execute all-default, and assert byte-equal verification against the source passes (the existing `--verify-against` acceptance path, unchanged). Verified by the new test passing in the OOXMLSwift test suite.
- [x] 4.2 Add an end-to-end test executing the same script with a new slot value and asserting: the output opens as valid OOXML, the designated paragraph carries the new text with preserved `pPr`, and excising the designated paragraph makes the part byte-identical to the reference remainder. Verified by the new test passing.
- [x] 4.3 Run the existing DSL-slot, op-level-slot, and MCP script-pipeline parity suites unchanged and confirm they pass, demonstrating no regression and MCP-surface inheritance via the shared transcoder entry points. Verified by the full `swift test` run for OOXMLSwift plus the parity suite green.

## 5. Workflow documentation convergence

- [x] 5.1 Update the swiftify SKILL.md raw-channel section from promise to present-tense behavior description: raw-channel slots by paraId, the collapse-to-dominant-run substitution semantic, the identity-shortcut default replay, and the two refusal modes (unknown paraId naming both domains, duplicate paraId). Verified by content review against the shipped behavior and the `swiftify-workflow` spec's coverage-first framing.
