## ADDED Requirements

### Requirement: Append-only operation log

The library SHALL provide an `OperationLog` type that records every state-changing operation as an immutable, append-only sequence of typed `Operation` values. Operations once appended SHALL NOT be modified or removed; rollback is expressed as a new appended `Undo` operation referencing the inverted target.

#### Scenario: Append preserves prior entries

- **WHEN** `log.append(op1)` runs, then `log.append(op2)` runs
- **THEN** `log.entries` contains `[op1, op2]` in that order, neither mutated

#### Scenario: Undo is itself an operation

- **WHEN** the caller invokes `log.undo()` while `log.entries` ends with `op1`
- **THEN** a new `Undo(targetID: op1.id)` operation appends to the log, and `log.entries` count increases by one

### Requirement: ID-based operations, never positional indices

Every `Operation` referencing a structural element SHALL identify the element by stable ID (`ElementID`), never by positional index. ID derivation order: existing OOXML stable IDs (`w14:paraId`, `w:bookmarkId`, `w:id` on comments, `r:id` on relationships) → library-generated UUID stored on the in-memory `XmlNode` when no OOXML ID exists.

#### Scenario: Operation references paragraph by ID

- **WHEN** the caller emits `InsertParagraphAfter(id:)` to insert a new paragraph after an existing paragraph
- **THEN** the operation carries the existing paragraph's `ElementID` (a `w14:paraId` GUID or library UUID), not its position

#### Scenario: Independent inserts commute

- **GIVEN** the log is empty and a base tree has paragraphs `p1`, `p2`, `p3`
- **WHEN** `op_a = InsertParagraphAfter(id: p1.id, ...)` and `op_b = InsertParagraphAfter(id: p3.id, ...)` are appended in either order, and the log is replayed
- **THEN** the resulting state is identical regardless of append order: a tree with the new paragraphs in their correct positions relative to `p1` and `p3`

### Requirement: JSONL on-disk format

`OperationLog` SHALL persist to disk as a JSONL file (one operation per line, UTF-8). Each line SHALL be a self-contained JSON object containing at minimum: `op_type`, `op_id`, `timestamp`, `source` (`"swift"` or `"word"`), and `payload`.

#### Scenario: Each line is a self-contained JSON object

- **WHEN** the file is opened with any line-by-line text reader
- **THEN** every line parses independently as a JSON object containing the required fields

#### Scenario: Append is single-line write

- **WHEN** `log.append(op)` flushes to disk
- **THEN** exactly one line is appended to the JSONL file using `O_APPEND` semantics; existing content is unchanged

##### Example: Operation JSONL line

- **GIVEN** an `InsertParagraphAfter` op
- **WHEN** the op is serialized
- **THEN** the line reads:
  `{"op_id":"6e3f2c","op_type":"insert_paragraph_after","timestamp":"2026-05-05T10:23:15.421Z","source":"swift","payload":{"after_id":"0AB7C123","element_id":"6f0a1b2c-...","text":"Hello","style":null}}`

### Requirement: Operation taxonomy covers full OOXML mutation surface

The `Operation` enum SHALL include element-level cases for the high-frequency OOXML mutations and tree-node-level cases as the schema-complete fallback. Required element-level cases include `InsertParagraphAfter`, `InsertParagraphBefore`, `RemoveParagraph`, `SetText`, `SetParagraphStyle`, `InsertTable`, `RemoveTable`, `SetCellText`, `InsertRun`, `SetRunFormat`, `InsertBookmark`, `InsertComment`, `Undo`, `Redo`, `BatchBegin`, `BatchEnd`. Required tree-node-level fallback cases include `InsertNode(parentID, beforeID?, xml)`, `RemoveNode(id)`, `UpdateAttribute(id, key, value?)`, `MoveNode(id, newParentID, beforeID?)`.

#### Scenario: Tree-node fallback covers schema gap

- **WHEN** a mutation touches an element class with no element-level operation (e.g., a custom `<w16cid:commentsExtensible>` entry)
- **THEN** the mutation is encoded as `InsertNode` / `RemoveNode` / `UpdateAttribute` ops referencing the tree node by ID, and replay reproduces the mutation byte-equal

### Requirement: Source attribution for every operation

Every operation SHALL carry a `source` field with value `"swift"` (originated from a Swift mutation) or `"word"` (inferred from a Word-import diff).

#### Scenario: Swift-originated operation

- **WHEN** Swift code calls `paragraph.text = "x"` and the resulting op is appended
- **THEN** the op's `source` is `"swift"`

#### Scenario: Word-imported operation

- **WHEN** `WordImport` infers a `SetText` operation from a Word-saved docx diff
- **THEN** the op's `source` is `"word"`

### Requirement: Batch transactions for grouped mutations

