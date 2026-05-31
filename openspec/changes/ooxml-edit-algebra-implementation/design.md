## Context

`ooxml-edit-isomorphism-foundation` (PsychQuant/macdoc#99, merged in PR #106 commit `648e5a5`) locked the architectural contract via:
- Capability spec `ooxml-edit-algebra` (8 normative Requirements with SHALL/MUST + Scenarios + 3 SBE Examples)
- 9 ADRs (canonical-identity round-trip, Edit-as-first-class, two-layer algebra, module split, operation naming, Word UI ground truth, conformance suite, deferred lens migration, downstream rerouting)
- 4 canonical CD diagrams in design.md ADR-002 Worked Examples (insertParagraph body-level, setBold run-level, insertHyperlink dual-part atomic, applyBold range-crossing)
- PR template requiring CD diagram for `EditAlgebra/` PRs (already in main: `.github/PULL_REQUEST_TEMPLATE.md`)
- CD discipline README at `docs/edit-algebra-cd-discipline.md`
- Coordination Relationship section in `word-aligned-state-sync` design.md

That foundation's apply phase was scoped to **decision-pinning + mechanical artifacts only** — Swift implementation (23 tasks) was deferred to this Phase 2 Spectra change.

### What's changed since #99's design.md was written

#99 ADR-002 stated runtime backing was the v0.13.0+ `applyOverlay()` / `markDirty()` machinery. Between #99 being written and now, ooxml-swift v0.31.x shipped the **OpLog runtime mechanism** that the `word-aligned-state-sync` Spectra change had been driving. The actual runtime on current main:

| File | Public type |
|---|---|
| `OOXMLSwift/OpLog/Operation.swift` | `public enum Operation: Equatable, Sendable` with ~20 cases |
| `OOXMLSwift/OpLog/OperationLog.swift` | `public struct OperationLog: Equatable, Sendable` (append-only log) |
| `OOXMLSwift/OpLog/OperationReducer.swift` | `public enum OperationReducer` with `static func materialize(log: OperationLog, base: XmlTree) throws -> XmlTree` |
| `OOXMLSwift/OpLog/OperationLog+JSONL.swift` | JSONL serialization |
| `OOXMLSwift/OpLog/OperationReducerCache.swift` | Async cached materialize |
| `OOXMLSwift/OpLog/ElementID.swift` | `public struct ElementID: Equatable, Hashable, Sendable, Codable` |

This is the canonical event-sourced runtime macdoc's `swift-as-document-source.md` design document describes. **Edit type's true backing is Operation/OperationLog/Reducer, not overlay/markDirty.** This change captures that reality.

## Goals / Non-Goals

**Goals:**

1. Ship the `Edit` protocol + `OOXMLEdit` enum + `WordEdit` enum + `EditError` enum in `EditAlgebra/` subdirectory of ooxml-swift, conforming to the foundation's capability spec
2. Route `Edit.apply(to:)` through v0.31.x `Operation` / `OperationLog` / `OperationReducer.materialize` — NOT through overlay/markDirty (correcting the foundation's ADR-002 backing assumption)
3. Implement **5 OOXMLEdit cases** (insertParagraph, setBold, insertHyperlink, plus 2 selected during apply per ADR-005)
4. Implement **3 WordEdit cases** with `lower()` (applyBold, applyLink, applyInsertParagraph)
5. Ship **property-based fully-faithful-functor tests** on NTPU thesis fixture validating canonical-identity invariant + naturality of `lower()`
6. Pass all foundation acceptance criteria (capability spec Requirements satisfied with code that compiles + tests pass)

**Non-Goals:**

- `word-builder-swift` lens migration (per foundation ADR-008 — separate follow-up)
- `che-word-mcp` boundary refactor (per che-word-mcp#162 — depends on this ship)
- Operation enum extension — uses what v0.31.x shipped; gap filled via `Operation.insertNode` fallback or upstream ooxml-swift issue
- Full WordEdit surface beyond the 3 canonical cases
- Automated CD diagram validation tooling — manual reviewer discipline stays per foundation ADR-002
- Migrating existing che-word-mcp tools to use `Document.apply(_ edit:)` — current Document-mutation API stays
- Module split implementation (`OOXMLSyntax` / `OOXMLSemantic` / `OOXMLDSL`) — foundation ADR-004 deferred to its own change; this change adds `EditAlgebra/` subdirectory in current `OOXMLSwift` module
- Performance optimization — first ship is correctness; benchmark if regression > 10% on NTPU fixture round-trip

## Decisions

### Decision 1: Edit ↔ Operation mapping table (the central design artifact)

Each `OOXMLEdit` case maps to one or more `Operation` cases. This mapping is the public contract that makes property tests possible. Below is the canonical table for the 5 in-scope cases:

| OOXMLEdit case | Maps to Operation case(s) | Notes |
|---|---|---|
| `OOXMLEdit.insertParagraph(after: ElementID, content: String, styleId: String?)` | `Operation.insertParagraphAfter(after: ElementID, paragraph: ParagraphPayload)` | 1:1 map. `ParagraphPayload(text: content, styleId: styleId)`. |
| `OOXMLEdit.insertParagraph(before: ElementID, content: String, styleId: String?)` | `Operation.insertParagraphBefore(before: ElementID, paragraph: ParagraphPayload)` | 1:1 map (positional variant). |
| `OOXMLEdit.setBold(target: ElementID, value: Bool)` | `Operation.setRunFormat(target: ElementID, format: RunFormatPayload)` | 1:1 map. `RunFormatPayload` carries `bold: Bool?`; setting `value=true` builds payload with `bold=true`, omitting unchanged fields. |
| `OOXMLEdit.insertHyperlink(target: ElementID, href: URL, displayText: String?)` | Composite: `Operation.insertNode(parent: targetParent, position: idx, nodeXML: hyperlinkXML)` + `Operation.updateAttribute(target: relsPart, prefix: nil, localName: "Target", value: href.absoluteString)` | 2-op atomic. The `insertHyperlink` Edit fails (throws preserveViolation) if either op cannot apply — full rollback semantics. |
| `OOXMLEdit.removeParagraph(target: ElementID)` | `Operation.removeParagraph(id: ElementID)` | 1:1 map. (5th canonical case — was deferred selection per ADR-005; selecting `removeParagraph` because it stress-tests preserve-violation defensive check for unaffected siblings.) |

**Rationale for picking these 5**:
- `insertParagraph` — body-level mutation, simplest CD, covers ADR-001 canonical-identity for sectPr/comments/customXml preservation
- `setBold` — run-level mutation, covers ADR-006 Word UI ground truth (Cmd-B)
- `insertHyperlink` — composite mutation requiring relationship-part update, exercises canonical-identity for `_rels/document.xml.rels` AND tests Edit's atomicity semantics
- `removeParagraph` (5th, NEW selection) — stresses preserve-violation defensive check (must not affect sibling paragraphs); tests the negative case of canonical-identity
- The 2nd "select during apply" slot (ADR-005 mentioned 5 cases) was reserved earlier; we now commit to `removeParagraph` as the 5th

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| **OOXMLEdit cases 1:1 with Operation cases** | **CHOSEN** for the 4 simple cases; OOXMLEdit type is a thin facade over the public Operation enum, callers can switch through both |
| Composite OOXMLEdit cases that wrap multiple Operations | **CHOSEN for insertHyperlink only** — semantically a single user-facing op, but requires dual-part mutation. Atomicity managed at Edit level (throw if any sub-op fails). |
| OOXMLEdit hides Operation entirely (own enum, no public mapping) | REJECTED — would force Edit type to re-implement what Operation already does; doubles maintenance |
| OOXMLEdit IS Operation (typealias) | REJECTED — loses ability to add Edit-specific semantics like `lower()`, atomicity, and the WordEdit/OOXMLEdit layering |

### Decision 2: WordEdit ↔ OOXMLEdit mapping (per foundation ADR-003)

| WordEdit case | `lower()` returns | Notes |
|---|---|---|
| `WordEdit.applyBold(range: WordRange)` (range within single paragraph) | `[OOXMLEdit.setBold(target: runID, value: true)]` | 1-element list; if range partial-covers a Run, lower() splits via OOXMLEdit.splitRun (added if needed) |
| `WordEdit.applyBold(range: WordRange)` (range crosses paragraph boundary) | `[OOXMLEdit.setBold(target: runID_1, ...), OOXMLEdit.setBold(target: runID_2, ...)]` | N-element list, one per affected paragraph (per foundation ADR-002 Worked Example 4) |
| `WordEdit.applyLink(range: WordRange, url: URL)` | `[OOXMLEdit.insertHyperlink(target: rangeRoot, href: url, displayText: rangeText)]` | Lowers to composite OOXMLEdit case; OOXMLEdit handles dual-part atomicity |
| `WordEdit.applyInsertParagraph(after: ParagraphRef, content: String)` | `[OOXMLEdit.insertParagraph(after: paraID, content: content, styleId: nil)]` | 1:1 lower; ParagraphRef resolves to ElementID at lower() time |

`WordRange` is a new lightweight struct: `public struct WordRange { let startRun: ElementID; let startOffset: Int; let endRun: ElementID; let endOffset: Int }`. This is the **decision-heavy part of WordEdit** — the user might want richer alternatives.

**Naturality invariant**: `(WordEdit.a ∘ WordEdit.b).lower() == WordEdit.a.lower() ∘ WordEdit.b.lower()` for composable pairs. Tested in `NaturalityTests.swift` with property-based randomization (50 pair samples per pair-type).

### Decision 3: WordDocument owns OperationLog, apply returns new WordDocument

**The type is `WordDocument`** (not `Document` — the original #99 design.md used the conceptual name; the actual ooxml-swift type is `WordDocument`). All Edit APIs reference `WordDocument`.

**Where does OperationLog live?** Four options were considered. The choice has substantial implications for the API surface of every downstream consumer (che-word-mcp, word-builder-swift, macdoc CLI):

| Option | API shape | Verdict + rationale |
|---|---|---|
| **A. WordDocument owns `operationLog: OperationLog` field** | `let newDoc = try doc.apply(edit)` | **CHOSEN** — one type for "parsed Word document", one obvious way to do it. Additive change (+1 field, custom Equatable to exclude log from content equality). Zero behavior change for existing callers. |
| B. Edit.apply takes log parameter | `let (newDoc, newLog) = try doc.apply(edit, log: currentLog)` | REJECTED — verbose; forces callers to manage log lifecycle explicitly. Wins for multi-document shared log scenarios (rare). |
| C. Each apply creates fresh log | `let newDoc = try doc.apply(edit)` (internal log discarded after materialize) | REJECTED — defeats OpLog's core value (append-only audit, JSONL persistence, sync-from-Word). Violates `docs/swift-as-document-source.md`'s "log is the truth medium" design. |
| D. New `EditableDocument` wrapper type | `let editable = doc.editable(); let newDoc = try editable.apply(edit).materialize()` | REJECTED after user feedback — looks elegant but bifurcates API surface. Each downstream (che-word-mcp 218 tools, word-builder-swift Packer, macdoc convert, test fixtures) has to choose "WordDocument or EditableDocument?" Parser entry point splits (`WordDocument.read(url)` vs `EditableDocument.read(url)` or `.editable()` step). Violates "one obvious way to do it". |

**User feedback (2026-05-31 — session deciding A vs D)**: 「如果要理解 word 的話應該要用同一種 parser」— D's surface bifurcation is the real cost, not parser drift (parser doesn't actually split). One-type wins.

**Implementation strategy** (Option A):

```swift
public struct WordDocument: Equatable {
    // Existing 12+ public fields ...
    public var body: Body
    public var styles: [Style]
    // ... etc ...
    
    // NEW (additive)
    public var operationLog: OperationLog = OperationLog()
    
    // Customized Equatable — log NOT included in content equality
    public static func == (lhs: WordDocument, rhs: WordDocument) -> Bool {
        return lhs.body == rhs.body
            && lhs.styles == rhs.styles
            // ... all 12+ existing fields compared ...
            // operationLog intentionally excluded — "document content equal"
            // ≠ "edit history equal". Compare logs explicitly:
            //   doc1.operationLog == doc2.operationLog
    }
}

extension WordDocument {
    public func apply(_ edit: any Edit) throws -> WordDocument {
        // 1. Lower WordEdit→OOXMLEdit, then OOXMLEdit→Operations
        let ops = try edit.lower().flatMap { try $0.operations() }
        
        // 2. Early validation: all target ElementIDs must resolve in self
        // (per spec.md Requirement "Document.apply Public Method" #4)
        try validateTargets(ops: ops)
        
        // 3. Append to log
        var newLog = self.operationLog
        for op in ops {
            newLog.append(op, source: .editAlgebra)
        }
        
        // 4. Materialize via OperationReducer
        var newTrees = self.xmlTrees
        for (partPath, tree) in newTrees {
            // Reduce only modified parts (efficient — most parts unchanged)
            if needsReplay(partPath: partPath, ops: ops) {
                newTrees[partPath] = try OperationReducer.materialize(
                    log: newLog, 
                    base: tree
                )
            }
        }
        
        // 5. Defensive: check non-targeted parts c14n-equal (preserveViolation)
        try validatePreservation(oldTrees: self.xmlTrees, newTrees: newTrees, ops: ops)
        
        // 6. Re-parse typed views (Body, Styles, etc.) from new trees
        // — already wired in v0.31.4 (commit 974a8d9 + 2078413 tree-backed typed views)
        var newDocument = self
        newDocument.operationLog = newLog
        newDocument.xmlTrees = newTrees
        try newDocument.reparseTypedViewsFromTrees()  // refreshes body/styles/etc.
        return newDocument
    }
}
```

**Why customized Equatable (excluding log)**:
- "Two WordDocuments are equal" semantically means "their content is equal" — what callers care about for diff, comparison, snapshot tests
- "Their edit histories are equal" is a separate concept — caller compares `doc1.operationLog == doc2.operationLog` explicitly when needed
- Without customization, `let docA = WordDocument.read(url); let docB = WordDocument.read(url); XCTAssertEqual(docA, docB)` would fail because each parse generates fresh log entries (TODO: verify if log starts empty or seeded — see §2.1 implementation)
- Customization is additive (compares same fields as auto-synthesized Equatable would, minus log)

**Why apply returns new WordDocument (not mutating)**:
- Foundation `ooxml-edit-algebra` Requirement "Edit Apply Surface on Document" mandates immutable apply
- Prevents lost-update bugs in concurrent contexts (Swift value semantics)
- Tradeoff: copies WordDocument struct on each apply. For long mutation chains, consumer can use `apply<S: Sequence>` to batch.

**Other rejected alternatives**:

| Approach | Verdict |
|---|---|
| `apply` mutating instead of returning new WordDocument | REJECTED — foundation ADR-002 says Edit gives immutable apply; mutating opens lost-update bugs |
| Direct XmlTree mutation, bypass OperationLog | REJECTED — defeats OpLog's audit-trail / sync-from-Word value |
| `apply` returns `Result<WordDocument, EditError>` | REJECTED — throws is more idiomatic Swift; Result<> better for async / batch later if needed |
| **Throws-based, immutable return, WordDocument-owns-log** | **CHOSEN** — matches foundation spec.md + user feedback on type surface |

### Decision 4: EditError shape

```swift
public enum EditError: Error, Equatable {
    case pathNotFound(ElementID)
    case preserveViolation(part: String, expected: String, actual: String)
    case unsupportedOperation(String)
    case notImplemented(String)
    case operationLogFailure(underlying: String)
}
```

`preserveViolation` carries diff context (which part, expected/actual c14n digests) so failures are debuggable. `unsupportedOperation` covers cases like "tried to OOXMLEdit.setBold on a non-Run element". `operationLogFailure` wraps OperationReducer errors so callers don't need to handle internal Operation enum variants directly.

### Decision 5: Property test infrastructure

Use `swift-testing`'s `@Test(arguments:)` for parameterized property tests. Each property test generates 100 randomized inputs within valid input domain (e.g., for `setBold` test: 100 random RunPath × {true, false} truth values).

Random number source: `SystemRandomNumberGenerator` for non-reproducibility (matches existing `RealWorldDocxRoundTripSmokeTests` style). If a failure is found, log the seed for reproduction.

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| XCTest `XCTAssertNoThrow` looped manually | REJECTED — verbose, no parameterized test infrastructure |
| **`swift-testing` `@Test(arguments:)`** | **CHOSEN** — native parameterized test support; matches modern Swift toolchain |
| `swift-quickcheck` or similar third-party | REJECTED — adds dependency; native swift-testing sufficient for current needs |

### Decision 6: End-to-end Edit-apply tests deferred behind OpLog Phase 2c

**Context** (discovered during §3 implementation, 2026-05-31): The `OperationReducer` shipped in ooxml-swift v0.31.4 implements **only Phase 2b**: it can replay `setText`, `setParagraphStyle`, `batchBegin/End`, and `unknown` opaque ops. It explicitly throws `ReducerError.malformedOp(reason: "Phase 2c implements this op")` for the entire family of tree-mutating Operations: `insertParagraphAfter`, `insertParagraphBefore`, `removeParagraph`, `insertTable`, `removeTable`, `setCellText`, `insertRun`, `setRunFormat`, `insertBookmark`, `insertComment`, `insertNode`, `removeNode`, `updateAttribute`, `moveNode`.

**Every Operation that any OOXMLEdit case lowers to (per Decision 1) is in that Phase-2c-pending set.**

**Implication for #105**: The Edit-algebra runtime sits on top of the Reducer. `WordDocument.apply(_:)` (§2) wires `lower() → operations() → log append → materialize`. The `materialize` step is the Reducer call, which currently throws for every OOXMLEdit case once §3+ implement `operations()` non-stubs.

**Decision**:

| Test layer | What it validates | OpLog Phase 2c dependency? |
|---|---|---|
| **OOXMLEdit `operations()` emission tests** (§3.1 unit tests) | OOXMLEdit lowers to the correct `Operation` enum payload | NO — pure data, no Reducer involvement |
| **`WordEdit.lower()` translation tests** (§7) | WordEdit lowers to the correct `[OOXMLEdit]` | NO — pure data |
| **End-to-end `document.apply(edit)` tests** (§3.3, §8 property tests, §9 naturality) | Apply actually mutates `xmlTrees` per Decision 1 mapping | YES — needs Reducer to handle the lowered Operations |

We **ship emission-layer tests now** (validates the translation code we just wrote). We **defer end-to-end and property tests** until OpLog Phase 2c lands. Documented in each test file with a header comment pointing back to this Decision.

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| **Defer e2e tests, ship emission tests (current decision)** | **CHOSEN** — unblocks #105 forward motion; emission tests still validate the new code; e2e gap is documented and tracked |
| Block #105 entirely on OpLog Phase 2c | REJECTED — couples two separately-scoped efforts; OOXMLEdit emission contract is independently verifiable |
| Bundle OpLog Phase 2c reducer implementation INTO #105 | REJECTED — would balloon #105 scope from "type runtime" to "type runtime + 14 Operation reducer cases". OpLog Phase 2c deserves its own change with explicit Spectra design for each reducer case (tree mutation semantics, ID preservation, sectPr/comments canonical-identity preservation, etc.) |
| Stub Reducer to no-op on Phase 2c cases just for #105 e2e tests | REJECTED — gives false confidence that `apply()` works; defeats the purpose of e2e validation |

**Tracking**: A follow-up issue should be filed against `ooxml-swift` for "OpLog Phase 2c reducer cases" before §3.3 / §8 / §9 can be unblocked. Suggested scope: implement the 14 currently-throwing Operation cases in `OperationReducer.apply(entry:to:)`, each with its own test fixture proving tree mutation correctness + canonical-identity preservation. Wire into #105 via tasks.md once that issue exists.

**Errata to Decision 3**: Decision 3 assumed the runtime backing (`OperationReducer.materialize`) could replay any Operation. In reality the Reducer's `apply` method handles Phase 2b only. This doesn't change the architectural choice (WordDocument owns OperationLog — still correct), but it does mean `WordDocument.apply(_:)` is currently end-to-end functional only for setText/setParagraphStyle-based Edits (none exist in §1's OOXMLEdit case list; all 5 cases are tree-mutating). The pipeline wiring in §2 is correct; it just throws at the Reducer step until Phase 2c.

## Implementation Contract

**Behavior**: After this change ships, ooxml-swift consumers can:

1. Construct `OOXMLEdit` values:
   ```swift
   let edit = OOXMLEdit.insertParagraph(after: paraID, content: "Hello", styleId: nil)
   ```
2. Compose Edits via `∘` (or array): `let composed = [edit1, edit2, edit3]` — each applies in order
3. Apply to a Document:
   ```swift
   let newDoc = try document.apply(edit)
   ```
4. Get `EditError.pathNotFound` if `paraID` doesn't resolve
5. Get `EditError.preserveViolation` if a buggy internal implementation modifies an unmodified subtree (defensive check)
6. Use `WordEdit` for semantic-layer operations:
   ```swift
   let wordEdit = WordEdit.applyBold(range: WordRange(startRun: r1, startOffset: 0, endRun: r1, endOffset: 5))
   let oOXMLEdits = wordEdit.lower()  // [OOXMLEdit.setBold(...)]
   ```

**Interface / data shape**:

```swift
// Edit.swift
public protocol Edit {
    func apply(to document: Document) throws -> Document
    func lower() -> [OOXMLEdit]
}

public enum EditError: Error, Equatable { /* per Decision 4 */ }

// OOXMLEdit.swift
public enum OOXMLEdit: Edit, Equatable, Sendable {
    case insertParagraph(after: ElementID, content: String, styleId: String?)
    case insertParagraphBefore(before: ElementID, content: String, styleId: String?)
    case setBold(target: ElementID, value: Bool)
    case insertHyperlink(target: ElementID, href: URL, displayText: String?)
    case removeParagraph(target: ElementID)

    // Edit conformance
    public func apply(to document: Document) throws -> Document { /* routes through Document.apply */ }
    public func lower() -> [OOXMLEdit] { [self] }  // identity for OOXMLEdit
    
    // OOXMLEdit-specific: Operation emission
    public func operations() -> [Operation]
}

// WordEdit.swift  
public enum WordEdit: Edit, Equatable, Sendable {
    case applyBold(range: WordRange)
    case applyLink(range: WordRange, url: URL)
    case applyInsertParagraph(after: ParagraphRef, content: String)
    
    public func apply(to document: Document) throws -> Document { /* lower + apply */ }
    public func lower() -> [OOXMLEdit]
}

public struct WordRange: Equatable, Sendable {
    public let startRun: ElementID
    public let startOffset: Int
    public let endRun: ElementID
    public let endOffset: Int
}

// Document.swift (additive)
extension Document {
    public func apply(_ edit: any Edit) throws -> Document { /* Decision 3 */ }
    public func apply<S: Sequence>(_ edits: S) throws -> Document where S.Element == any Edit { /* fold */ }
}
```

**Failure modes**:
- `OOXMLEdit.setBold` on a non-Run element → `EditError.unsupportedOperation("setBold requires Run target, got \(elementType)")`
- `OOXMLEdit.insertParagraph(after:)` with non-existent `after:` → `EditError.pathNotFound(elementID)`
- `OOXMLEdit.insertHyperlink` where `target` resolves but rels-part is missing → `EditError.preserveViolation(part: "_rels/document.xml.rels", expected: "non-empty", actual: "missing")`
- Internal `OperationReducer.materialize` throws → wrapped as `EditError.operationLogFailure(underlying: error.localizedDescription)`

**Acceptance criteria** (per foundation capability spec):

1. `swift build` succeeds on ooxml-swift with no warnings
2. `swift test --filter EditAlgebraTests` passes 100% with at least:
   - 5 protocol conformance tests (EditProtocolTests)
   - 6 apply API tests (DocumentApplyTests covering immutable apply, all error cases)
   - 5 property tests (one per OOXMLEdit case, 100 randomized inputs each)
   - 3 naturality tests (WordEdit composition pairs)
3. CD diagrams for the 5 OOXMLEdit cases land in `docs/edit-algebra-cd-discipline.md` (extension of foundation ADR-002 Worked Examples)
4. `Document.apply(_ edit:)` API doesn't break existing callers (existing tests still pass)
5. PR opening this change passes the foundation's `.github/PULL_REQUEST_TEMPLATE.md` Edit Algebra checklist

**Scope boundaries** (in scope vs out):

- **In scope**: 5 OOXMLEdit cases, 3 WordEdit cases, EditError enum, Edit protocol, Document.apply API, OOXMLEdit→Operation mapping table, property tests on NTPU fixture, CD diagrams for the 5 cases, errata cross-reference to foundation #99 design.md
- **Out of scope**: word-builder-swift lens migration, che-word-mcp boundary refactor, downstream PR re-frames (#102/#103/#104 in macdoc), automated CD validation, full OOXMLEdit surface beyond 5, corpus expansion beyond NTPU fixture, module split implementation, OOXMLSyntax/Semantic/DSL module split

## Risks / Trade-offs

| Risk | Mitigation |
|---|---|
| **`Operation` enum API drift** — if v0.31.x Operation/OperationLog API shifts (e.g., new required field), our OOXMLEdit→Operation mapping breaks | Pin tested ooxml-swift version in property tests; check v0.31.x/v0.32.x compat; flag any breakage via standard ooxml-swift CHANGELOG review |
| **CD diagram correctness** — ADR-002 says reviewer must verify diagram is correct, but humans can rubber-stamp | Property tests are the second gate — if CD says "applyBold commutes with X" but property test catches a counter-example, the CD is wrong. Discipline: CD-failed-by-property-test = explicit revert + redesign |
| **WordRange resolution** — `WordRange` references `ElementID` for startRun/endRun. If document is mutated between WordRange creation and `lower()`, IDs may be stale | Document `WordRange` validity scope as "valid in the Document instance it was created from"; lower() throws `pathNotFound` if either ID doesn't resolve |
| **Atomic insertHyperlink** — composite OOXMLEdit case wraps 2 Operations. If first applies and second fails, partial state | Edit.apply throws BEFORE log materialization for composite cases (validate target + relsPart upfront, atomic Operation batch via `Operation.batchBegin`/`batchEnd` if OpLog supports rollback) |
| **Performance regression** — Edit type wraps Operations adds 1 indirection layer | Benchmark on NTPU fixture round-trip; baseline = direct Operation manipulation; flag > 10% regression |
| **Naturality property hard to enforce** — composable WordEdit pairs may behave subtly different through lower() | Property test asserts naturality explicitly for each implemented WordEdit pair; CI flags on violation |
| **Foundation ADR-002 stale on backing** — current design says "applyOverlay/markDirty" but reality is Operation/Reducer | This change's design.md (Decision 3) corrects + errata note in foundation #99 issue body |
| **Module split deferred** — `EditAlgebra/` lives in current `OOXMLSwift` module; future ADR-004 split moves it to `OOXMLSemantic` | API surface designed to be relocatable — no internal coupling to module-private APIs |

## Migration Plan

**No user-facing migration**. Edit type is additive. Existing `Document.applyOverlay()` / `markPartDirty()` callers continue working unchanged.

**Coordination with `word-aligned-state-sync`**: that change's runtime (`Operation` enum + `OperationLog` + `OperationReducer`) is the backing this change builds on. No code coordination needed — just architectural alignment captured here + in foundation design.md errata.

**Future BREAKING dependencies** (out of this change):
- `word-builder-swift` 1.0.0 lens migration (per foundation ADR-008)
- `che-word-mcp` MCP boundary refactor to WordEdit (per che-word-mcp#162)
