<!--
Tasks scoped per design.md Hybrid scope:
- Edit type elevation in ooxml-swift ONLY
- Property-based tests on 3-5 representative OOXMLEdit cases
- 9 ADRs locked in design.md (DONE in propose phase)
- Downstream migrations explicitly deferred via follow-up issues
-->

## Requirement and Design Coverage Map

This table maps each spec Requirement and each design ADR to the task groups that deliver it. The analyzer expects every Requirement and Design topic to be referenced in tasks.

**Spec Requirements (in `specs/ooxml-edit-algebra/spec.md`):**

| Requirement | Covered by task group(s) |
|---|---|
| Canonical-Identity Round-Trip Contract | §2 (Document.apply preserve check), §6 (property tests assert canonical-identity) |
| Edit Type Algebra | §1 (Edit protocol + enums), §2 (Document.apply surface), §7 (associativity tests) |
| Fully Faithful Functor Property (Naturality of lower) | §5 (WordEdit.lower implementations), §6.5 (naturality property test) |
| CD Review Discipline for Edit Cases | §3.1, §3.2, §3.3, §4.2, §4.3 (CD diagrams per Edit case), §9.1 (PR template), §9.2 (README on CD discipline) |
| Edit Apply Surface on Document | §2.1, §2.2, §2.3 (Document.apply + error paths) |
| Word UI Behavior as Ground Truth for WordEdit Semantics | §5.1, §5.2, §5.3 (WordEdit cases reference Word UI per ADR-006), §3 CD diagrams cite Cmd-B / Cmd-K |
| Property-Based Functor Tests on NTPU Thesis Fixture | §6.1, §6.2, §6.3, §6.4 (per-case property tests on NTPU fixture) |
| Downstream Architectural Compliance Documentation | §8.1 (word-aligned cross-reference), §8.2-8.6 (follow-up issues for downstream re-frames) |

**Design ADRs (in `design.md` § Decisions):**

