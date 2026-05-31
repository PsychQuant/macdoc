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

## 1. Edit protocol + EditError + enum scaffold — COMPLETE

- [x] 1.1 Create `packages/ooxml-swift/Sources/OOXMLSwift/EditAlgebra/Edit.swift` declaring `public protocol Edit { func apply(to document: WordDocument) throws -> WordDocument; func lower() -> [OOXMLEdit] }` + `public enum EditError: Error, Equatable, Sendable` with all 5 cases per Decision 4. Verified: `swift build` succeeds; `EditProtocolTests` confirms shape.
- [x] 1.2 Create `packages/ooxml-swift/Sources/OOXMLSwift/EditAlgebra/OOXMLEdit.swift` with `public enum OOXMLEdit: Edit, Equatable, Sendable` containing all 5 case declarations (insertParagraph + insertParagraphBefore + setBold + insertHyperlink + removeParagraph). Stub `apply(to:)` throws `EditError.notImplemented` (replaced per case in §3-§6). `lower()` returns `[self]` (identity for OOXMLEdit). Verified: `EditProtocolTests.testOOXMLEditCases*` confirms conformance.
- [x] 1.3 Create `packages/ooxml-swift/Sources/OOXMLSwift/EditAlgebra/WordEdit.swift` with `public enum WordEdit: Edit, Equatable, Sendable` containing 3 case declarations + `public struct WordRange: Equatable, Sendable` + `public struct ParagraphRef: Equatable, Sendable`. Stub `lower()` returns `[]` (TODO marker for §7). Verified: `EditProtocolTests` covers WordEdit + WordRange.
- [x] 1.4 Create `packages/ooxml-swift/Sources/OOXMLSwift/EditAlgebra/OOXMLEdit+Operation.swift` where per-case `operations() -> [Operation]` mapping lives. §3-§6 fill in cases incrementally.

## 2. Document.apply public API — wiring COMPLETE; defensive validations PHASED

- [x] 2.1 Add `extension WordDocument { public func apply(_ edit: any Edit) throws -> WordDocument }` to `packages/ooxml-swift/Sources/OOXMLSwift/EditAlgebra/WordDocument+Apply.swift` (new file, not Models/Document.swift). Implementation per Decision 3: lower edit → operations → append to OperationLog → materialize via OperationReducer → return new WordDocument. WordDocument gains additive `operationLog: OperationLog` field. Verified: `DocumentApplyTests.testApplyReturnsNewDocument` + 8 more tests confirm immutability + log append + sequence apply.
- [ ] 2.2 **PHASED — see Decision 6 errata**. Implement `EditError.pathNotFound` early-validation throw in `WordDocument.apply(_:)` (validate ALL target ElementIDs resolve in input BEFORE log append). Currently the Reducer's per-op `elementNotFound` surfaces as `EditError.operationLogFailure(underlying:)`; upfront `pathNotFound` is the cleaner UX but requires per-op target extraction (depends on per-op part scoping fix). Tracked together with §2.3 + multi-part scoping fix.
- [ ] 2.3 **PHASED — see Decision 6 errata**. Implement `EditError.preserveViolation` defensive c14n check in `WordDocument.apply(_:)` (after Reducer.materialize, assert non-target parts are c14n-equal to input). Requires c14n digest helper + per-op part scoping (currently apply iterates ALL parts).
- [x] 2.4 Implement `EditError.operationLogFailure` wrapping — any thrown `OperationReducer` error wrapped as `EditError.operationLogFailure(underlying: error.localizedDescription)`. Verified: `WordDocument+Apply.swift:86` wraps via `do { … } catch { throw EditError.operationLogFailure(underlying: …) }`.
- [x] 2.5 Add sequence-folding `extension WordDocument { public func apply<S: Sequence>(_ edits: S) throws -> WordDocument where S.Element == any Edit }`. Verified: `DocumentApplyTests.testApplyEmptySequence` + `testApplySingleEditViaSequence`.

## 3. OOXMLEdit.insertParagraph + insertParagraphBefore (first canonical case)

- [x] 3.1 Implement `OOXMLEdit.insertParagraph(after:content:styleId:).operations()` per Decision 1 mapping table: emit `[Operation.insertParagraphAfter(after: elementID, paragraph: ParagraphPayload(text: content, styleId: styleId))]`. Verify: `InsertParagraphTests.testInsertParagraphEmitsInsertParagraphAfter` + `testInsertParagraphPreservesStyleId` + `testInsertParagraphEmptyContent` assert emission shape.
- [x] 3.2 Implement `OOXMLEdit.insertParagraphBefore(...)` symmetrically with `Operation.insertParagraphBefore`. Verify: `InsertParagraphTests.testInsertParagraphBeforeEmitsInsertParagraphBefore` confirms emission.
- [x] 3.3 **UNBLOCKED + SHIPPED (synthesized variant)** — ooxml-swift#71 Phase 2c reducer cases for `insertParagraphAfter` + `insertParagraphBefore` landed. `InsertParagraphE2ETests.testInsertParagraphAfterMutatesDocumentPart` + `testInsertParagraphBeforeMutatesDocumentPart` prove the full chain (Edit → lower → operations → log → materialize → new WordDocument) mutates `xmlTrees["word/document.xml"]` on a synthesized single-part doc. **Real .docx fixture variant (NTPU thesis + canonical-identity for sectPr/comments/customXml) deferred** until per-op part scoping fix lands in `WordDocument+Apply.swift` (currently iterates ALL parts → Reducer throws elementNotFound on parts not containing target).
- [ ] 3.4 Add CD diagram for `OOXMLEdit.insertParagraph(after:)` to `docs/edit-algebra-cd-discipline.md`, following the ASCII-ladder format of foundation ADR-002 Worked Example 1 (the diagram for this case already exists in foundation design.md — extend with Operation reference). Verify: diagram present in repo, references this case explicitly.

