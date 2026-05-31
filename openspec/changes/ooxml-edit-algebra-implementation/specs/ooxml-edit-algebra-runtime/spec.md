## ADDED Requirements

### Requirement: Edit Protocol Public API

The `ooxml-swift` library SHALL provide a `public protocol Edit` in `Sources/OOXMLSwift/EditAlgebra/Edit.swift` declaring at minimum:

```swift
public protocol Edit {
    func apply(to document: Document) throws -> Document
    func lower() -> [OOXMLEdit]
}
```

The library SHALL provide `public enum EditError: Error, Equatable` with at minimum the cases: `pathNotFound(ElementID)`, `preserveViolation(part: String, expected: String, actual: String)`, `unsupportedOperation(String)`, `notImplemented(String)`, `operationLogFailure(underlying: String)`.

#### Scenario: Edit protocol defines apply + lower

- **WHEN** a caller imports OOXMLSwift and declares a type conforming to `Edit`
- **THEN** the type MUST implement `apply(to: Document) throws -> Document` and `lower() -> [OOXMLEdit]`

#### Scenario: EditError cases are Equatable

- **WHEN** two `EditError.pathNotFound(elementID)` values are compared with the same ElementID
- **THEN** they SHALL be Equatable-equal

### Requirement: OOXMLEdit Enum with 5 Canonical Cases

The `ooxml-swift` library SHALL provide `public enum OOXMLEdit: Edit, Equatable, Sendable` in `Sources/OOXMLSwift/EditAlgebra/OOXMLEdit.swift` with at minimum these 5 cases:

```swift
case insertParagraph(after: ElementID, content: String, styleId: String?)
case insertParagraphBefore(before: ElementID, content: String, styleId: String?)
case setBold(target: ElementID, value: Bool)
case insertHyperlink(target: ElementID, href: URL, displayText: String?)
case removeParagraph(target: ElementID)
```

Each case SHALL implement `Edit` protocol's `apply(to:)` by emitting one or more `Operation` cases via the mapping table documented in this change's design.md Decision 1.

`OOXMLEdit.lower()` SHALL return `[self]` (identity — OOXMLEdit IS the syntactic layer).

#### Scenario: OOXMLEdit.insertParagraph routes to Operation.insertParagraphAfter

- **WHEN** `OOXMLEdit.insertParagraph(after: paraID, content: "Hello", styleId: nil).apply(to: doc)` is called
- **THEN** the resulting Document's OperationLog SHALL contain a new `Operation.insertParagraphAfter(after: paraID, paragraph: ParagraphPayload(text: "Hello", styleId: nil))` entry

##### Example: insertParagraph emits expected Operation

- **GIVEN** a Document with paragraph ID `p1` and empty OperationLog
- **WHEN** `OOXMLEdit.insertParagraph(after: p1, content: "Hello", styleId: nil).apply(to: doc)` is called
- **THEN** the new Document's OperationLog has exactly 1 entry of type `Operation.insertParagraphAfter` with `after == p1` and `paragraph.text == "Hello"`

#### Scenario: OOXMLEdit.setBold routes to Operation.setRunFormat

- **WHEN** `OOXMLEdit.setBold(target: runID, value: true).apply(to: doc)` is called
- **THEN** the resulting Document's OperationLog SHALL contain a new `Operation.setRunFormat` entry whose `RunFormatPayload.bold == true`

#### Scenario: OOXMLEdit.insertHyperlink routes to atomic composite Operations

- **WHEN** `OOXMLEdit.insertHyperlink(target: runID, href: url, displayText: "example").apply(to: doc)` is called AND both the document.xml node insertion AND the rels-part attribute update succeed
- **THEN** the new Document's OperationLog SHALL contain BOTH the `Operation.insertNode` entry (for the `<w:hyperlink>` element) AND the `Operation.updateAttribute` entry (for the Relationship Target)
- **AND** if either sub-operation fails validation, NEITHER SHALL be appended (atomic rollback at Edit level)

### Requirement: WordEdit Enum with 3 Canonical Cases

The `ooxml-swift` library SHALL provide `public enum WordEdit: Edit, Equatable, Sendable` in `Sources/OOXMLSwift/EditAlgebra/WordEdit.swift` with at minimum:

```swift
case applyBold(range: WordRange)
case applyLink(range: WordRange, url: URL)
case applyInsertParagraph(after: ParagraphRef, content: String)
```

