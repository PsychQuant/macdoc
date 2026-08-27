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

## 6. Verify round 1 hardening (structure-aware locator, fail-loud import)

- [x] 6.1 Replace lexical token search with a structure-aware scanner (quote-aware tags, comment/CDATA/PI skip, `<w:p>` nesting depth, attribute-position paraId) delivering the amended requirement "Raw-channel slot designation by paraId" third refusal (non-paragraph carrier named). Verified by testTableRowParaIdRefusesNamingCarrier / testParaIdOnlyInTextContentRefuses / testQuoteForgingValueCannotRedirectLaterSlot.
- [x] 6.2 Depth-aware surgery honoring `w:txbxContent` paragraph nesting and `w:pPrChange`/`w:rPrChange` self-nesting; XML 1.0 validity refusal for slot values; numeric character reference decoding in defaults. Verified by testTextboxNestedParagraphSubstitutionStaysWellFormed / testPPrChangeNestedPPrPreservedAndWellFormed / testControlCharacterValueRefuses / testNumericCharacterReferenceDefaultAndIdentity.
- [x] 6.3 Import-time guard re-application (stale directive, duplicate, missing binding → `rawSlotExecutionFailure`) and post-surgery well-formedness verification. Verified by testImportStaleDirectiveFailsLoudly / testImportDuplicateParaIdFailsLoudly.
- [x] 6.4 Full-fixture sweep regression pin: every unique REC-O-01 paraId through substitution — zero corruption (round 1 measured 21/109). Verified by testRECFixtureFullParaIdSweepZeroCorruption; full suite 1439 tests 0 failures.

## 7. Verify round 2 hardening (overlap preflight, no-carry refusal, rPr fallback)

- [x] 7.1 Overlap preflight in `apply`: all designated spans located against the original XML first; overlapping designations (outer paragraph + w:txbxContent-nested inner) refuse with both paraIds named — substitution order can never silently discard a binding. Verified by testOverlappingNestedSlotDesignationsRefuse.
- [x] 7.2 `// @slot-raw` directives with no `word/document.xml` carryPart in the log refuse instead of no-op. Verified by testRawDirectiveWithoutDocumentCarryRefuses.
- [x] 7.3 Malformed `// @slot-raw` lines throw at parse (supersedes round-1 silent-skip pin). Verified by testMalformedRawSlotDirectiveFailsLoudly.
- [x] 7.4 Dominant-rPr selection restored to whole-subtree scan (depth-aware spans) so runs inside `w:hyperlink`/`w:sdt` wrappers contribute formatting. Verified by testHyperlinkWrappedRunContributesDominantRPr.
- [x] 7.5 SKILL.md 典型情境 reordered (verify-default-first, then substitute; filled output's guarantee = render's post-surgery well-formedness + step-3-proven script structure); collapse semantic documents inline-content removal; main-part-only qualifier. Content review vs shipped behavior.