## 4. OOXMLEdit.setBold (run-level mutation) — emission COMPLETE

- [x] 4.1 Implement `OOXMLEdit.setBold(target:value:).operations()` — emits `[Operation.setRunFormat(target:, format: RunFormatPayload(bold: value))]`. **Decision (resolved)**: `value: false` lowers to EXPLICIT `payload.bold = false` (not nil) — nil means "leave unchanged", explicit false means "remove bold". `SetBoldTests.testSetBoldFalseEmitsSetRunFormatWithBoldFalse` pins the contract.
- [x] 4.2 **UNBLOCKED + SHIPPED (synthesized variant)** — ooxml-swift#71 Phase 2c `setRunFormat` (bold MVP) landed. `InsertParagraphE2ETests.testSetBoldMutatesRunRPr` confirms the chain produces `<w:rPr><w:b/></w:rPr>` on the targeted Run after `doc.apply(OOXMLEdit.setBold(target:, value: true))`. Real-.docx NTPU variant deferred behind multi-part scoping fix.
- [ ] 4.3 Add CD diagram for `OOXMLEdit.setBold` extending foundation ADR-002 Worked Example 2.

## 5. OOXMLEdit.insertHyperlink (composite dual-part atomic case) — PENDING composite-design checkpoint

> **Status**: Awaiting user input on 5 composite-design questions before §5.1 starts (target type semantics — wrap existing Run vs insert new wrapper; atomicity strategy if OpLog batch rollback not available; rels XML coordination — same Operation or cross-part composite; displayText nil → use href; run-splitting when range partial-covers a Run). Independent of OpLog Phase 2c emission can ship anytime; e2e additionally needs ooxml-swift#71 `insertNode` + `updateAttribute` reducer cases.

- [ ] 5.1 Implement `OOXMLEdit.insertHyperlink(target:href:displayText:).operations()` per Decision 1 composite mapping: emit `[Operation.insertNode(parent: targetParent, position: idx, nodeXML: hyperlinkElementXML), Operation.updateAttribute(target: relsPart, prefix: nil, localName: "Target", value: href.absoluteString)]`. The 2 operations MUST appear in this order (insertNode first, then updateAttribute) so atomic rollback semantics are preserved by OperationLog batch. Verify: `EditAlgebraTests.testInsertHyperlinkEmitsOperations` confirms 2-element list with correct order.
- [ ] 5.2 Implement upfront atomicity validation: BEFORE returning operations, check both target paragraph exists AND _rels/document.xml.rels exists; throw `EditError.preserveViolation(part:)` if either missing. Verify: `EditAlgebraTests.testInsertHyperlinkAtomicityValidation` removes rels-part from fixture and asserts upfront throw.
- [ ] 5.3 End-to-end test: `EditAlgebraTests.testInsertHyperlinkApplies` adds hyperlink to NTPU fixture; assert both `<w:hyperlink r:id="rNN">` element added to document.xml AND new `<Relationship>` entry in _rels/document.xml.rels; assert all other parts c14n-equal to input.
- [ ] 5.4 Add CD diagram for `OOXMLEdit.insertHyperlink` extending foundation ADR-002 Worked Example 3 (dual-part atomic).

## 6. OOXMLEdit.removeParagraph (5th canonical case) — emission COMPLETE

- [x] 6.1 Implement `OOXMLEdit.removeParagraph(target:).operations()` — emits `[Operation.removeParagraph(id: target)]`. Pinned label translation: OOXMLEdit uses `target:`, Operation uses `id:` — `RemoveParagraphTests.testRemoveParagraphEmitsOperationRemoveParagraph` asserts ElementID survives the label rename.
- [x] 6.2 **UNBLOCKED + SHIPPED (synthesized variant)** — ooxml-swift#71 Phase 2c `removeParagraph` case landed. `InsertParagraphE2ETests.testRemoveParagraphMutatesDocumentPart` removes middle paragraph from synthesized 3-paragraph doc and confirms siblings ["a", "c"] preserved. Real-.docx NTPU variant + sibling-rPr c14n-equality assertions deferred behind multi-part scoping fix.
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