And `public struct WordRange: Equatable, Sendable` with `startRun: ElementID`, `startOffset: Int`, `endRun: ElementID`, `endOffset: Int`.

`WordEdit.lower()` SHALL return `[OOXMLEdit]` with at minimum 1 element per affected paragraph. For range-crossing-paragraph cases, lower() returns N-element list (one per paragraph), per foundation ADR-002 Worked Example 4.

#### Scenario: WordEdit.applyBold within single paragraph lowers to single OOXMLEdit

- **WHEN** `WordEdit.applyBold(range:)` is called with a range covering text within ONE paragraph
- **THEN** `lower()` returns a list of exactly 1 `OOXMLEdit.setBold` element

#### Scenario: WordEdit.applyBold across paragraph boundary lowers to multiple OOXMLEdit

- **WHEN** `WordEdit.applyBold(range:)` is called with a range spanning text across 2 paragraphs
- **THEN** `lower()` returns a list of exactly 2 `OOXMLEdit.setBold` elements (one per paragraph)

#### Scenario: WordEdit.lower() is total (no partial functions)

- **WHEN** any defined `WordEdit` case has `lower()` called
- **THEN** the call SHALL return a non-empty `[OOXMLEdit]` list (never returns empty array or throws)

### Requirement: Document.apply Public Method

The `Document` type SHALL expose `public func apply(_ edit: any Edit) throws -> Document` in `Sources/OOXMLSwift/Models/Document.swift`. This method SHALL:

1. Internally route the edit's emitted Operations through the existing `OperationLog` and `OperationReducer.materialize` infrastructure
2. Return a new Document instance (immutable apply — input Document unchanged)
3. NOT replace or modify the existing `applyOverlay`, `markPartDirty`, `partTree`, `xmlTrees` APIs
4. Throw `EditError.pathNotFound(elementID)` if any target ElementID does not resolve in the input Document
5. Throw `EditError.preserveViolation(...)` if the resulting Document's c14n form differs from input on a part NOT targeted by the edit (defensive check)
6. Wrap any `OperationReducer.materialize` error as `EditError.operationLogFailure(underlying: ...)`

The library SHALL also provide `public func apply<S: Sequence>(_ edits: S) throws -> Document where S.Element == any Edit` for sequence-folding apply.

#### Scenario: apply returns new immutable Document

- **WHEN** `let d2 = try d1.apply(OOXMLEdit.setBold(target: runID, value: true))`
- **THEN** `d2` is a new Document with the edit applied AND `d1` is bytewise-equal-after-c14n to its state before the call

#### Scenario: apply throws pathNotFound on missing ElementID

- **WHEN** `OOXMLEdit.setBold(target: invalidRunID, value: true).apply(to: doc)` is called where `invalidRunID` doesn't resolve in `doc`
- **THEN** the call throws `EditError.pathNotFound(invalidRunID)`

#### Scenario: apply preserves existing API surface

- **WHEN** existing callers of `Document.applyOverlay()`, `Document.markPartDirty(_:)`, `Document.partTree(at:)`, `Document.xmlTrees` continue compiling and running after this change
- **THEN** their behavior MUST be unchanged

### Requirement: Property-Based Fully-Faithful-Functor Tests

The `ooxml-swift` test suite SHALL include `Tests/OOXMLSwiftTests/EditAlgebraTests/FullyFaithfulFunctorTests.swift` using `swift-testing` `@Test(arguments:)` parameterized tests that:

1. Cover at least 5 implemented `OOXMLEdit` cases (all 5 canonical: insertParagraph, insertParagraphBefore, setBold, insertHyperlink, removeParagraph)
2. Use the existing `RealWorldDocxRoundTripSmokeTests` NTPU thesis fixture loader as the input Document source
3. For each Edit case, generate at least 100 randomized argument samples within valid input domain
4. For each sample, assert: the resulting Document's c14n form on subtrees NOT in the Edit's target path is bytewise-equal to the input's c14n form (canonical-identity invariant)

The suite SHALL also include `Tests/OOXMLSwiftTests/EditAlgebraTests/NaturalityTests.swift` asserting `(WordEdit.a ∘ WordEdit.b).lower() == WordEdit.a.lower() ∘ WordEdit.b.lower()` for at least 50 randomized pairs of each composable WordEdit pair-type (applyBold ∘ applyLink, applyBold ∘ applyInsertParagraph, applyLink ∘ applyInsertParagraph).

