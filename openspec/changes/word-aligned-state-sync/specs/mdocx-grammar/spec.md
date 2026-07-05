## ADDED Requirements

### Requirement: Operation wire format is defined by ooxml-operation-log

The op names appearing in this spec's Scenarios and SBE Examples SHALL be read as references to the canonical operation taxonomy defined in `ooxml-operation-log` — the single normative home of the operation wire format (#128). This spec regulates the DSL surface and the reverse transcoder's behavior; it SHALL NOT define or restate operation shapes. Where an example historically showed a positional `at:` index, the index is derived display metadata: actual addressing is ID-based per `ooxml-operation-log`'s "ID-based operations, never positional indices" requirement — the DSL emits children in declaration order via `appendParagraph(in:)` / `insertParagraphAfter(after:)` anchoring.

#### Scenario: Example op names resolve to canonical taxonomy

- **WHEN** an SBE example in this spec names an emitted operation
- **THEN** the operation's authoritative shape (payload fields, addressing, JSONL form) is the one in `ooxml-operation-log`, and any discrepancy resolves in favor of `ooxml-operation-log`

## MODIFIED Requirements

### Requirement: Component-aware op log via BeginComponent and EndComponent

A user-defined type conforming to `WordComponent` MUST emit a paired `beginComponent` and `endComponent` operation (canonical shapes in `ooxml-operation-log`) bracketing all operations produced by its body. The `beginComponent` op MUST carry the component's runtime type name and its `id`; the `endComponent` op MUST carry the same `id`.

The reverse transcoder MUST recognise the `beginComponent`/`endComponent` envelope in the op log and reconstruct the component invocation in the output source. The `beginComponent` and `endComponent` operations MUST NOT produce any element in the final OOXML output (they are op-log metadata only — the documented exception to OOXML-mirror op naming).

#### Scenario: component body wrapped in op-log envelope

- **GIVEN** a custom component `Summary` that, when expanded, produces one `Paragraph(id: "sum-frame", style: .summaryFrame)` containing a `Run("note text")`
- **WHEN** an author writes `Summary(id: "ch1-summary") { "note text" }`
- **THEN** the op log contains, in order: `beginComponent(type: "Summary", id: "ch1-summary")`, `appendParagraph(in: "ch1-summary", id: "sum-frame", style: "summaryFrame")`, `setRuns(target: "sum-frame", runs: [{text: "note text"}])`, `endComponent(id: "ch1-summary")` (canonical names per `ooxml-operation-log`)

#### Scenario: reverse direction reconstructs component invocation

- **WHEN** the reverse transcoder reads the op log produced by the previous scenario
- **THEN** it emits exactly `Summary(id: "ch1-summary") { "note text" }` and MUST NOT emit the flattened `Paragraph(...) { ... }` form

#### Scenario: component metadata produces no OOXML artifact

- **WHEN** the docx is serialised from the op log produced by the first scenario above
- **THEN** the resulting `word/document.xml` MUST NOT contain any element corresponding to `beginComponent` or `endComponent`
- **AND** byte-equal round-trip MUST hold for the docx output across multiple component-instance invocations

### Requirement: Special-character inline atoms as standalone children

Tab stops (`Tab()`), line breaks (`Break()`), no-break hyphens (`NoBreakHyphen()`), and other OOXML inline atoms that have no text content and no formatting properties MUST be expressible as standalone children within the paragraph result builder, parallel to `Run` and `String`. They MUST NOT be modeled as static factory methods on `Run`.

#### Scenario: Tab and Break compose with Run and String

- **WHEN** a paragraph body contains `"Header"; Tab(); "Right-aligned"; Break(); "Continued"`
- **THEN** the emitted operations include the runs and, between them, `insertTab` / `insertBreak` ops in declaration order (canonical shapes in `ooxml-operation-log`)

##### Example: standalone atom op shapes

| Source | Emitted op (canonical, per `ooxml-operation-log`) |
| ------ | ------------------------------------------------- |
| `Tab()` | `insertTab(in: <container-id>)` — appended in declaration order |
| `Break()` | `insertBreak(in: <container-id>)` |
| `NoBreakHyphen()` | `insertNoBreakHyphen(in: <container-id>)` |
