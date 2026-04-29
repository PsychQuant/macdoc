## ADDED Requirements

### Requirement: AlternateContent SHALL track whether fallbackRuns has been mutated since construction

The `AlternateContent` value type SHALL expose `public private(set) var fallbackRunsModified: Bool = false`. The `fallbackRuns` property SHALL be implemented with a `didSet` observer that flips `fallbackRunsModified` to `true` whenever the array is reassigned, mutated through index, appended, replaced, or otherwise written. Construction via `init(rawXML:fallbackRuns:position:)` SHALL leave `fallbackRunsModified` as `false` (the `didSet` SHALL NOT fire from initializer assignment).

#### Scenario: Reader-loaded AlternateContent starts clean

- **WHEN** `DocxReader.read(from:)` parses a `.docx` containing one or more `<mc:AlternateContent>` blocks and constructs the corresponding `AlternateContent` values
- **THEN** every constructed `AlternateContent.fallbackRunsModified` SHALL equal `false`

#### Scenario: Reassigning fallbackRuns flips the flag

- **WHEN** caller code assigns `ac.fallbackRuns = [Run(text: "new")]` on a previously-clean `AlternateContent`
- **THEN** `ac.fallbackRunsModified` SHALL equal `true` immediately after the assignment

#### Scenario: Mutating fallbackRuns through index flips the flag

- **WHEN** caller code mutates `ac.fallbackRuns[0].text = "changed"` on a previously-clean `AlternateContent`
- **THEN** `ac.fallbackRunsModified` SHALL equal `true` immediately after the mutation

##### Example: mutation patterns covered

| Mutation | Flag becomes |
| -------- | ------------ |
| `ac.fallbackRuns = [...]` | `true` |
| `ac.fallbackRuns.append(Run(...))` | `true` |
| `ac.fallbackRuns[0] = Run(...)` | `true` |
| `ac.fallbackRuns[0].text = "x"` | `true` |
| `ac.fallbackRuns.removeAll()` | `true` |
| reading `ac.fallbackRuns` | `false` (no change) |

---

### Requirement: Paragraph emit SHALL throw when AlternateContent.fallbackRuns has been mutated but rawXML was not regenerated

`Paragraph.toXMLSortedByPosition()` and any legacy emit path that traverses `Paragraph.alternateContents` SHALL inspect each `AlternateContent.fallbackRunsModified` field. When any value in the paragraph's `alternateContents` collection has `fallbackRunsModified == true`, the emit method SHALL throw `OOXMLError.unserializedFallbackEdit(position: ac.position)` and SHALL NOT write the stale `rawXML` to the output. The throw SHALL identify the offending `AlternateContent` by its `position` so the caller can locate the paragraph in the model.

#### Scenario: Modified fallbackRuns triggers throw on emit

- **WHEN** a paragraph contains an `AlternateContent` whose `fallbackRuns` has been mutated since construction (so `fallbackRunsModified == true`) and the caller invokes `paragraph.toXMLSortedByPosition()`
- **THEN** the call SHALL throw `OOXMLError.unserializedFallbackEdit(position: ac.position)` and SHALL NOT return any partial XML output for the offending paragraph

#### Scenario: Unmodified fallbackRuns emits cleanly

- **WHEN** a paragraph contains an `AlternateContent` whose `fallbackRunsModified` is `false` (Reader-loaded, untouched)
- **THEN** `toXMLSortedByPosition()` SHALL emit `ac.rawXML` at `ac.position` exactly as before this change, byte-equivalent to the v0.21.3 baseline

#### Scenario: Multiple AlternateContents — only modified one triggers throw

- **WHEN** a paragraph contains two `AlternateContent` values, only one of which has `fallbackRunsModified == true`
- **THEN** the emit SHALL throw `OOXMLError.unserializedFallbackEdit(position:)` carrying the position of the modified one and SHALL NOT emit any output until both are clean

---

### Requirement: Paragraph commentIds SHALL be deprecated and converted to a computed property derived from commentRangeMarkers

`Paragraph.commentIds` SHALL be marked `@available(*, deprecated, message: "Use commentRangeMarkers (source of truth since Phase 4).")`. The property SHALL be removed from Reader population (Reader SHALL stop writing to it directly) and SHALL be converted to a computed get-only property whose body derives the id list from `commentRangeMarkers`. Existing callers that read `commentIds` SHALL continue to compile (with a deprecation warning) and SHALL observe the same id values as before for any paragraph loaded from disk.

