# ooxml-edit-algebra-runtime Specification

## Purpose

TBD - created by archiving change 'ooxml-edit-algebra-implementation'. Update Purpose after archive.

## Requirements

### Requirement: Edit Protocol Public API

The `ooxml-swift` library SHALL provide a `public protocol Edit` in `Sources/OOXMLSwift/EditAlgebra/Edit.swift` declaring at minimum:

```swift
public protocol Edit {
    func apply(to document: WordDocument) throws -> WordDocument
    func lower() -> [OOXMLEdit]
}
```

The library SHALL provide `public enum EditError: Error, Equatable` with at minimum the cases: `pathNotFound(ElementID)`, `preserveViolation(part: String, expected: String, actual: String)`, `unsupportedOperation(String)`, `notImplemented(String)`, `operationLogFailure(underlying: String)`.

#### Scenario: Edit protocol defines apply + lower

- **WHEN** a caller imports OOXMLSwift and declares a type conforming to `Edit`
- **THEN** the type MUST implement `apply(to: WordDocument) throws -> WordDocument` and `lower() -> [OOXMLEdit]`

#### Scenario: EditError cases are Equatable

- **WHEN** two `EditError.pathNotFound(elementID)` values are compared with the same ElementID
- **THEN** they SHALL be Equatable-equal


<!-- @trace
source: ooxml-edit-algebra-implementation
updated: 2026-06-01
code:
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-051714.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-094041.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-130250.log
-->

---
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
- **THEN** the resulting WordDocument's OperationLog SHALL contain a new `Operation.insertParagraphAfter(after: paraID, paragraph: ParagraphPayload(text: "Hello", styleId: nil))` entry

##### Example: insertParagraph emits expected Operation

- **GIVEN** a WordDocument with paragraph ID `p1` and empty OperationLog
- **WHEN** `OOXMLEdit.insertParagraph(after: p1, content: "Hello", styleId: nil).apply(to: doc)` is called
- **THEN** the new WordDocument's OperationLog has exactly 1 entry of type `Operation.insertParagraphAfter` with `after == p1` and `paragraph.text == "Hello"`

#### Scenario: OOXMLEdit.setBold routes to Operation.setRunFormat

- **WHEN** `OOXMLEdit.setBold(target: runID, value: true).apply(to: doc)` is called
- **THEN** the resulting WordDocument's OperationLog SHALL contain a new `Operation.setRunFormat` entry whose `RunFormatPayload.bold == true`

#### Scenario: OOXMLEdit.insertHyperlink routes to atomic composite Operations

- **WHEN** `OOXMLEdit.insertHyperlink(target: runID, href: url, displayText: "example").apply(to: doc)` is called AND both the document.xml node insertion AND the rels-part attribute update succeed
- **THEN** the new WordDocument's OperationLog SHALL contain BOTH the `Operation.insertNode` entry (for the `<w:hyperlink>` element) AND the `Operation.updateAttribute` entry (for the Relationship Target)
- **AND** if either sub-operation fails validation, NEITHER SHALL be appended (atomic rollback at Edit level)


<!-- @trace
source: ooxml-edit-algebra-implementation
updated: 2026-06-01
code:
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-051714.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-094041.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-130250.log
-->

---
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


<!-- @trace
source: ooxml-edit-algebra-implementation
updated: 2026-06-01
code:
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-051714.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-094041.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-130250.log
-->

---
### Requirement: WordDocument.apply Public Method

The `WordDocument` type (declared in `Sources/OOXMLSwift/Models/Document.swift`) SHALL expose `public func apply(_ edit: any Edit) throws -> WordDocument`. The apply method is implemented as an extension in `Sources/OOXMLSwift/EditAlgebra/WordDocument+Apply.swift`. This method SHALL:

1. Internally route the edit's emitted Operations through the existing `OperationLog` and `OperationReducer.materialize` infrastructure
2. Return a new WordDocument instance (immutable apply — input WordDocument unchanged)
3. NOT replace or modify the existing `applyOverlay`, `markPartDirty`, `partTree`, `xmlTrees` APIs
4. **(PHASED — Phase 2c follow-up)** Throw `EditError.pathNotFound(elementID)` if any target ElementID does not resolve in the input WordDocument. Until phased delivery lands, target-not-found surfaces via Reducer-wrapping as `EditError.operationLogFailure(underlying: "...elementNotFound...")`.
5. **(PHASED — Phase 2c follow-up)** Throw `EditError.preserveViolation(...)` if the resulting WordDocument's c14n form differs from input on a part NOT targeted by the edit (defensive check). Until phased delivery lands, the apply pipeline trusts the Reducer's per-op semantics for non-target preservation.
6. Wrap any `OperationReducer.materialize` error as `EditError.operationLogFailure(underlying: ...)`

The library SHALL also provide `public func apply<S: Sequence>(_ edits: S) throws -> WordDocument where S.Element == any Edit` for sequence-folding apply.

**Phased acceptance note**: Items #4 and #5 are normative end-state requirements but ship in a later phase (see this change's design.md Decision 6 errata — depends on multi-part scoping fix + per-op target extraction). Items #1, #2, #3, #6 + sequence-folding are required for initial acceptance.

#### Scenario: apply returns new immutable WordDocument

- **WHEN** `let d2 = try d1.apply(OOXMLEdit.setBold(target: runID, value: true))`
- **THEN** `d2` is a new WordDocument with the edit applied AND `d1` is bytewise-equal-after-c14n to its state before the call

#### Scenario: apply throws pathNotFound on missing ElementID