The library SHALL provide `OperationLog.batch(_:)` which wraps N inner appends into a single atomic transaction marked by `BatchBegin` / `BatchEnd` operations. Replay of a batch SHALL apply all inner ops or none (atomic).

#### Scenario: Batch atomicity

- **WHEN** `log.batch { log.append(op_a); log.append(op_b) }` runs and replay is interrupted between `op_a` and `op_b`
- **THEN** the resulting state has neither `op_a` nor `op_b` applied (rolled back to pre-batch state)

#### Scenario: Batch reduces tree apply passes

- **WHEN** a batch wraps 1000 setText calls
- **THEN** the tree-apply traversal happens once at `BatchEnd`, not 1000 times

### Requirement: Operation IDs are unique and stable

Every operation SHALL have a globally unique `op_id` (UUID v4 or content-derived stable hash). Replaying the same log SHALL produce the same sequence of `op_id` values.

#### Scenario: Replay-stable op_ids

- **WHEN** the same log file is replayed twice on the same base tree
- **THEN** the `op_id` of each operation in both replays matches

### Requirement: ElementID derivation rules

`ElementID` SHALL be derived from existing OOXML stable IDs in priority order: (1) `w14:paraId` for paragraphs, (2) `w:id` for comments and bookmarks, (3) `r:id` for relationships, (4) `w14:textId` as a tiebreaker for paragraphs. When none of these are present, a library-generated UUID v4 SHALL be assigned and stored on the in-memory `XmlNode`. Library-generated UUIDs SHALL NOT be persisted into the docx (Word would strip them).

#### Scenario: Existing w14:paraId is reused

- **GIVEN** a paragraph with `<w:p w14:paraId="0AB7C123"/>`
- **WHEN** the paragraph is read into the tree
- **THEN** the `ElementID` for that paragraph equals `"0AB7C123"` (or a typed wrapper carrying that GUID)

#### Scenario: Missing OOXML ID generates UUID

- **GIVEN** a paragraph without `w14:paraId`
- **WHEN** the paragraph is read into the tree
- **THEN** an `ElementID(uuid: ...)` is generated for in-memory use; the docx is not modified

### Requirement: Forward-compatible log format

Log readers SHALL ignore unknown op_type values without crashing, and SHALL preserve unknown fields when re-serializing entries.

#### Scenario: Unknown op_type is preserved on re-serialize

- **WHEN** a log file contains a line with `op_type: "future_op_v2"` and the current library does not recognize it
- **THEN** the line round-trips through read-then-write byte-equal; the operation is treated as opaque (replay leaves the tree unchanged for that op)

### Requirement: Authoring operations extend the taxonomy additively with OOXML-mirror naming

