## 1. Setup & Test Infrastructure

- [x] 1.1 Create `packages/ooxml-swift/Tests/OOXMLSwiftTests/Issue99FlattenReplaceOMMLBilateralTests.swift` skeleton with shared fixtures: (a) `<w:p>` direct-child OMML reproducer for Decision 6 source-XML position ordering, (b) `<w:hyperlink>` direct-child, (c) `<mc:Fallback>` direct-child, (d) nested hyperlink/fldSimple combo. Each fixture builds via `DocxReader.read(from:)` of an inline-XML stub so tests do not depend on external `.docx` files.

## 2. ReplaceResult Enum (Decision 7)

- [x] 2.1 RED test: `ReplaceResult.replaced(count: N)` constructible with `count >= 0`; `count == 0` distinct from `refusedDueToOMMLBoundary` per requirement "ReplaceResult enum carries informative refusal occurrences" — anchor not found returns `.replaced(count: 0)`, NOT a refusal case.
- [x] 2.2 RED test: `ReplaceResult.refusedDueToOMMLBoundary(occurrences:)` carries `[Occurrence]` where each `Occurrence` has `matchSpan: Range<Int>` and `ommlSpans: [Range<Int>]`; verify shape via direct enum construction (no engine integration yet).
- [x] 2.3 Implement `packages/ooxml-swift/Sources/OOXMLSwift/Models/ReplaceResult.swift` — public `enum ReplaceResult: Equatable { case replaced(count: Int); case refusedDueToOMMLBoundary(occurrences: [Occurrence]) }` plus nested `public struct Occurrence: Equatable { public let matchSpan: Range<Int>; public let ommlSpans: [Range<Int>] }`. Mark file-level doc-comment referencing the spec capability `ooxml-paragraph-text-mirror`.
- [x] 2.4 Verify GREEN: 2.1 + 2.2 pass with new enum.

## 3. Walker Helper for Direct-Child OMML (Decision 3 — Lightweight unified walker, not protocol abstraction)

- [x] 3.1 RED test: `flattenedDisplayText()` on `<w:p><w:r><w:t>see eq </w:t></w:r><m:oMath>...δ...</m:oMath><w:r><w:t> here</w:t></w:r></w:p>` returns `"see eq δ here"` — covers Requirement "flattenedDisplayText walks direct-child OMML at all 4 wrapper positions" position 1 (paragraph) AND Decision 6 source-XML position ordering.
- [x] 3.2 RED test: `flattenedDisplayText()` includes `θ` from `<w:hyperlink><m:oMath>...θ...</m:oMath></w:hyperlink>` — wrapper position 2.
- [x] 3.3 RED test: `flattenedDisplayText()` includes `κ` from `<mc:AlternateContent><mc:Fallback><m:oMath>...κ...</m:oMath></mc:Fallback></mc:AlternateContent>` — wrapper position 3.
- [x] 3.4 RED test: `flattenedDisplayText()` includes `η` from nested `<w:hyperlink><w:fldSimple><w:r><m:oMath>...η...</m:oMath></w:r></w:fldSimple></w:hyperlink>` — wrapper position 4 (nested wrapper).
- [x] 3.5 RED test: walker reads OMML from raw storage on demand — covers Requirement "Direct-child OMML storage remains raw passthrough". Assert: after `flattenedDisplayText()` walks a paragraph, `paragraph.unrecognizedChildren` containing `name == "oMath"` entries are unchanged (rawXML preserved verbatim, no mutation).
- [x] 3.6 Implement private helper `walkOMMLBearingChildren(_ paragraph:, _ visit:)` (or per-direction equivalent helpers) in `packages/ooxml-swift/Sources/OOXMLSwift/Models/InsertLocation.swift`. Helper enumerates: (a) `paragraph.unrecognizedChildren where name == "oMath" || name == "oMathPara"`, (b) `paragraph.hyperlinks[].children where case .rawXML(raw) and raw.contains("oMath")`, (c) `paragraph.alternateContents[].rawXML where contains direct-child OMML in fallback section`, (d) nested wrapper case from (b)+(c) recursion. Walker uses `OMMLParser.parse(xml:).visibleText` for text extraction. Implements Decision 3 (lightweight unified pattern, no protocol).
- [x] 3.7 Wire `flattenedDisplayText()` (`InsertLocation.swift:278-294`) to consume walker output — append OMML visible text fragments at positions dictated by `position: Int?` field per Decision 6 source-XML ordering. Implements Decision 1 (Bilateral fix scope — read AND write, not read-only) read side.
- [x] 3.8 Verify GREEN: 3.1, 3.2, 3.3, 3.4, 3.5 all pass — closes che-word-mcp #99, #100, #101, #102 read side.

