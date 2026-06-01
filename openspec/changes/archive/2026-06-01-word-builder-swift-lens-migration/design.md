## Context

`word-builder-swift` 0.9.0 (shipped via macdoc#71) provides a fluent Swift API for `.docx` authoring that mirrors `docx.js` 9.6.x:

```swift
let doc = Document(sections: [
    Section(children: [
        Paragraph(children: [TextRun("Hello")])
    ])
])
try Packer.toFile(doc, url: outURL)
```

Internally, `DocumentConverter.convert(_:)` translates the struct tree into `OOXMLSwift.WordDocument`, then `OOXMLSwift.DocxWriter` serializes it. The model is **write-only**: no `init(reading:)`, no Edit-protocol surface, no round-trip semantics.

Meanwhile, `ooxml-edit-isomorphism-foundation` (archived) shipped 9 ADRs locking the Edit-algebra contract; `ooxml-edit-algebra-implementation` (archived 2026-06-01) shipped the Phase 2 runtime — the `Edit` protocol, `OOXMLEdit` / `WordEdit` enums, `WordDocument.apply(_ edit:)` method, plus the OpLog + Reducer event-sourced backing. All 5 OOXMLEdit cases + all 3 WordEdit cases function end-to-end. Reducer Phase 2c shipped the cases needed by current OOXMLEdit usage (`insertParagraphAfter`, `insertParagraphBefore`, `removeParagraph`, `setRunFormat`-bold, `insertSiblingAfter`, `addRelationship`, `wrapWithHyperlink`).

ADR-008 (from the foundation) mandated word-builder-swift migrate to a lens-model architecture and prescribed a 3-month coexistence + deprecation cycle. The deferred-tracking issue is macdoc#101. Scouting during the discuss phase revealed **zero downstream callers**: `grep -rln "import WordBuilderSwift" packages/ mcp/ Sources/ Tests/` returns 0 hits; no `Package.swift` lists word-builder-swift as a dependency. Only `examples/*.swift` (1–5 standalone demos) use the API.

Constraints:

- The Edit-algebra contract is **stable** and lives in ooxml-swift. word-builder-swift consumes it, doesn't redefine it.
- The Reducer's Phase 2c coverage is partial (~7 of ~14 Operation cases); LensDocument's authoring surface should not require Reducer cases that haven't shipped (or surface a clear `EditError.notImplemented`/`operationLogFailure` when callers reach for unimplemented edits).
- BREAKING change is semver-correct (v1.0.0), but the no-callers observation means the BREAKING label is functionally moot — there's nothing to break.
- Module name (`WordBuilderSwift`) and package name (`word-builder-swift`) are preserved across the migration to avoid identity churn at the dependency level.

Stakeholders:

- **Authors of macdoc#71** (Phase 1 shipper of v0.9.0) — should know their docx.js-parallel work is being replaced with a different abstraction.
- **Future adopters** (che-word-mcp, macdoc CLI, dxedit per ADR-009) — will land on the lens model as the only API option; migration burden falls on them at adoption time, not retroactively.
- **`reference/docx-js/`** — referenced by the existing spec as the source of API names. After this change, that reference becomes purely informational (the spec no longer mirrors docx.js).

## Goals / Non-Goals

**Goals**:

1. Replace `word-builder-swift` v0.9.0's struct-serialization surface with a lens-model handle (`LensDocument`) wrapping `OOXMLSwift.WordDocument`.
2. Expose the `OOXMLSwift.Edit` protocol + `OOXMLEdit`/`WordEdit` cases as the authoring vocabulary (no parallel WordBuilder protocol).
3. Provide `init()`, `init(reading: URL)`, `apply(_ edit:)`, `apply<S: Sequence>(_ edits:)`, `emit(to:)` as the LensDocument public surface.
4. Rewrite `examples/*.swift` to use LensDocument + Edit, preserving file numbering for git-history continuity.
5. Replace the `word-builder-swift` capability spec's v0.9.0 Requirements (docx.js mirror, struct-serialization shape) with v1.0.0 lens-model Requirements (LensDocument shape, Edit-protocol reuse, emit semantics).
6. Ship `Package.swift` version bump to 1.0.0 and a README "Migration from 0.9.0" section.

**Non-Goals**:

- **No coexistence between v0.9.0 and v1.0.0**: zero callers makes parallel-API maintenance pure overhead. The struct-serialization types are removed atomically in v1.0.0.
- **No new `WordBuilderEdit` protocol**: ADR-009 frames downstream packages as Layer 3/4 front-ends to the foundation. Duplicating the Edit protocol would violate single-source-of-truth.
- **No changes to ooxml-swift**: Edit-algebra runtime is already complete. This change consumes it.
- **No che-word-mcp / macdoc CLI integration**: neither imports word-builder-swift; integration is per-package follow-up work.
- **No write-only-fluent compatibility shim**: e.g., adding `init(sections:)` overload that internally translates to LensDocument. The docx.js parallel is abandoned, not preserved-via-translation, because the lens model is fundamentally a different abstraction (handle to live document state vs. immutable struct snapshot).
- **No coordination work on `word-aligned-state-sync`**: ADR-008 anticipated convergence at the v1.0.0 cleanup window, but with this change scoped to API replacement only (no OpLog or Reducer changes), no work needs to happen on the active change.
- **No CHANGELOG migration framework**: a one-line v1.0.0 entry suffices given the no-callers observation. Future feature changes will create the CHANGELOG file structure if it doesn't already exist after this change.

## Decisions

### Decision 1: Clean break in v1.0.0, no coexistence cycle

**Decision**: Remove `Document`, `Section`, `SectionChild`, `Paragraph` (word-builder-swift's), `Run` (word-builder-swift's), `Table` (word-builder-swift's), `Enums.swift`, `Packer`, and `DocumentConverter` in v1.0.0 atomically. No deprecation warnings, no overloads, no parallel emit paths.

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| **Atomic removal in v1.0.0 (this Decision)** | **CHOSEN** — zero callers means coexistence protects nobody and creates parallel-API debt |
| 3-month coexistence + deprecation per ADR-008 | REJECTED on scout — `grep -rln "import WordBuilderSwift"` returns 0 hits across all macdoc-family packages; deprecation warnings would surface to no one |
| Keep `Document(sections:)` as a write-only convenience wrapper that internally constructs a LensDocument and calls `apply` | REJECTED — pretending the struct API is still valid hides the fact that the underlying semantics are now event-sourced (each "section" would be a sequence of synthesized inserts). Reading "sections" back would not match what was written (no lens). Misleading. |
| Keep only `Packer.toData(_:)` overload that accepts `LensDocument`, removing struct types | REJECTED — half-migration leaves the `Packer` namespace as orphan vestigial API. Cleaner to remove Packer entirely and expose `emit(to:)` on LensDocument. |

**Rationale**: macdoc#99 ADR-008's coexistence period exists to spread migration cost across calling sites. With zero current callers, the cost is zero in both timelines; coexistence only adds maintenance overhead. The BREAKING semver label is technically correct but practically vacuous.

**Consequence**: A future user upgrading from 0.9.0 → 1.0.0 sees compile errors at every `Document(sections:)` / `Packer.toX(...)` call site. README's "Migration from 0.9.0" section gives them the table. This is acceptable because (a) no such users exist today, and (b) the spec change is normative (the v0.9.0 spec is being replaced, not extended).

### Decision 2: `LensDocument` wraps `OOXMLSwift.WordDocument`; does NOT replace it

**Decision**: `LensDocument` is a thin struct holding a single private `OOXMLSwift.WordDocument` field. All Edit application delegates to `WordDocument.apply(_:)`. Emit calls `OOXMLSwift.DocxWriter.writeData(...)` then writes bytes to the URL.

```swift
public struct LensDocument {
    private var inner: OOXMLSwift.WordDocument

    public init() {
        self.inner = OOXMLSwift.WordDocument()
    }

    public init(reading url: URL) throws {
        self.inner = try OOXMLSwift.DocxReader.read(from: url)
    }

    public func apply(_ edit: any Edit) throws -> LensDocument {
        var copy = self
        copy.inner = try inner.apply(edit)
        return copy
    }

    public func apply<S: Sequence>(_ edits: S) throws -> LensDocument where S.Element == any Edit {
        var copy = self
        copy.inner = try inner.apply(edits)
        return copy
    }

    public func emit(to url: URL) throws {
        let data = try OOXMLSwift.DocxWriter.writeData(inner)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try data.write(to: url)
    }
}
```

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| **LensDocument wraps WordDocument (this Decision)** | **CHOSEN** — preserves separation of concerns (ooxml-swift owns parser + event-sourced runtime; word-builder-swift owns authoring ergonomics) |
| LensDocument IS `OOXMLSwift.WordDocument` (typealias) | REJECTED — leaks the entire WordDocument surface (many internal-set fields, custom Equatable that excludes operationLog, etc.) into word-builder-swift's API. Confuses module boundaries. |
| LensDocument is a builder type that emits a fresh WordDocument at emit time | REJECTED — destroys round-trip semantics for `init(reading:)`. The lens-model whole-point is that read state and write state are the same handle. |
| LensDocument carries an independent backing tree (its own XmlTrees + OpLog), copying state from WordDocument at construction | REJECTED — duplicates state, breaks reference behavior, requires synchronization between the two state stores. |

**Rationale**: Wrapping is the minimum-surface design that achieves the lens-model property. The private `inner` field keeps WordDocument's public surface scoped to ooxml-swift consumers; LensDocument users only see the 5-method authoring surface.

**Implications**:
- LensDocument is a value type (`struct`), matching WordDocument's value semantics. Apply returns a new LensDocument (immutable apply).
- Equatable inheritance: LensDocument doesn't auto-conform to Equatable. If callers need equality, they compare emitted bytes or extract `.inner` via a future internal accessor. v1.0.0 does not need it.
- Sendable: LensDocument's Sendable conformance depends on WordDocument's. WordDocument is already Sendable (per OOXMLSwift conventions); LensDocument inherits.

### Decision 3: Reuse ooxml-swift's `Edit` protocol; no `WordBuilderEdit`

**Decision**: LensDocument's `apply(_:)` takes `any Edit` where `Edit` is the protocol from `OOXMLSwift.EditAlgebra.Edit`. Callers write:

```swift
import WordBuilderSwift  // brings LensDocument
import OOXMLSwift        // brings Edit, OOXMLEdit, WordEdit (transitively re-exported by WordBuilderSwift)

let doc = LensDocument()
let after = try doc.apply(WordEdit.applyInsertParagraph(
    after: ParagraphRef(...),
    content: "Hello"
))
try after.emit(to: outURL)
```

To avoid the import duplication, `Sources/WordBuilderSwift/WordBuilderSwift.swift` re-exports the foundation's types:

```swift
@_exported import OOXMLSwift  // re-export Edit, OOXMLEdit, WordEdit, EditError
```

After re-export, callers only need `import WordBuilderSwift`.

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| **Reuse OOXMLSwift.Edit + @_exported import (this Decision)** | **CHOSEN** — single-source-of-truth for Edit-algebra; minimal API surface in word-builder-swift |
| New `WordBuilderEdit` protocol that wraps `Edit` | REJECTED per ADR-009 — duplicates the contract, creates parallel algebras (e.g., a user-facing WordBuilderEdit vs internal Edit), increases maintenance burden, confuses callers about which to use |
| LensDocument exposes typed convenience methods (`func bold(range:)`, `func insertParagraph(after:content:)`) instead of generic `apply(_:)` | REJECTED — diverges from the Edit-protocol mental model. Each typed method is just a thin wrapper around a specific `WordEdit` case; encouraging callers to use the underlying protocol future-proofs them against new cases. v1.1.x could add typed sugar as a refinement. |
| Don't re-export OOXMLSwift; require callers to import both modules | REJECTED — needless friction. Re-export is the standard Swift mechanism for type-pass-through. |

**Rationale**: ADR-009's downstream-rerouting framework explicitly positions word-builder-swift as a Layer 3 front-end to the foundation. Front-ends consume the contract; they don't redefine it. Re-export keeps the foundation's contract visible while giving word-builder-swift the ergonomic top-level handle (LensDocument).

### Decision 4: Examples are rewritten in the same PR; file numbering preserved

**Decision**: All `examples/*.swift` files (currently `01-hello-world.swift` through `05-aligned-paragraphs.swift`) are rewritten to use LensDocument + Edit. File numbers preserved for git-history continuity (same blob name, new content). Each example shows a different aspect of the lens-model authoring flow.

| Example | v0.9.0 content | v1.0.0 content |
|---|---|---|
| `01-hello-world.swift` | `Document([Section([Paragraph([TextRun("Hello")])])])` + `Packer.toFile` | `LensDocument().apply(WordEdit.applyInsertParagraph(...))` + `emit` |
| `02-heading-and-paragraphs.swift` | Multiple Paragraphs with HeadingLevel | Chain `applyInsertParagraph` with `styleId: "Heading1"` etc. |
| `03-table-3x3.swift` | Table builder | Demonstrates `LensDocument(reading:)` + table-manipulation Edits (currently throws notImplemented until Phase 2c reducer ships table cases — example shows the call shape and notes the error mode) |
| `04-mixed-formatting.swift` | Bold + italic Runs | Chain `WordEdit.applyBold(range:)` (italic via setItalic when shipped per ooxml-swift#71 follow-up) |
| `05-aligned-paragraphs.swift` | AlignmentType on paragraphs | Show via `OOXMLEdit.setParagraphStyle` (currently functional via setText/setParagraphStyle phase 2b cases) |

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| **Rewrite examples in same PR, preserve numbering (this Decision)** | **CHOSEN** — same-PR rewrite keeps the examples synced with the API; preserved numbering keeps git blame clean |
| Delete v0.9.0 examples, create new examples with v1.0.0 numbering | REJECTED — loses git-history continuity for example files |
| Keep v0.9.0 examples in `examples/legacy/`, add new examples in `examples/` | REJECTED — perpetuates "two ways to do it" mental model that this change is eliminating |
| Skip examples in this PR, defer to follow-up | REJECTED — examples are the first thing users read; shipping v1.0.0 with v0.9.0 examples is broken-doc state |

**Rationale**: Examples define the user's first impression of the API. Same-PR rewrite ensures the docs match the code at release time. Preserving file numbering is a small kindness to anyone reading `git log examples/01-hello-world.swift`.

### Decision 5: README "Migration from 0.9.0" is a 3-row table, not a paragraph essay

**Decision**: README gains a top-level "Migration from 0.9.0" section with a single 3-row table:

```markdown
## Migration from 0.9.0

| v0.9.0 (REMOVED in 1.0.0) | v1.0.0 (current) |
|---|---|
| `Document(sections: [Section(children: [...])])` | `LensDocument()` then chain `apply(WordEdit.applyInsertParagraph(...))` |
| `Packer.toFile(doc, url:)` | `doc.emit(to: url)` |
| `Packer.toData(doc)` | Use `OOXMLSwift.DocxWriter.writeData(doc.inner)` if you need raw bytes (LensDocument exposes `.inner` via `internal` access for the OOXMLSwift module; callers outside OOXMLSwift get `emit(to:)` only). For v1.0.0, write-to-disk is the supported path; raw-bytes access is a follow-up. |

See `examples/` for end-to-end programs.
```

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| **3-row table + see-examples pointer (this Decision)** | **CHOSEN** — minimum-viable migration doc; the no-callers observation means this section is informational, not load-bearing |
| Full-page migration essay with code blocks for each v0.9.0 idiom | REJECTED — overkill for zero current callers; the table is sufficient for anyone arriving from v0.9.0 |
| Dedicated `MIGRATION.md` file | REJECTED — same overkill problem; README section is more discoverable |
| Skip migration doc entirely | REJECTED — even with zero callers, the spec change is normative; a future archaeologist looking at v0.9.0 code needs the mapping |

**Rationale**: Documentation cost should match documentation usage. With zero current callers, a long migration document is text-fully-mostly-unread. A 3-row table gets the structural mapping across without performative thoroughness.

### Decision 6: `Packer` and `DocumentConverter` are removed wholesale, not refactored

**Decision**: Delete `Sources/WordBuilderSwift/Packer.swift` and `Sources/WordBuilderSwift/DocumentConverter.swift` entirely. Their roles (struct→ooxml conversion + ZIP serialization) are subsumed by `LensDocument`'s direct use of `OOXMLSwift.WordDocument` + `OOXMLSwift.DocxWriter`.

**Alternatives considered**:

| Approach | Verdict |
|---|---|
| **Remove both files (this Decision)** | **CHOSEN** — neither has a role in the lens model |
| Keep `Packer` as a namespace with `Packer.emit(lensDocument:, to:)` | REJECTED — emit is a property of LensDocument, not a separate static utility; LensDocument should be self-sufficient |
| Keep `DocumentConverter` as bidirectional bridge for future read-back compatibility | REJECTED — no read-back compatibility is desired; the struct API is being removed, not preserved |

**Rationale**: Cleanup principle — don't keep code that has no role in the new architecture, even if it might "look reusable" later. If a Packer-shaped utility re-emerges in v1.1.x, it can be reintroduced fresh with a v1.1.x-appropriate signature.

## Implementation Contract

**Behavior**: After this change archives, a Swift developer using word-builder-swift 1.0.0 can:

1. Construct an empty document handle: `let doc = LensDocument()`.
2. Open an existing `.docx` file as a document handle: `let doc = try LensDocument(reading: url)`.
3. Apply a single Edit: `let after = try doc.apply(WordEdit.applyInsertParagraph(after: paraRef, content: "Hi"))`.
4. Apply a sequence of Edits in order: `let final = try doc.apply([edit1, edit2, edit3] as [any Edit])`.
5. Serialize to disk: `try final.emit(to: outURL)`.
6. Receive `EditError.notImplemented` or `EditError.operationLogFailure` for Edit cases whose Reducer support hasn't shipped yet (currently limited to non-tree-mutating ops + the 7 critical-path Phase 2c cases already shipped).

The struct-serialization API (`Document(sections:)`, `Section(children:)`, `Packer.toFile(_, url:)`, `Packer.toData(_)`, `Packer.toBase64String(_)`) no longer compiles. Callers see clear compile errors at every removed-type usage site.

**Interface / data shape**:

```swift
// Sources/WordBuilderSwift/LensDocument.swift
public struct LensDocument {
    public init()
    public init(reading url: URL) throws
    public func apply(_ edit: any Edit) throws -> LensDocument
    public func apply<S: Sequence>(_ edits: S) throws -> LensDocument where S.Element == any Edit
    public func emit(to url: URL) throws
}

// Sources/WordBuilderSwift/WordBuilderSwift.swift (re-export root)
@_exported import OOXMLSwift
```

After re-export, `import WordBuilderSwift` is sufficient — callers see `LensDocument`, `Edit`, `OOXMLEdit`, `WordEdit`, `EditError`, `WordRange`, `ParagraphRef`, etc.

**Failure modes**:

- `LensDocument(reading: url)` throws if the file is missing, unreadable, or not a valid `.docx` archive (propagated from `OOXMLSwift.DocxReader`).
- `apply(_ edit:)` throws `EditError.notImplemented` for stubbed Edit cases (e.g., `OOXMLEdit.insertHyperlink` if its Reducer support hasn't shipped in the consumed ooxml-swift version).
- `apply(_ edit:)` throws `EditError.operationLogFailure` when the Reducer can't apply (typically: target ElementID doesn't resolve, or Phase 2c case not yet implemented).
- `emit(to:)` throws if the file system rejects the write (permissions, disk full, invalid URL).

**Acceptance criteria**:

1. `swift build` succeeds in `packages/word-builder-swift/` with no warnings (no `MathEquation`-style deprecation noise from this change's code).
2. `swift test` in `packages/word-builder-swift/Tests/` passes 100% with at least:
   - Construction tests for `LensDocument()` and `LensDocument(reading:)`
   - Apply tests for one `OOXMLEdit` case and one `WordEdit` case (proves the Edit protocol is accessible)
   - Emit test that round-trips through disk and reads back via `OOXMLSwift.DocxReader` to verify byte-equality property holds (smoke level; canonical-identity is asserted via OOXMLSwift's tests)
3. All `examples/*.swift` files compile under `swift build` as standalone Swift scripts (or as a sub-target if the package wires them that way).
4. README contains the "Migration from 0.9.0" section with the 3-row table.
5. `Package.swift` declares `version: "1.0.0"` (or whatever semver mechanism the package uses; check existing Package.swift conventions).
6. `spectra validate word-builder-swift-lens-migration` passes.
7. The `word-builder-swift` capability spec's Purpose statement matches the new "lens-model handle" description, and the v0.9.0 Requirements (Public API mirrors docx.js, struct-serialization shape, etc.) are removed.

**Scope boundaries** (in scope vs out):

- **In scope**: LensDocument type + 5-method surface, `@_exported import OOXMLSwift`, examples rewrite, Tests rewrite, README "Migration from 0.9.0" + Architecture sections, CHANGELOG v1.0.0 entry (create file if absent), Package.swift version bump, word-builder-swift spec.md replacement.
- **Out of scope**: ooxml-swift modifications, che-word-mcp / macdoc CLI integration, dxedit DSL work, R-wordbuilder generator updates, word-aligned-state-sync coordination, Reducer Phase 2c completion (separate ooxml-swift work), typed convenience sugar methods on LensDocument (e.g., `func bold(range:)` — deferred to v1.1.x), Equatable conformance on LensDocument.

## Risks / Trade-offs

| Risk | Mitigation |
|---|---|
| **Future caller assumes v0.9.0 struct API exists** — somebody copies a v0.9.0 example into a v1.0.0 project | Migration table in README + clear compile errors at removed type sites. The compile errors are unambiguous (e.g., "cannot find type 'Document' in scope"). |
| **Reducer Phase 2c coverage gap surfaces as runtime failure** — LensDocument exposes Edit cases whose Reducer impl hasn't shipped (e.g., setBold italic, table mutations) | Document the gap in README's Architecture section + in CHANGELOG. Errors surface as `EditError.notImplemented` / `.operationLogFailure` with clear messages. ooxml-swift#71 tracks Reducer completion. |
| **@_exported import OOXMLSwift creates symbol pollution** — re-export brings in all ooxml-swift public symbols (not just Edit-algebra), some of which may collide with future word-builder-swift additions | Acceptable for v1.0.0; if collisions arise later, switch to explicit re-export (`public typealias Edit = OOXMLSwift.Edit`) per-symbol. Defer until needed. |
| **LensDocument value semantics + WordDocument internal mutability** — WordDocument has reference-typed XmlNode children inside its xmlTrees; passing LensDocument around copies the struct but xmlNode references are shared | This is inherited from WordDocument's design and documented in macdoc#105 (Paragraph Equatable reference-identity constraint). LensDocument users who need true deep isolation can construct a fresh LensDocument via emit→re-read. Document the trade-off in README's Architecture section. |
| **examples/ rewrite leaves Phase-2c-pending Edits as commented-out code** — example 03-table-3x3.swift uses table-mutation Edits whose Reducer cases haven't shipped | Acceptable. Example 03 shows the intent + an explanatory comment ("table-mutation Reducer support tracked in ooxml-swift#71"). When Phase 2c completes for tables, that example becomes runnable without API changes. |
| **The single-source-of-truth principle for Edit protocol blocks word-builder-swift from adding non-OOXMLSwift authoring vocabulary** | Acceptable trade-off. If word-builder-swift wants to add native-Swift-only convenience (e.g., closures-as-Edits via builder DSL), it can layer that on top via extension methods (LensDocument extensions producing OOXMLEdit chains). The core protocol stays in ooxml-swift. |
| **Package.swift version bump alone may not propagate the BREAKING signal** to consumers who pin via `.upToNextMajor(from: "0.9.0")` | Acceptable — that's what semver is for. The 0.9 → 1.0 bump IS the breaking-signal; any consumer who pins minor-only-up gets clear major-bump alerts at next `swift package update`. |

## Migration Plan

**There is no migration plan for current callers** because there are no current callers. The following steps describe the implementation order of THIS change, not a migration framework for downstream consumers.

**Step 1: Write LensDocument.swift** — new file at `packages/word-builder-swift/Sources/WordBuilderSwift/LensDocument.swift` with the 5-method surface per Decision 2.

**Step 2: Add @_exported import** — rewrite `Sources/WordBuilderSwift/WordBuilderSwift.swift` to be `@_exported import OOXMLSwift` (replaces whatever's currently there).

**Step 3: Delete removed files** — `git rm` the 7 removed source files (`Document.swift`, `Section.swift` if present, `Paragraph.swift`, `Run.swift`, `Table.swift`, `Enums.swift`, `Packer.swift`, `DocumentConverter.swift`). The package's `Package.swift` doesn't need source-list updates because Swift PM auto-discovers `Sources/WordBuilderSwift/*.swift`.

**Step 4: Rewrite examples** — for each of `examples/01-*` through `examples/05-*`, replace the v0.9.0 code with v1.0.0 LensDocument + Edit calls per Decision 4's table.

**Step 5: Rewrite tests** — `Tests/WordBuilderSwiftTests/` rewritten to verify the 5-method LensDocument surface (one test per acceptance-criteria scenario in Implementation Contract).

**Step 6: Update README + CHANGELOG** — add "Migration from 0.9.0" section per Decision 5 + Architecture section. Create CHANGELOG.md if absent with v1.0.0 entry. Bump Package.swift version to "1.0.0".

**Step 7: Replace the spec.md** — `openspec/specs/word-builder-swift/spec.md` Purpose statement and Requirements rewritten to match the v1.0.0 surface. The spec change ships as part of this Spectra change's `specs` artifact.

**Step 8: Verify** — `swift test` in `packages/word-builder-swift/`; `spectra validate word-builder-swift-lens-migration`; visual review of README rendering.

**Step 9: Archive this Spectra change** — `spectra archive word-builder-swift-lens-migration` after apply completes.

**Step 10: Close macdoc#101** — closing comment cites this Spectra change's archive path + the ooxml-swift commits required (`f440c35` Phase 2c critical-path, `e6adb77` multi-part scoping, `cb503e3` performance benchmark, etc., reflecting the foundation work this consumes).

**Coordination with active changes**:

- `word-aligned-state-sync` continues independently. No artifact-level coordination needed. Cross-reference text in design.md is informational.
- `ooxml-edit-isomorphism-foundation` (archived) ADR-008 is the originating mandate; no modifications to the archived foundation are required by this change.