Operations required by the `.mdocx` authoring surface (`mdocx-grammar`) SHALL be added to the `Operation` enum additively: existing cases and their JSONL wire shapes SHALL NOT change. New operation names and payload field names SHALL mirror official OOXML (ECMA-376 WordprocessingML) vocabulary where a correspondence exists — the same naming policy `mdocx-grammar` mandates for DSL elements, extended to the op layer (#128). Ops with no OOXML correspondence SHALL be documented as explicit exceptions with justification.

This spec is the single normative home of the operation wire format. Other specs (`mdocx-grammar`, `ooxml-script-transcode`) SHALL reference operations by canonical name and SHALL NOT restate their shapes.

#### Scenario: New op names anchor to ECMA-376 vocabulary

- **WHEN** a new operation targeting run content is added
- **THEN** its name and payload reference the OOXML element vocabulary (`run` ↔ `<w:r>`, `tab` ↔ `<w:tab>`, `styleId` ↔ `<w:pStyle w:val>`), not invented synonyms

##### Example: OOXML-mirror correspondence table

| Op / payload field | OOXML anchor (ECMA-376 WordprocessingML) |
| --- | --- |
| `appendParagraph` / `insertParagraphAfter` target | `<w:p>` as child of `<w:body>` (or container) |
| `paraId` (ParagraphPayload) | `w14:paraId` attribute |
| `setRuns` | `<w:r>` children of `<w:p>` |
| `bold` (RunPayload) | `<w:b>` (§17.3.2.1 "b (Bold)") |
| `italic` (RunPayload) | `<w:i>` (§17.3.2.16, ECMA title "Italics"; field spelled `italic` for cross-payload consistency with the shipped `RunFormatPayload.italic`) |
| `color` (RunPayload) | `<w:color w:val>` |
| `styleId` | `<w:pStyle w:val>` reference / `<w:style w:styleId>` definition |
| `insertTab` | `<w:tab/>` (§17.3.3.24) inside `<w:r>` |
| `insertBreak` | `<w:br/>` (§17.3.3.1) inside `<w:r>` |
| `insertNoBreakHyphen` | `<w:noBreakHyphen/>` (§17.3.3.18) inside `<w:r>` |
| `beginComponent` / `endComponent` | (none — documented exception: op-log metadata) |

### Requirement: AppendParagraph anchors construction-order inserts

The taxonomy SHALL include `appendParagraph(in: ElementID?, paragraph: ParagraphPayload)` appending a paragraph as the last block-level child of the container addressed by `in` (`nil` = the document body). This covers the authoring case where no preceding sibling exists yet; subsequent construction-order inserts SHALL use the existing `insertParagraphAfter(after:)` anchored on the previously emitted element. To carry the DSL's mandatory explicit identifiers (`mdocx-grammar` "Mandatory explicit identifiers on structural elements"), `ParagraphPayload` SHALL gain an optional `paraId` field (↔ `w14:paraId`); when present the reducer stamps it on the created `<w:p>`, when absent the existing opID-derived libraryUUID behavior applies unchanged. Addressing stays ID-based — no positional index parameter exists (per the "ID-based operations, never positional indices" requirement; `mdocx-grammar` example indices are derived display metadata, not addressing).

#### Scenario: First paragraph in an empty body

- **GIVEN** an empty document body and an empty log
- **WHEN** the DSL emits its first paragraph
- **THEN** the op is `appendParagraph(in: nil, paragraph: ...)`; the second paragraph emits `insertParagraphAfter(after: <first-id>)`

### Requirement: SetRuns replaces inline content with typed run payloads

The taxonomy SHALL include `setRuns(target: ElementID, runs: [RunPayload])` replacing the addressed paragraph's inline content. The formatting fields SHALL be added to the existing `RunPayload` struct (which today carries only `text`) — NOT to the separate `RunFormatPayload` used by `setRunFormat` — as optionals: `bold` ↔ `<w:b>`, `italic` ↔ `<w:i>`, `color` ↔ `<w:color w:val>`. Spelling note: ECMA-376 titles `<w:i>` "Italics", but the field is spelled `italic` for cross-payload consistency with the shipped `RunFormatPayload.italic` (the OOXML anchor is the element `<w:i>` itself, which both spellings mirror).

#### Scenario: Formatted runs round-trip through the log

- **WHEN** `setRuns(target: p, runs: [{text: "本章探討"}, {text: "意識本質", bold: true}])` replays
- **THEN** the paragraph contains two `<w:r>` children in order, the second carrying `<w:rPr><w:b/></w:rPr>`

### Requirement: DefineStyle registers style definitions once

The taxonomy SHALL include `defineStyle(payload: StylePayload)` carrying `styleId` (↔ `<w:style w:styleId>`) plus properties. Replaying a `defineStyle` whose `styleId` already exists SHALL be an idempotent no-op (define-on-first-use semantics from `mdocx-grammar` stay replay-safe).

#### Scenario: Duplicate defineStyle is idempotent

- **WHEN** two `defineStyle(styleId: "titleBrown", ...)` ops replay
- **THEN** styles.xml contains exactly one `titleBrown` definition and replay does not throw

### Requirement: Component envelope ops are log metadata only

The taxonomy SHALL include `beginComponent(type: String, id: ElementID)` / `endComponent(id: ElementID)` bracketing a `WordComponent` expansion. **Documented exception to OOXML-mirror naming**: these have no OOXML correspondence by design — they are op-log metadata (like the batch markers) and SHALL produce zero elements in serialized OOXML; the reducer treats them as no-ops.

#### Scenario: Envelope produces no OOXML artifact

- **WHEN** a log containing a `beginComponent`/`endComponent` pair replays and the tree serializes
- **THEN** the output contains no element corresponding to either op

### Requirement: Inline atom ops mirror OOXML empty elements

The taxonomy SHALL include `insertTab(in: ElementID)`, `insertBreak(in: ElementID)`, and `insertNoBreakHyphen(in: ElementID)` appending the corresponding empty inline element (`<w:tab/>`, `<w:br/>`, `<w:noBreakHyphen/>`) in construction order. `in:` SHALL address a **run** (`<w:r>`) — these atoms are only schema-valid inside `<w:r>`, never as direct children of `<w:p>`. When the DSL emits a standalone atom with no preceding run in the paragraph, the reducer SHALL synthesize an empty wrapping `<w:r>` first. No index parameter (same ID-based rule as AppendParagraph). Scope note: a bare `<w:br/>` is the text-wrapping line break; page/column breaks (`w:type="page|column"`) are out of scope until a future additive `type:` parameter.

#### Scenario: Tab op appends w:tab

- **WHEN** `insertTab(in: <run-id>)` replays
- **THEN** the addressed `<w:r>` gains a trailing `<w:tab/>` child