## 4. Replace-Side OMML Boundary Detection (Decision 2 — REPLACE semantic = opaque OMML refuse Semantic A)

- [x] 4.1 RED test: `replaceInParagraphSurfaces(find: "here", with: "there")` on the standard `<w:p>` direct-child OMML reproducer returns `ReplaceResult.replaced(count: 1)` — wholly-within-`<w:t>` mutation proceeds. Covers Requirement "replaceInParagraphSurfaces detects OMML boundaries" (wholly-within scenario).
- [x] 4.2 RED test: `replaceInParagraphSurfaces(find: "eq δ here", with: "ref X")` on the same reproducer returns `ReplaceResult.refusedDueToOMMLBoundary(occurrences:)` with `occurrences[0].matchSpan == 4..<13` and `occurrences[0].ommlSpans == [7..<8]`. Verifies no mutation occurs (paragraph XML byte-identical pre/post call). Covers Decision 2 + Requirement "replaceInParagraphSurfaces detects OMML boundaries" cross-OMML scenario.
- [x] 4.3 RED test: paragraph contains find string twice — once wholly within `<w:t>`, once crossing OMML — `replaceInParagraphSurfaces` result combines both: `count > 0` for replaced AND non-empty `occurrences` for refused. Covers Requirement "replaceInParagraphSurfaces detects OMML boundaries" mixed scenario. (Concrete combinator type — single ReplaceResult value with both signals or struct wrapping count+occurrences — chosen during 4.6 implementation; spec only requires both signals carried.)
- [x] 4.4 Extend `packages/ooxml-swift/Sources/OOXMLSwift/Models/TextReplacementEngine.swift` `replaceInContentXML` to expose offset-map of `<w:t>` boundary regions in returned struct (or add a sibling helper `walkOMMLBoundaries` that returns OMML span regions in flattened-text coordinates). Single source of truth for offset-map computation reused by 4.6.
- [x] 4.5 Change `Document.replaceInParagraphSurfaces` (`packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift:326-369`) return type from `Int` to `ReplaceResult`. BREAKING for ooxml-swift internal callers — update all internal callsites in same commit. Document the breaking change in commit message.
- [x] 4.6 Implement OMML boundary detection in `replaceInParagraphSurfaces` per Decision 2 (Semantic A opaque OMML refuse): for each occurrence of find-string match, check if `matchSpan` intersects any `ommlSpan` from walker (3.6) reused for write-side. If intersects → emit `Occurrence` to `refusedDueToOMMLBoundary`. If not → proceed with mutation via TextReplacementEngine.replace and emit to `replaced(count:)`. Implements Decision 1 bilateral fix write side.
- [x] 4.7 Verify GREEN: 4.1, 4.2, 4.3 all pass.

## 5. Mirror Invariant Verification + Documentation (Decision 1, Decision 8)