- **WHEN** `OOXMLEdit.setBold(target: invalidRunID, value: true).apply(to: doc)` is called where `invalidRunID` doesn't resolve in `doc`
- **THEN** the call throws `EditError.pathNotFound(invalidRunID)`

#### Scenario: apply preserves existing API surface

- **WHEN** existing callers of `WordDocument.applyOverlay()`, `WordDocument.markPartDirty(_:)`, `WordDocument.partTree(at:)`, `WordDocument.xmlTrees` continue compiling and running after this change
- **THEN** their behavior MUST be unchanged


<!-- @trace
source: ooxml-edit-algebra-implementation
updated: 2026-06-01
code:
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-051714.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-094041.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-130250.log
-->

---
### Requirement: Property-Based Fully-Faithful-Functor Tests

The `ooxml-swift` test suite SHALL include `Tests/OOXMLSwiftTests/EditAlgebraTests/FullyFaithfulFunctorTests.swift` using `swift-testing` `@Test(arguments:)` parameterized tests that:

1. Cover at least 5 implemented `OOXMLEdit` cases (all 5 canonical: insertParagraph, insertParagraphBefore, setBold, insertHyperlink, removeParagraph)
2. Use the existing `RealWorldDocxRoundTripSmokeTests` NTPU thesis fixture loader as the input WordDocument source
3. For each Edit case, generate at least 100 randomized argument samples within valid input domain
4. For each sample, assert: the resulting WordDocument's c14n form on subtrees NOT in the Edit's target path is bytewise-equal to the input's c14n form (canonical-identity invariant)

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


<!-- @trace
source: ooxml-edit-algebra-implementation
updated: 2026-06-01
code:
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-051714.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-094041.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-130250.log
-->

---
### Requirement: CD Diagrams Land in Documentation

For each of the 5 implemented `OOXMLEdit` cases AND the 3 implemented `WordEdit` cases, a commutative diagram (ASCII ladder, IETF-RFC style) SHALL be added to `docs/edit-algebra-cd-discipline.md` (extending the foundation's ADR-002 Worked Examples).

Each CD diagram SHALL show:
1. The Word UI action OR schema-level change (top arrow)
2. The `τ` translation between Word semantics and Swift representation (vertical arrows)
3. The commutativity claim (commute is the assertion the property test validates)

#### Scenario: CD diagram for setBold matches foundation ADR-002 Example 2 format

- **WHEN** a reader opens `docs/edit-algebra-cd-discipline.md` and looks for the `OOXMLEdit.setBold` CD diagram
- **THEN** the diagram SHALL follow the same ASCII-ladder format as foundation ADR-002 Worked Example 2


<!-- @trace
source: ooxml-edit-algebra-implementation
updated: 2026-06-01
code:
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-051714.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-094041.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-130250.log
-->

---
### Requirement: Edit Apply Performance Within Foundation Baseline

The `WordDocument.apply(_ edit:)` method's performance on the NTPU thesis fixture SHALL be within 10% of the baseline measured by direct `OperationLog` manipulation + `OperationReducer.materialize`. If a regression exceeds 10%, this Requirement is NOT satisfied and the implementation MUST be optimized before merge.

#### Scenario: insertParagraph apply benchmark

- **WHEN** `OOXMLEdit.insertParagraph(after: paraID, content: "test", styleId: nil).apply(to: ntpuDoc)` is timed
- **THEN** the average over 100 invocations SHALL be within 10% of the time for the equivalent direct `Operation.insertParagraphAfter` log-append + materialize cycle


<!-- @trace
source: ooxml-edit-algebra-implementation
updated: 2026-06-01
code:
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-051714.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-094041.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-130250.log
-->

---
### Requirement: Foundation Spec Compliance

This change's implementation SHALL satisfy all foundation `ooxml-edit-algebra` capability spec Requirements (8 Requirements documented in `openspec/changes/ooxml-edit-isomorphism-foundation/specs/ooxml-edit-algebra/spec.md`). Specifically:

- Foundation Requirement "Canonical-Identity Round-Trip Contract" — satisfied via property tests
- Foundation Requirement "Edit Type Algebra" — satisfied via Edit protocol + 5 OOXMLEdit cases
- Foundation Requirement "Fully Faithful Functor Property (Naturality of lower)" — satisfied via NaturalityTests
- Foundation Requirement "CD Review Discipline for Edit Cases" — satisfied via PR template enforcement + CD diagrams in docs
- Foundation Requirement "Edit Apply Surface on Document" — satisfied via `WordDocument.apply(_:)` public method (foundation Requirement title uses the conceptual name "Document"; the actual ooxml-swift type is `WordDocument`)
- Foundation Requirement "Word UI Behavior as Ground Truth for WordEdit Semantics" — satisfied via WordEdit cases referencing Word UI verbs (applyBold ↔ Cmd-B, applyLink ↔ Cmd-K, etc.)
- Foundation Requirement "Property-Based Functor Tests on NTPU Thesis Fixture" — satisfied via FullyFaithfulFunctorTests
- Foundation Requirement "Downstream Architectural Compliance Documentation" — satisfied as ADVISORY (this change does not itself enforce downstream compliance; che-word-mcp#162 + word-builder-swift lens migration trackers continue)

#### Scenario: foundation spec validate passes

- **WHEN** `spectra validate ooxml-edit-isomorphism-foundation` runs after this change ships
- **THEN** it SHALL continue passing (foundation spec is not modified by this change)

<!-- @trace
source: ooxml-edit-algebra-implementation
updated: 2026-06-01
code:
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-051714.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-094041.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-130250.log
-->