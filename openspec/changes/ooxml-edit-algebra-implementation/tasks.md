<!--
Tasks for ooxml-edit-algebra-implementation (Phase 2 Swift code for foundation #99).

All commits land on ooxml-swift branch idd/105-edit-algebra-runtime.
Each commit references PsychQuant/macdoc#105.

Foundation contract anchors (do not violate):
- spec.md "Canonical-Identity Round-Trip Contract"
- spec.md "Edit Apply Surface on Document"
- design.md ADR-002 CD discipline (PR must attach CD diagram per Edit case)
- design.md ADR-005 naming convention (OOXMLEdit uses schema-element names; WordEdit uses Word UI verb prefixes)
-->

## Requirement and Design Coverage Map

| Capability Requirement (this change's spec.md) | Covered by task group(s) |
|---|---|
| Edit Protocol Public API | §1 (Edit protocol + EditError) |
| OOXMLEdit Enum with 5 Canonical Cases | §3 (insertParagraph + insertParagraphBefore), §4 (setBold), §5 (insertHyperlink), §6 (removeParagraph) |
| WordEdit Enum with 3 Canonical Cases | §7 (applyBold + applyLink + applyInsertParagraph) |
| Document.apply Public Method | §2 (Document.apply wiring) |
| Property-Based Fully-Faithful-Functor Tests | §8 (per-case property tests), §9 (naturality tests) |
| CD Diagrams Land in Documentation | §10.1 (CD diagrams in docs/edit-algebra-cd-discipline.md) |
| Edit Apply Performance Within Foundation Baseline | §10.2 (benchmark) |
| Foundation Spec Compliance | §10.3 (foundation spec validate stays green) |

| Design Decision (this change's design.md) | Covered by task group(s) |
|---|---|
| Decision 1: Edit ↔ Operation mapping table | §3-§6 (each OOXMLEdit case's `operations()` method) |
| Decision 2: WordEdit ↔ OOXMLEdit mapping | §7 (WordEdit cases' `lower()` implementations) |
| Decision 3: Document.apply implementation strategy | §2 (apply method routes through OperationLog + Reducer) |
| Decision 4: EditError shape | §1 (EditError enum with 5 cases) |
| Decision 5: Property test infrastructure | §8 (`swift-testing` `@Test(arguments:)`) |

## 1. Edit protocol + EditError + enum scaffold

- [ ] 1.1 Create `packages/ooxml-swift/Sources/OOXMLSwift/EditAlgebra/Edit.swift` declaring `public protocol Edit { func apply(to document: Document) throws -> Document; func lower() -> [OOXMLEdit] }` + `public enum EditError: Error, Equatable` with all 5 cases per Decision 4. Verify: `swift build` succeeds with no warnings; protocol and enum visible via `swift package describe --type json`.
- [ ] 1.2 Create `packages/ooxml-swift/Sources/OOXMLSwift/EditAlgebra/OOXMLEdit.swift` with `public enum OOXMLEdit: Edit, Equatable, Sendable` containing all 5 case declarations from spec.md (insertParagraph + insertParagraphBefore + setBold + insertHyperlink + removeParagraph), each with stub `apply(to:)` throwing `EditError.notImplemented("OOXMLEdit.\(caseName)")` and `lower()` returning `[self]`. Verify: `swift build` succeeds; targeted test `EditAlgebraTests.testOOXMLEditEnumExists` instantiates each case and confirms Edit conformance.
- [ ] 1.3 Create `packages/ooxml-swift/Sources/OOXMLSwift/EditAlgebra/WordEdit.swift` with `public enum WordEdit: Edit, Equatable, Sendable` containing 3 case declarations (applyBold + applyLink + applyInsertParagraph) + `public struct WordRange: Equatable, Sendable` with the 4 fields per spec. Each WordEdit case has stub `apply(to:)` calling `lower()` then `Document.apply([OOXMLEdit])`, and stub `lower()` returning `[]` (TODO marker). Verify: `swift build` succeeds; targeted test `EditAlgebraTests.testWordEditEnumExists` asserts conformance.
- [ ] 1.4 Create empty `packages/ooxml-swift/Sources/OOXMLSwift/EditAlgebra/OOXMLEdit+Operation.swift` placeholder where the `operations() -> [Operation]` extension method will live (§3-§6 fill it in). Verify: file exists, compiles.

## 2. Document.apply public API

- [ ] 2.1 Add `extension Document { public func apply(_ edit: any Edit) throws -> Document }` to `packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift`. Implementation per Decision 3: call `edit.lower().flatMap { $0.operations() }`, append to OperationLog, materialize via OperationReducer, return new Document. Verify: existing `Document.applyOverlay`, `markPartDirty`, `partTree`, `xmlTrees` callers compile unchanged; new test `DocumentApplyTests.testApplyReturnsNewDocument` confirms immutable apply (input Document c14n-equal after call).
- [ ] 2.2 Implement `EditError.pathNotFound` throw in `Document.apply(_:)` — validate ALL target ElementIDs resolve in input Document BEFORE log append (early validation). Verify: `DocumentApplyTests.testApplyThrowsOnPathNotFound` instantiates Edit with invalid ElementID and asserts the correct error is thrown.
- [ ] 2.3 Implement `EditError.preserveViolation` defensive check in `Document.apply(_:)` — after Reducer.materialize, compare c14n forms of NON-target parts; throw if any differ. Verify: `DocumentApplyTests.testPreserveViolationDefensive` injects a buggy mock Edit that returns Operations modifying a non-target part, asserts the defensive check fires.
- [ ] 2.4 Implement `EditError.operationLogFailure` wrapping — wrap any thrown `OperationReducer` error (e.g., reducer internal error) as `EditError.operationLogFailure(underlying: error.localizedDescription)`. Verify: `DocumentApplyTests.testOperationLogFailureWrap` uses a corrupted log fixture (or mock) to trigger Reducer error and asserts the wrapped error type.
- [ ] 2.5 Add sequence-folding `extension Document { public func apply<S: Sequence>(_ edits: S) throws -> Document where S.Element == any Edit }` per spec.md Requirement "Document.apply Public Method". Verify: `DocumentApplyTests.testApplyMultipleEdits` applies 3 edits in sequence and confirms equivalence to fold-of-singles.

## 3. OOXMLEdit.insertParagraph + insertParagraphBefore (first canonical case)

- [x] 3.1 Implement `OOXMLEdit.insertParagraph(after:content:styleId:).operations()` per Decision 1 mapping table: emit `[Operation.insertParagraphAfter(after: elementID, paragraph: ParagraphPayload(text: content, styleId: styleId))]`. Verify: `InsertParagraphTests.testInsertParagraphEmitsInsertParagraphAfter` + `testInsertParagraphPreservesStyleId` + `testInsertParagraphEmptyContent` assert emission shape.
- [x] 3.2 Implement `OOXMLEdit.insertParagraphBefore(...)` symmetrically with `Operation.insertParagraphBefore`. Verify: `InsertParagraphTests.testInsertParagraphBeforeEmitsInsertParagraphBefore` confirms emission.
- [ ] 3.3 **BLOCKED** on OpLog Phase 2c (see design.md Decision 6). End-to-end test: `EditAlgebraTests.testInsertParagraphApplies` applies the Edit to the NTPU thesis fixture and confirms the new paragraph appears at the specified index; assert canonical-identity for sectPr / comments / customXml (c14n-equal to input). **Cannot ship until OperationReducer implements `insertParagraphAfter`/`insertParagraphBefore` cases (currently throws `malformedOp("Phase 2c implements this op")`).** Tracking: file ooxml-swift issue for "OpLog Phase 2c reducer cases" before unblocking.
- [ ] 3.4 Add CD diagram for `OOXMLEdit.insertParagraph(after:)` to `docs/edit-algebra-cd-discipline.md`, following the ASCII-ladder format of foundation ADR-002 Worked Example 1 (the diagram for this case already exists in foundation design.md — extend with Operation reference). Verify: diagram present in repo, references this case explicitly.

## 4. OOXMLEdit.setBold (run-level mutation)

- [ ] 4.1 Implement `OOXMLEdit.setBold(target:value:).operations()` per Decision 1: emit `[Operation.setRunFormat(target: targetID, format: RunFormatPayload(bold: value, ...other fields nil))]`. Decide: pass `bold: false` as explicit-false vs nil-omit (depends on how RunFormatPayload represents "remove bold" vs "leave unchanged"). Verify: `EditAlgebraTests.testSetBoldEmitsOperation` confirms emission.
- [ ] 4.2 End-to-end test: `EditAlgebraTests.testSetBoldApplies` toggles bold on a Run in NTPU fixture; assert `<w:b/>` presence flipped in target Run's rPr; assert sibling Runs' rPr c14n-equal to input.
- [ ] 4.3 Add CD diagram for `OOXMLEdit.setBold` extending foundation ADR-002 Worked Example 2.

## 5. OOXMLEdit.insertHyperlink (composite dual-part atomic case)

- [ ] 5.1 Implement `OOXMLEdit.insertHyperlink(target:href:displayText:).operations()` per Decision 1 composite mapping: emit `[Operation.insertNode(parent: targetParent, position: idx, nodeXML: hyperlinkElementXML), Operation.updateAttribute(target: relsPart, prefix: nil, localName: "Target", value: href.absoluteString)]`. The 2 operations MUST appear in this order (insertNode first, then updateAttribute) so atomic rollback semantics are preserved by OperationLog batch. Verify: `EditAlgebraTests.testInsertHyperlinkEmitsOperations` confirms 2-element list with correct order.
- [ ] 5.2 Implement upfront atomicity validation: BEFORE returning operations, check both target paragraph exists AND _rels/document.xml.rels exists; throw `EditError.preserveViolation(part:)` if either missing. Verify: `EditAlgebraTests.testInsertHyperlinkAtomicityValidation` removes rels-part from fixture and asserts upfront throw.
- [ ] 5.3 End-to-end test: `EditAlgebraTests.testInsertHyperlinkApplies` adds hyperlink to NTPU fixture; assert both `<w:hyperlink r:id="rNN">` element added to document.xml AND new `<Relationship>` entry in _rels/document.xml.rels; assert all other parts c14n-equal to input.
- [ ] 5.4 Add CD diagram for `OOXMLEdit.insertHyperlink` extending foundation ADR-002 Worked Example 3 (dual-part atomic).

## 6. OOXMLEdit.removeParagraph (5th canonical case)

- [ ] 6.1 Implement `OOXMLEdit.removeParagraph(target:).operations()` per Decision 1: emit `[Operation.removeParagraph(id: targetID)]`. Verify: `EditAlgebraTests.testRemoveParagraphEmitsOperation` confirms emission.
- [ ] 6.2 End-to-end test: `EditAlgebraTests.testRemoveParagraphApplies` removes a paragraph from NTPU fixture; assert target paragraph gone; assert ALL other paragraphs + sibling Runs c14n-equal to input (this stress-tests preserve-violation since removing a paragraph shifts body-children indices). 
- [ ] 6.3 Add CD diagram for `OOXMLEdit.removeParagraph` to `docs/edit-algebra-cd-discipline.md` (new — not in foundation ADR-002, designed during this change).

## 7. WordEdit cases + lower() implementations

- [ ] 7.1 Implement `WordEdit.applyBold(range:).lower()` per Decision 2: detect if range is within single paragraph or crosses boundary; emit 1-element or N-element `[OOXMLEdit.setBold]` list accordingly. If range partial-covers a Run, prepend split-run operation (TBD: requires adding `OOXMLEdit.splitRun` case if not already present — file ooxml-swift issue if Operation.splitRun not in v0.31.x). Verify: `EditAlgebraTests.testApplyBoldLowerSingleParagraph` + `testApplyBoldLowerCrossParagraph`.
- [ ] 7.2 Implement `WordEdit.applyLink(range:url:).lower()` per Decision 2: emit `[OOXMLEdit.insertHyperlink(target: rangeRoot, href: url, displayText: rangeText)]`. Verify: `EditAlgebraTests.testApplyLinkLower` confirms.
- [ ] 7.3 Implement `WordEdit.applyInsertParagraph(after:content:).lower()` per Decision 2: resolve `ParagraphRef` to `ElementID`, emit `[OOXMLEdit.insertParagraph(after: paraID, content: content, styleId: nil)]`. Verify: `EditAlgebraTests.testApplyInsertParagraphLower`.
- [ ] 7.4 Add CD diagrams for the 3 WordEdit cases extending foundation ADR-002 Worked Example 4 (range-crossing boundary).

## 8. Property-based fully-faithful-functor tests per OOXMLEdit case

- [ ] 8.1 Create `Tests/OOXMLSwiftTests/EditAlgebraTests/FullyFaithfulFunctorTests.swift` test target setup using `swift-testing` `@Test(arguments:)`. Reuse NTPU thesis fixture loader from `RealWorldDocxRoundTripSmokeTests`. Verify: `FullyFaithfulFunctorTests.testFixtureLoads` confirms fixture path resolves and Document parses.
- [ ] 8.2 Add property test for `OOXMLEdit.insertParagraph` covering 100 randomized indices (valid range from 0 to body.children.count). Verify: `FullyFaithfulFunctorTests.testInsertParagraphCanonicalIdentity` passes 100 inputs; failure logs reproducible seed.
- [ ] 8.3 Add property test for `OOXMLEdit.setBold` covering 100 randomized RunPath × {true, false} samples. Verify: `FullyFaithfulFunctorTests.testSetBoldCanonicalIdentity` passes 100 inputs.
- [ ] 8.4 Add property test for `OOXMLEdit.insertHyperlink` covering 100 randomized target × URL samples (test URLs from `https://example.com/test/<UUID>`). Verify: `FullyFaithfulFunctorTests.testInsertHyperlinkCanonicalIdentity` passes 100 inputs INCLUDING rels-part atomic update assertion.
- [ ] 8.5 Add property test for `OOXMLEdit.removeParagraph` covering 100 randomized target IDs. Verify: `FullyFaithfulFunctorTests.testRemoveParagraphCanonicalIdentity` passes 100 inputs.

## 9. Naturality tests for WordEdit composition

- [ ] 9.1 Add `Tests/OOXMLSwiftTests/EditAlgebraTests/NaturalityTests.swift` test target. Verify file exists, swift build OK.
- [ ] 9.2 Add naturality test for `WordEdit.applyBold ∘ WordEdit.applyLink` — 50 randomized pair samples; assert `(a ∘ b).lower() == a.lower() ∘ b.lower()` (allowing operation reordering for independent ops). Verify: `NaturalityTests.testApplyBoldApplyLinkNaturality` passes 50 inputs.
- [ ] 9.3 Add naturality test for `WordEdit.applyBold ∘ WordEdit.applyInsertParagraph` — 50 randomized pair samples. Verify: `NaturalityTests.testApplyBoldApplyInsertParagraphNaturality` passes.
- [ ] 9.4 Add naturality test for `WordEdit.applyLink ∘ WordEdit.applyInsertParagraph` — 50 randomized pair samples. Verify: `NaturalityTests.testApplyLinkApplyInsertParagraphNaturality` passes.

## 10. Verification + finalization

- [ ] 10.1 Add CD diagrams for all 5 OOXMLEdit cases + 3 WordEdit cases to `docs/edit-algebra-cd-discipline.md`. Verify: file contains 8 CD diagram sections; cross-references from `Tests/.../FullyFaithfulFunctorTests.swift` comments back to the diagrams.
- [ ] 10.2 Run benchmark: `OOXMLEdit.insertParagraph.apply` × 100 calls vs direct `OperationLog.append + OperationReducer.materialize` × 100 calls. Verify: average time within 10% of baseline (per spec.md Performance Requirement). Record results in `docs/edit-algebra-cd-discipline.md` § Benchmarks.
- [ ] 10.3 Run `spectra validate ooxml-edit-algebra-implementation` AND `spectra validate ooxml-edit-isomorphism-foundation` — both must pass green. Verify: validator output shows no errors for either change.
- [ ] 10.4 Run full `swift test` on ooxml-swift package. Verify: all existing tests continue passing (no regression) AND all new EditAlgebra/Naturality/FullyFaithfulFunctor tests pass at 100%.
- [ ] 10.5 Update `docs/edit-algebra-cd-discipline.md` § Status section: change "Currently in decision-pinning state" to "Phase 2 implementation shipped via PsychQuant/macdoc#105 + ooxml-swift PR <N>". Verify: status accurate.
- [ ] 10.6 Add errata note to foundation #99 issue body (or as comment if body too long): backing reference correction from "applyOverlay/markDirty" (ADR-002 original) to "Operation/OperationLog/OperationReducer" (this change's design.md Decision 3). Verify: errata visible on #99 issue.