#### Scenario: Reader-loaded paragraph commentIds matches markers

- **WHEN** `DocxReader.read(from:)` parses a paragraph containing `<w:commentRangeStart w:id="3"/>` and `<w:commentRangeEnd w:id="3"/>`
- **THEN** `paragraph.commentIds` SHALL return `[3]` and `paragraph.commentRangeMarkers` SHALL contain a start+end pair both with `id == 3`

#### Scenario: commentIds compiles with deprecation warning

- **WHEN** consumer code reads `paragraph.commentIds`
- **THEN** the compile SHALL succeed with a deprecation warning pointing at `commentRangeMarkers` and the value returned SHALL match the v0.21.3 baseline behaviour

#### Scenario: commentIds reflects markers added post-Reader

- **WHEN** caller code appends a new `CommentRangeMarker` to `paragraph.commentRangeMarkers` (matched start+end pair with `id == 99`)
- **THEN** the next read of `paragraph.commentIds` SHALL include `99` in the returned list (computed property reflects the live marker state)

---

### Requirement: Comment range markers SHALL survive a sort-by-position emit round-trip with all three structural elements preserved at original positions

A paragraph whose source XML contains a `<w:commentRangeStart>` marker, a `<w:r><w:commentReference/></w:r>` inner run, and a `<w:commentRangeEnd>` marker SHALL round-trip through Reader → `toXMLSortedByPosition()` → re-Reader with all three elements preserved at the same relative positions. The round-trip SHALL NOT collapse, drop, reorder, or duplicate any of the three elements.

#### Scenario: Single-comment paragraph round-trip preserves all three markers

- **GIVEN** input XML `<w:p><w:commentRangeStart w:id="1"/><w:r><w:commentReference w:id="1"/></w:r><w:commentRangeEnd w:id="1"/></w:p>`
- **WHEN** the paragraph is read by `DocxReader`, emitted via `toXMLSortedByPosition()`, and re-read
- **THEN** the re-read paragraph SHALL contain exactly one `commentRangeStart` marker with `id == 1`, exactly one `commentReference` run-child with `id == 1`, and exactly one `commentRangeEnd` marker with `id == 1`, all at their original positions

##### Example: marker count invariant

| Element | Initial count | Post-round-trip count |
| ------- | ------------- | --------------------- |
| `commentRangeStart` markers | 1 | 1 |
| `commentReference` run children | 1 | 1 |
| `commentRangeEnd` markers | 1 | 1 |

---

### Requirement: OOXMLError SHALL expose the unserializedFallbackEdit case

The `OOXMLError` enum in `Sources/OOXMLSwift/Models/OOXMLError.swift` SHALL define the case:

```swift
case unserializedFallbackEdit(position: Int)
```

The associated value `position` SHALL carry the `AlternateContent.position` of the offending value so the caller can locate the paragraph in their model. The case SHALL be added to the existing enum so consumers continue to catch a single `OOXMLError`.

#### Scenario: Caller distinguishes unserializedFallbackEdit from other OOXMLError cases

- **WHEN** a caller wraps `try paragraph.toXMLSortedByPosition()` in `do/catch` and switches on the caught `OOXMLError`
- **THEN** the caller SHALL be able to match `.unserializedFallbackEdit(let position)` distinctly from other `OOXMLError` cases and read the `position` integer for diagnostics

---

### Requirement: Round-trip SHALL preserve byte-equivalent output for unmutated input

For any input that does not mutate `AlternateContent.fallbackRuns` after Reader load and does not mutate `commentRangeMarkers` after Reader load, the public observable behaviour of `Paragraph.toXMLSortedByPosition()` and `Document.write(to:)` SHALL be byte-equivalent to the v0.21.3 baseline. No additional throws, no new error semantics, no changed emit ordering for the no-op case SHALL be introduced.

#### Scenario: No-op round-trip of legitimate corpus document is unaffected

- **WHEN** a `.docx` from the existing test corpus is read and written back without mutating `fallbackRuns` or marker collections
- **THEN** the output SHALL match the v0.21.3 byte-equivalence baseline and the existing test suite SHALL pass without modification