#### Scenario: Property test passes for setBold canonical-identity

- **WHEN** the property test for `OOXMLEdit.setBold` is executed
- **THEN** for 100 randomized `target: ElementID × value: Bool` samples against the NTPU thesis fixture, the canonical-identity invariant holds (unmodified Runs remain c14n-equal to input)

#### Scenario: Naturality property test passes for applyBold ∘ applyLink

- **WHEN** the naturality test runs 50 randomized WordRange pairs (range1 for applyBold, range2 for applyLink)
- **THEN** `(WordEdit.applyBold(range1) ∘ WordEdit.applyLink(range2)).lower()` produces the same `[OOXMLEdit]` list (allowing for reordering of independent operations) as `WordEdit.applyBold(range1).lower() ∘ WordEdit.applyLink(range2).lower()`

#### Scenario: Property test failure logs reproducible seed

- **WHEN** a property test fails on input N
- **THEN** the test output SHALL include the failing input's seed value (so the failure is reproducible)

### Requirement: CD Diagrams Land in Documentation

For each of the 5 implemented `OOXMLEdit` cases AND the 3 implemented `WordEdit` cases, a commutative diagram (ASCII ladder, IETF-RFC style) SHALL be added to `docs/edit-algebra-cd-discipline.md` (extending the foundation's ADR-002 Worked Examples).

Each CD diagram SHALL show:
1. The Word UI action OR schema-level change (top arrow)
2. The `τ` translation between Word semantics and Swift representation (vertical arrows)
3. The commutativity claim (commute is the assertion the property test validates)

#### Scenario: CD diagram for setBold matches foundation ADR-002 Example 2 format

- **WHEN** a reader opens `docs/edit-algebra-cd-discipline.md` and looks for the `OOXMLEdit.setBold` CD diagram
- **THEN** the diagram SHALL follow the same ASCII-ladder format as foundation ADR-002 Worked Example 2

### Requirement: Edit Apply Performance Within Foundation Baseline

The `Document.apply(_ edit:)` method's performance on the NTPU thesis fixture SHALL be within 10% of the baseline measured by direct `OperationLog` manipulation + `OperationReducer.materialize`. If a regression exceeds 10%, this Requirement is NOT satisfied and the implementation MUST be optimized before merge.

#### Scenario: insertParagraph apply benchmark

- **WHEN** `OOXMLEdit.insertParagraph(after: paraID, content: "test", styleId: nil).apply(to: ntpuDoc)` is timed
- **THEN** the average over 100 invocations SHALL be within 10% of the time for the equivalent direct `Operation.insertParagraphAfter` log-append + materialize cycle

### Requirement: Foundation Spec Compliance

This change's implementation SHALL satisfy all foundation `ooxml-edit-algebra` capability spec Requirements (8 Requirements documented in `openspec/changes/ooxml-edit-isomorphism-foundation/specs/ooxml-edit-algebra/spec.md`). Specifically:

- Foundation Requirement "Canonical-Identity Round-Trip Contract" — satisfied via property tests
- Foundation Requirement "Edit Type Algebra" — satisfied via Edit protocol + 5 OOXMLEdit cases
- Foundation Requirement "Fully Faithful Functor Property (Naturality of lower)" — satisfied via NaturalityTests
- Foundation Requirement "CD Review Discipline for Edit Cases" — satisfied via PR template enforcement + CD diagrams in docs
- Foundation Requirement "Edit Apply Surface on Document" — satisfied via Document.apply(_:) public method
- Foundation Requirement "Word UI Behavior as Ground Truth for WordEdit Semantics" — satisfied via WordEdit cases referencing Word UI verbs (applyBold ↔ Cmd-B, applyLink ↔ Cmd-K, etc.)
- Foundation Requirement "Property-Based Functor Tests on NTPU Thesis Fixture" — satisfied via FullyFaithfulFunctorTests
- Foundation Requirement "Downstream Architectural Compliance Documentation" — satisfied as ADVISORY (this change does not itself enforce downstream compliance; che-word-mcp#162 + word-builder-swift lens migration trackers continue)

#### Scenario: foundation spec validate passes

- **WHEN** `spectra validate ooxml-edit-isomorphism-foundation` runs after this change ships
- **THEN** it SHALL continue passing (foundation spec is not modified by this change)