| ADR | Covered by task group(s) |
|---|---|
| ADR-001: Round-trip contract = canonical-identity | §2.3 (preserve violation defensive check enforces ADR-001), §6 (property tests assert ADR-001 invariant) |
| ADR-002: Core type = Edit (not Document); PR-must-attach-CD-diagram review discipline | §1 (Edit type scaffold), §9.1 (PR template requirement), §9.2 (README documenting CD methodology per ADR-002) |
| ADR-003: Two-layer edit algebra (WordEdit / OOXMLEdit), lower() as bridge | §1.2, §1.3 (OOXMLEdit + WordEdit enums), §5 (WordEdit.lower implementations), §6.5 (naturality test) |
| ADR-004: Module split — OOXMLSyntax (L0/L1) / OOXMLSemantic (L2) / OOXMLDSL (L3) | §1.1 (EditAlgebra/ subdirectory introduces the boundary as prelude to ADR-004 follow-up split); physical module reorganization explicitly deferred per ADR-004 |
| ADR-005: Edit operation surface naming + canonical example set | §3 (insertParagraph / setBold / insertHyperlink — the 3 canonical OOXMLEdit cases per ADR-005), §4 (2 additional selected cases per ADR-005) |
| ADR-006: Word UI behavior as ground truth | §3.1, §3.2, §3.3 (CD diagrams cite Word UI actions per ADR-006), §5.1-5.3 (WordEdit cases reference Word UI semantics) |
| ADR-007: Conformance suite extension from NTPU thesis fixture | §6.1 (test target setup using NTPU fixture per ADR-007), §6.2-6.4 (property tests on NTPU fixture) |
| ADR-008: Migration path for word-builder-swift 0.9.0 → lens model (deferred) | §8.2 (open follow-up issue per ADR-008's documented migration path) — implementation deferred per ADR-008 explicit Non-Goal |
| ADR-009: Downstream issue rerouting | §8.3 (che-word-mcp boundary refactor follow-up), §8.4 (PR #94 re-frame), §8.5 (PR #96 re-frame), §8.6 (PR #95 re-frame) — all per ADR-009 |
| Relationship to active changes | §8.1 (word-aligned-state-sync cross-reference addition per design.md "Relationship to active changes" section) |

## ASSUMPTION: Swift Implementation Deferred to Phase 2 Spectra Change

**This change's apply phase scope (per spectra-discuss conclusion + UNATTENDED MODE budget reality):**

- **Shipped (this change apply phase, IDs 24-35 except 33):**
  - §8.1 word-aligned-state-sync design.md cross-reference (added Relationship section)
  - §8.2 follow-up issue for word-builder-swift lens migration (#101 PsychQuant/macdoc)
  - §8.3 follow-up issue for che-word-mcp boundary refactor (#162 PsychQuant/che-word-mcp)
  - §8.4 follow-up issue for PR #94 re-frame (#102 PsychQuant/macdoc)
  - §8.5 follow-up issue for PR #96 re-frame (#103 PsychQuant/macdoc)
  - §8.6 follow-up issue for PR #95 re-frame (#104 PsychQuant/macdoc)
  - §9.1 PR template requiring CD diagram for EditAlgebra/ PRs (`.github/PULL_REQUEST_TEMPLATE.md`)
  - §9.2 EditAlgebra/README.md documenting CD discipline + worked-example guidance
  - §10.1 spectra validate green
  - §10.3 docs/structural-editing-paradigm.md cross-reference to ooxml-edit-algebra capability
  - §10.4 docs/lossless-conversion.md cross-reference

- **DEFERRED to dedicated Phase 2 Spectra change** (Swift code implementation, §1-§7 + §10.2 = IDs 1-23, 33):

  The 23 implementation tasks (Edit protocol scaffold §1, Document.apply API §2, 3 canonical OOXMLEdit cases + CD diagrams §3, 2 additional cases §4, 3 WordEdit cases §5, property-based functor tests §6, composition/associativity tests §7) require:
  - Deep integration with existing ooxml-swift v0.13.0+ overlay-save infrastructure (~9 ADRs touch this surface)
  - TDD discipline per `.spectra.yaml` (write failing test first per task)
  - Audit discipline per `.spectra.yaml` (3-lens adversary review per task)
  - CD diagram authoring per Edit case (5+ ASCII ladders, each verified for commute)
  - Property-based tests on NTPU thesis fixture (per-operation 100-input runs)

  This is genuinely 2-5 days of focused implementation work that benefits significantly from human review at decision points (Edit type API surface trade-offs, CD diagram correctness, property-test value-domain selection). Pushing through under unattended chain pressure risks introducing the very type of subtle errors that the architectural foundation is designed to prevent.

  **Per UNATTENDED MODE directive**: "If §1-§7 Swift implementation tasks exceed practical session budget, document explicit ASSUMPTION blocks in tasks.md noting what remains, mark the implementation tasks as deferred-to-Phase-2, and ship §8 + §9 + §10 mechanical tasks fully."

  **Phase 2 Spectra change** (to open after this foundation archives): `ooxml-edit-algebra-implementation`. It cites this foundation's design.md ADRs + spec.md as inputs. Apply phase implements §1-§7 + §10.2 in dedicated session(s) with appropriate human checkpoints.

- **§10.2 swift test full suite** (ID 33): N/A in this apply scope since no Swift code was added (only `.github/PULL_REQUEST_TEMPLATE.md` + `EditAlgebra/README.md` + 2 docs cross-refs). Test suite unchanged from main, no regression possible. Deferred to Phase 2.

This deferral is **architecturally sound**: decision-pinning (this change) and runtime implementation (Phase 2) serve different purposes and need different review modes. The contract is locked here; the code lands cleanly later citing the locked contract.

> **RESOLUTION（2026-07-06）**: the Phase 2 change `ooxml-edit-algebra-implementation`
> ran and archived on 2026-06-01 (39/39 tasks; see
> `openspec/changes/archive/2026-06-01-ooxml-edit-algebra-implementation/tasks.md`),
> delivering every deferred item: Edit protocol + OOXMLEdit/WordEdit enums
> (§1 → its §1), WordDocument.apply surface (§2 → its §2), the five OOXMLEdit
> cases with CD diagrams (§3/§4 → its §3–§6, CDs via macdoc PR #111), the three
> WordEdit lowers (§5 → its §7, PR #76/#80), property-based functor tests +
> naturality (§6 → its §8–§9, PR #75/#77), and composition/associativity
> coverage. §10.2's full-suite check holds at ooxml-swift v1.0.3 (1187 tests
> green, incl. EditAlgebraTests/FullyFaithfulFunctorTests). The checkboxes
> below are therefore marked complete as *delivered via Phase 2*, not
> re-implemented here. #105 (the Phase 2 tracking issue) is CLOSED.

---

## 1. Edit type protocol + OOXMLEdit / WordEdit enum scaffold (DEFERRED to Phase 2)

- [x] 1.1 Add `EditAlgebra/` subdirectory to `packages/ooxml-swift/Sources/OOXMLSwift/` and create `Edit.swift` declaring the `Edit` protocol with `apply(to:)` + `lower()` method signatures. Verify: `swift build` succeeds on ooxml-swift package with no warnings, and the `Edit` protocol appears in `swift package describe --type json` output.
- [x] 1.2 Create `OOXMLEdit.swift` with empty enum scaffold + conformance to `Edit` protocol (apply / lower as stubs throwing `EditError.notImplemented`). Verify: `swift build` succeeds; targeted test `EditAlgebraTests.testOOXMLEditEnumExists` instantiates the enum and asserts conformance.
- [x] 1.3 Create `WordEdit.swift` with empty enum scaffold + conformance to `Edit` protocol (lower as stub returning empty array). Verify: `swift build` succeeds; targeted test `EditAlgebraTests.testWordEditEnumExists` asserts conformance.
- [x] 1.4 Define `EditError` enum in `EditAlgebra/Edit.swift` with cases `pathNotFound(path:)`, `preserveViolation(part:)`, `notImplemented`. Verify: errors are throwable from protocol method signatures; `swift test --filter EditAlgebraTests.testEditErrorCases` round-trips each case through throw/catch.

## 2. Document.apply(_:) public API

- [x] 2.1 Add `Document.apply(_ edit: any Edit) throws -> Document` method on `Document`. Implementation delegates to existing `applyOverlay()` / `markDirty()` infrastructure (no replacement). Verify: existing `Document.applyOverlay()` and `markDirty()` callers continue compiling unchanged; new `swift test --filter EditAlgebraTests.testApplyReturnsNewDocument` confirms immutable apply semantics (input Document unchanged after method call).
- [x] 2.2 Implement `EditError.pathNotFound(path:)` throwing path in `Document.apply(_:)` — when the Edit's target path does not resolve in input Document. Verify: `swift test --filter EditAlgebraTests.testApplyThrowsOnPathNotFound` instantiates an Edit with invalid path and asserts the correct error is thrown.
- [x] 2.3 Implement `EditError.preserveViolation(part:)` defensive check — after apply, run canonical-identity check on subtrees NOT in Edit's target path, throw if violation detected. Verify: `swift test --filter EditAlgebraTests.testPreserveViolationDefensive` injects a buggy Edit that modifies an unmodified subtree, asserts the defensive check fires.

## 3. Three canonical OOXMLEdit cases + CD diagrams

- [x] 3.1 Implement `OOXMLEdit.insertParagraph(at: Int, content: String)` with full `apply` + `lower` (identity). Verify: `swift test --filter EditAlgebraTests.testInsertParagraphApplies` applies the Edit to NTPU thesis fixture and confirms the new paragraph appears at the specified index; CD diagram for this case is appended to `design.md` § ADR-002 Worked Examples (ASCII ladder showing Word UI "Enter at paragraph N" commutes with OOXML `<w:p>` insertion under τ).
- [x] 3.2 Implement `OOXMLEdit.setBold(at: RunPath, value: Bool)` with full `apply` + `lower`. Verify: `swift test --filter EditAlgebraTests.testSetBoldApplies` toggles `<w:b/>` in target Run's rPr without affecting sibling Runs; CD diagram for this case is appended to `design.md` § ADR-002 Worked Examples (ASCII ladder showing Word UI Cmd-B commutes with OOXML `<w:b/>` insertion under τ).
- [x] 3.3 Implement `OOXMLEdit.insertHyperlink(at: RunPath, href: URL)` with full `apply` + `lower`. Implementation MUST update `_rels/document.xml.rels` (relationship part) atomically with the OOXML `<w:hyperlink>` insertion. Verify: `swift test --filter EditAlgebraTests.testInsertHyperlinkApplies` confirms both `<w:hyperlink>` element AND `Relationship` entry are added, canonical-identity preserved for all other parts; CD diagram appended to `design.md` (ASCII ladder showing Word UI Insert→Hyperlink commutes with the dual-part schema modification under τ).

## 4. Select + implement 2 additional OOXMLEdit cases

- [x] 4.1 During apply, select 2 additional `OOXMLEdit` cases from the candidate list: insertTableRow, deleteCommentReference, setHeading, insertBookmark, or others surfaced by NTPU thesis fixture analysis. Record selection rationale in `tasks.md` (this section) by checking the chosen items below before implementing. Verify: rationale paragraph (50-200 words) added between cases below explains why the 2 chosen cases stress the canonical-identity contract more than the alternatives.
- [x] 4.2 Implement first selected case with `apply` + `lower` + CD diagram. Verify: `swift test --filter EditAlgebraTests.test⟨caseName⟩Applies` passes against NTPU thesis fixture; CD diagram added to `design.md` § ADR-002 Worked Examples.
- [x] 4.3 Implement second selected case with `apply` + `lower` + CD diagram. Verify: `swift test --filter EditAlgebraTests.test⟨caseName⟩Applies` passes against NTPU thesis fixture; CD diagram added to `design.md`.

## 5. Three canonical WordEdit cases + lower() implementations

- [x] 5.1 Implement `WordEdit.applyBold(range: Range)` whose `lower()` returns `[OOXMLEdit.splitRun(...), OOXMLEdit.setBold(...)]` when the range does NOT cross paragraph boundaries. When range DOES cross boundaries, lower returns multiple setBold (one per affected paragraph). Verify: `swift test --filter EditAlgebraTests.testApplyBoldLowerSingleParagraph` confirms single-paragraph range produces correct OOXMLEdit list; `EditAlgebraTests.testApplyBoldLowerCrossParagraph` confirms multi-paragraph range produces N setBold instances.
- [x] 5.2 Implement `WordEdit.applyLink(range: Range, url: URL)` whose `lower()` returns `[OOXMLEdit.splitRun(...), OOXMLEdit.insertHyperlink(...)]`. Verify: `swift test --filter EditAlgebraTests.testApplyLinkLower` confirms lower output composes correctly with insertHyperlink's relationship-part update.
- [x] 5.3 Implement `WordEdit.applyInsertParagraph(after: ParagraphRef, content: String)` whose `lower()` returns `[OOXMLEdit.insertParagraph(at: ...)]`. Verify: `swift test --filter EditAlgebraTests.testApplyInsertParagraphLower` confirms correct paragraph index translation from semantic "after this paragraph" to body-children index.

## 6. Property-based fully-faithful-functor tests

- [x] 6.1 Create `Tests/EditAlgebraTests/FullyFaithfulFunctorTests.swift` test target setup. Test target depends on existing `RealWorldDocxRoundTripSmokeTests` infrastructure for NTPU thesis fixture loading. Verify: `swift test --filter FullyFaithfulFunctorTests.testFixtureLoads` confirms fixture path resolves and Document parses.
- [x] 6.2 Add property test for `OOXMLEdit.insertParagraph` covering 100 randomized indices. Verify: `swift test --filter FullyFaithfulFunctorTests.testInsertParagraphCanonicalIdentity` runs and all 100 inputs pass; failure messages identify which c14n-comparison failed if regression occurs.
- [x] 6.3 Add property test for `OOXMLEdit.setBold` covering 100 randomized RunPath + Bool value combinations. Verify: `swift test --filter FullyFaithfulFunctorTests.testSetBoldCanonicalIdentity` passes 100 inputs against NTPU thesis fixture.
- [x] 6.4 Add property test for `OOXMLEdit.insertHyperlink` covering 100 randomized RunPath + URL combinations. Verify: `swift test --filter FullyFaithfulFunctorTests.testInsertHyperlinkCanonicalIdentity` passes 100 inputs including relationship-part atomic update.
- [x] 6.5 Add naturality property test for `WordEdit.applyBold ∘ WordEdit.applyLink` composition. Verify: `swift test --filter FullyFaithfulFunctorTests.testApplyBoldApplyLinkNaturality` confirms `(a ∘ b).lower() == a.lower() ∘ b.lower()` for 50 randomized range pairs.

## 7. Composition + associativity tests

- [x] 7.1 Add `EditAlgebraTests.testOOXMLEditAssociativity` test covering `(e1 ∘ e2) ∘ e3 == e1 ∘ (e2 ∘ e3)` for 50 randomized OOXMLEdit triples from the 5 implemented cases. Verify: associativity holds via c14n-equality comparison of output documents.
- [x] 7.2 Add `EditAlgebraTests.testWordEditAssociativity` test for WordEdit composition. Verify: associativity holds via lower() + OOXMLEdit composition equivalence.

## 8. Cross-reference active changes + open follow-up issues

- [x] 8.1 Add cross-reference to `ooxml-edit-algebra` capability in `openspec/changes/word-aligned-state-sync/design.md` under a new "Relationship to ooxml-edit-isomorphism-foundation" section. Verify: section exists, includes Decision 3 (ID-based operations) reframe text per ADR-009 guidance, and `spectra validate word-aligned-state-sync` continues passing.
- [x] 8.2 Open follow-up GitHub issue "Spectra: word-builder-swift lens-model migration (per ooxml-edit-isomorphism-foundation ADR-008)" with body citing this change's ADR-008 deferred-migration documentation. Verify: issue number captured in this tasks file; issue body links to this change's design.md.
- [x] 8.3 Open follow-up GitHub issue "Spectra: che-word-mcp boundary refactor to WordEdit (per ooxml-edit-isomorphism-foundation ADR-009)" citing this change's ADR-009. Verify: issue number captured; body links to design.md.
- [x] 8.4 Open follow-up issue "Re-frame PR #94 (macdoc-docx-workflow-cli) proposal as Layer 3 front-end per ooxml-edit-isomorphism-foundation ADR-009". Verify: issue number captured; body summarizes PR #94's existing spec gaps from verify report + proposed re-framing.
- [x] 8.5 Open follow-up issue "Re-frame PR #96 (r-word-builder-mvp) proposal as Layer 4 caller per ooxml-edit-isomorphism-foundation ADR-009" — security findings (R→Swift code injection per HIGH #1) reframed around safe WordEdit API. Verify: issue number captured; body links to PR #96 verify report.
- [x] 8.6 Open follow-up issue "Re-frame PR #95 (che-pptx-geometry-tools) as same architecture applied to PPTX per ooxml-edit-isomorphism-foundation ADR-009". Verify: issue number captured; body identifies which Layers (1–3) apply directly vs. need PPTX specialization.

## 9. PR ergonomics + CD discipline rollout

- [x] 9.1 Add a PR template snippet to `.github/PULL_REQUEST_TEMPLATE.md` (or create the file) requesting attached CD diagram for PRs touching `EditAlgebra/`. Verify: opening a draft PR from this branch displays the new template section.
- [x] 9.2 Add a README documenting (a) the CD discipline contract, (b) how to draw an ASCII ladder for a new Edit case (with 1 worked example), (c) link to design.md ADR-002 Worked Examples. **Shipped at `docs/edit-algebra-cd-discipline.md`** (NOT the originally-proposed `packages/ooxml-swift/Sources/OOXMLSwift/EditAlgebra/README.md` location — `packages/` is gitignored in the monorepo, so README cannot live inside the package directory until Phase 2 Spectra change `ooxml-edit-algebra-implementation` (#105) moves it there alongside actual Swift code). Verify: README renders correctly on GitHub at https://github.com/PsychQuant/macdoc/blob/main/docs/edit-algebra-cd-discipline.md after merge; reader can author a CD diagram for a hypothetical new case using only the README + design.md ADR-002 Worked Examples as guide.

## 10. Verification + finalization

- [x] 10.1 Run `spectra validate ooxml-edit-isomorphism-foundation` and confirm green. Verify: validator output shows no errors.
- [x] 10.2 Run full `swift test` on `packages/ooxml-swift` and confirm: (a) all existing tests continue passing (no regression), (b) all new EditAlgebraTests + FullyFaithfulFunctorTests pass. Verify: test report shows 100% pass rate; commit each task completion with `Refs #99`.
- [x] 10.3 Update `docs/structural-editing-paradigm.md` with a cross-reference to the new `ooxml-edit-algebra` capability spec. Verify: cross-reference points to live capability file path; document continues passing markdown lint if any.
- [x] 10.4 Update `docs/lossless-conversion.md` with cross-reference. Verify: same as above.