- [x] 5.1 RED test for Requirement "Mirror invariant — same surface coverage, asymmetric on OMML detected": pin that `flattenedDisplayText` and `replaceInParagraphSurfaces` walk the same 4 wrapper positions (probe via instrumented paragraph that records visit calls). Asymmetric handling expected — read includes OMML text, write refuses on cross. Covers all 4 scenarios from the requirement.
- [x] 5.2 Verify mirror invariant GREEN after Decision 1 bilateral fix lands.
- [x] 5.3 Refresh `InsertLocation.swift:264-266` docstring per Decision 8 (Documentation refresh — embrace asymmetry explicitly): rewrite to say "Mirrors the surface coverage of `replaceInParagraphSurfaces` (same wrappers walked). Within each surface, reads expose all visible text including direct-child OMML; writes treat OMML as opaque text markers (analogous to `<w:delText>` / `<w:instrText>` skipping) — replacements crossing OMML boundaries refuse with `ReplaceResult.refusedDueToOMMLBoundary(occurrences:)`, replacements wholly within `<w:r><w:t>` ranges proceed normally." Reference both new capability specs by name. This task also closes che-word-mcp #103.
- [x] 5.4 Update all ooxml-swift internal callers of `replaceInParagraphSurfaces` to handle new `ReplaceResult` enum (find by `grep -rn replaceInParagraphSurfaces packages/ooxml-swift/Sources/`). Convert each call from `count = try replaceInParagraphSurfaces(...)` to switch on result. Maintain previous semantics (sum counts, propagate failures).

## 6. Library Design Principles Conformance (Decision 5)

- [x] 6.1 RED test (or design-time review entry, since principles are normative not directly testable): the cluster fix design refuses Semantic B (cross-OMML mutation preserving OMML — produces "see δref X") and Semantic C default (silent OMML drop) per Requirement "Correctness primacy — refusal over incorrect approximation". Captured in design.md Decision 2 alternatives table with concrete refused outputs. Verify design.md Decision 2 contains the worked example.
- [x] 6.2 RED test (design-time review entry): the cluster fix conforms to Requirement "Human-like operations — no surprising state, no silent destruction" — default behavior refuses cross-OMML mutation (no silent destruction); future escape hatch (`omml_handling: "drop"`) deferred per Non-Goals (explicit opt-in pattern documented). Verify design.md Decision 2 + Non-Goals reference the escape-hatch deferral.
- [x] 6.3 Document principle conformance per Requirement "Principles govern all current and future ooxml-swift mutators": confirm design.md Decision 2 explicitly evaluates both principles for this change. Future Spectra changes touching mutators MUST follow same Decisions-section pattern. (No code change — design.md already complete; this task is a self-audit checkpoint before archive.)

## 7. Round-Trip Regression + Release Prep

- [x] 7.1 RED test: round-trip via `DocxReader.read(from: url)` → no mutation → `DocxWriter.write(to: outURL)` for each of the 4 wrapper-position fixtures produces byte-identical `word/document.xml` content for the OMML elements (verify via diff). Pins Requirement "Direct-child OMML storage remains raw passthrough" round-trip clause.
- [x] 7.2 Run full ooxml-swift test suite (`swift test`). Verify: all existing tests pass (no regression), new tests from 1.1, 2.1-2.4, 3.1-3.8, 4.1-4.7, 5.1, 6.1-6.2, 7.1 all pass, and `testDocumentContentEqualityInvariant` matrix-pin still holds (round-trip fidelity unchanged because Decision 4 raw-passthrough preserved).
- [x] 7.3 [P] Add `packages/ooxml-swift/CHANGELOG.md` `[Unreleased]` entry describing: Decision 1 bilateral fix scope, new `ReplaceResult` public enum (Decision 7) BREAKING for `replaceInParagraphSurfaces` return type, Decision 5 library principles spec, cluster close of che-word-mcp #99/#100/#101/#102/#103. Reference both new capability specs by name.

## 8. Cluster Issue Close Preparation

- [x] 8.1 Verify cluster issue references: each test in `Issue99FlattenReplaceOMMLBilateralTests.swift` covering a wrapper position MUST cite the corresponding issue number (e.g., `testFlattenIncludesOMathDirectChildOfParagraph_Issue99`, `..._Issue100`, `..._Issue101`, `..._Issue102`). Commit messages reference all 5 issues via `Refs PsychQuant/che-word-mcp#99 #100 #101 #102 #103`.
- [x] 8.2 #103 docstring sync verified per Decision 8 (Documentation refresh — embrace asymmetry explicitly): cross-check that 5.3 produced the new docstring text matching the spec wording. Confirm #103 closes by reference to this Spectra change in commit body without separate docs commit. Goals (proposal coverage of all 5 issues) and Non-Goals (equation content mutation, escape hatch, typed field promotion, symmetric mirror, visitor protocol — all deferred or rejected) re-verified for scope alignment before archive.


## 9. Design Decisions Cross-Reference (analyzer cross-check)

This section pins each design.md `### Decision` heading to the implementing tasks. Required by analyzer cross-reference rule.

- [x] 9.1 Decision 1: Bilateral fix scope (read AND write), not read-only — implemented across tasks 3.7 (read side wire-up) AND 4.6 (write side boundary detection). Verified together by 5.2.
- [x] 9.2 Decision 2: REPLACE semantic = opaque OMML refuse (Semantic A) — implemented in task 4.6, RED-pinned by 4.2 + 4.3, principle conformance recorded by 6.1.
- [x] 9.3 Decision 3: Lightweight unified walker, not protocol abstraction — implemented in task 3.6, no protocol introduced; module-private helper signature confirmed.
- [x] 9.4 Decision 4: Raw passthrough preserved — direct-child OMML stays in `unrecognizedChildren` / `HyperlinkChild.rawXML` / `AlternateContent.rawXML` — pinned by tasks 3.5 (walker reads from raw) AND 7.1 (round-trip preserves raw XML).
- [x] 9.5 Decision 5: Library design principles as foundational normative invariants — implemented as new `ooxml-library-design-principles` spec capability; conformance verified by tasks 6.1, 6.2, 6.3.
- [x] 9.6 Decision 6: Position ordering = source XML order — implemented in task 3.7 walker output ordering; pinned by RED test in task 3.1.
- [x] 9.7 Decision 7: ReplaceResult typed enum with structured occurrence info — implemented in tasks 2.1-2.4; consumed by 4.5 + 4.6.
- [x] 9.8 Decision 8: Documentation refresh — embrace asymmetry explicitly — implemented in task 5.3 (docstring rewrite at `InsertLocation.swift:264-266`); cluster issue #103 closes via this task.

## 10. Requirement Cross-Reference (analyzer cross-check)

This section pins each spec `### Requirement` title verbatim to the implementing tasks.

- [x] 10.1 Requirement: flattenedDisplayText walks direct-child OMML at all 4 wrapper positions — pinned by tasks 3.1 (paragraph), 3.2 (hyperlink), 3.3 (Fallback), 3.4 (nested); implementation in 3.6 + 3.7; verification in 3.8.
- [x] 10.2 Requirement: replaceInParagraphSurfaces detects OMML boundaries at all 4 wrapper positions — pinned by tasks 4.1 (wholly-within wrapper position 1), 4.2 (cross-OMML wrapper position 1), 4.3 (mixed). Wrapper positions 2/3/4 inherit walker coverage from task 3.6 (single source of truth) and are co-verified by mirror parity test 5.1.
- [x] 10.3 Requirement: ReplaceResult enum carries informative refusal occurrences — implemented in tasks 2.1, 2.2, 2.3.
- [x] 10.4 Requirement: Mirror invariant — same surface coverage, asymmetric on OMML detected — pinned by task 5.1, GREEN by 5.2, documented by 5.3.
- [x] 10.5 Requirement: Direct-child OMML storage remains raw passthrough — pinned by tasks 3.5 (walker reads from raw) and 7.1 (round-trip XML byte-identical).
- [x] 10.6 Requirement: Correctness primacy — refusal over incorrect approximation — design-time conformance recorded in task 6.1.
- [x] 10.7 Requirement: Human-like operations — no surprising state, no silent destruction — design-time conformance recorded in task 6.2.
- [x] 10.8 Requirement: Principles govern all current and future ooxml-swift mutators — meta-conformance audit in task 6.3.
