## ADDED Requirements

### Requirement: Hyperlink.text setter SHALL be marked deprecated and emit a compile-time warning at every call site

The `Hyperlink.text` property's setter SHALL be annotated with `@available(*, deprecated, message: "Mutates runs destructively (loses formatting / rawElements). Use .runs directly to preserve formatting; assign a single Run to replace, append/insert Runs to extend.")`. The setter's runtime behaviour SHALL remain identical to the v0.21.4 baseline (`runs = [Run(text: newValue)]`). The getter SHALL NOT be deprecated. Removal of the setter is scheduled for v0.22 (separate change).

#### Scenario: Setter call site emits compile-time warning

- **WHEN** consumer code writes `hyperlink.text = "new content"` and is recompiled against v0.21.5
- **THEN** the compile SHALL succeed with a deprecation warning whose message string contains the substring `"Use .runs directly"` and the runtime behaviour SHALL produce the same `runs` array as the v0.21.4 baseline (single Run carrying the new text)

#### Scenario: Getter remains warning-free

- **WHEN** consumer code reads `let txt = hyperlink.text`
- **THEN** the compile SHALL succeed with no deprecation warning and the returned value SHALL equal `runs.map { $0.text }.joined()`

---

### Requirement: All thirteen typed-child position fields SHALL change from non-optional Int to optional Int defaulting to nil

The `position` property SHALL be redeclared as `public var position: Int? = nil` in every typed-child model that previously declared it as `public var position: Int` or `public var position: Int = 0`. The thirteen sites SHALL be `Hyperlink.swift` (Hyperlink), `Run.swift` (Run), `AlternateContent.swift` (AlternateContent), `FieldSimple.swift` (FieldSimple), `Field.swift` (StructuredDocumentTag), and `ParagraphChildMarkers.swift` (eight marker types: BookmarkMarker, CommentRangeMarker, FieldCharMarker, PermissionRangeMarker, ProofErrorMarker, SectionPropertiesMarker, MoveRangeMarker, and one additional marker family at the listed line numbers). Each model's initializer SHALL propagate the optional default. The unrelated `Field.swift:466` `position` field SHALL NOT be modified (already `Int?` for a different purpose).

#### Scenario: Default-constructed typed child has nil position

- **WHEN** consumer code constructs `let h = Hyperlink(/* no position argument */)` (or `Run(...)`, `AlternateContent(...)`, etc.)
- **THEN** the resulting value SHALL have `position == nil`

#### Scenario: Reader-loaded typed child has explicit position

- **WHEN** `DocxReader.read(from:)` parses a `.docx` and constructs the typed children with their source-document positions
- **THEN** every Reader-constructed typed child SHALL have `position != nil` (the explicit Reader-assigned value)

#### Scenario: Caller migration via nil-coalescing

- **WHEN** consumer code that previously read `let p: Int = h.position` is recompiled against v0.21.5
- **THEN** the compile SHALL fail with a type mismatch error and the migration SHALL be `let p = h.position ?? 0` (or any explicit fallback the caller chooses)

##### Example: thirteen-site cascade

| File | Symbol | Pre-change | Post-change |
| ---- | ------ | ---------- | ----------- |
| Hyperlink.swift | `Hyperlink.position` | `Int = 0` | `Int? = nil` |
| Run.swift | `Run.position` | `Int = 0` | `Int? = nil` |
| AlternateContent.swift | `AlternateContent.position` | `Int` | `Int? = nil` |
| FieldSimple.swift | `FieldSimple.position` | `Int` | `Int? = nil` |
| Field.swift | `StructuredDocumentTag.position` | `Int` | `Int? = nil` |
| ParagraphChildMarkers.swift × 8 | each marker's `.position` | `Int` | `Int? = nil` |

---

### Requirement: Paragraph sort-by-position emit SHALL partition typed children into explicit and append cohorts

`Paragraph.toXMLSortedByPosition()` SHALL, for each typed-child collection it traverses, partition members into "explicit" (`position != nil`) and "append" (`position == nil`) cohorts. The explicit cohort SHALL be emitted at its assigned positions in the existing sort order. The append cohort SHALL be emitted *after* the highest explicit position in the same collection, at sequential positions starting from `(max(explicit) ?? 0) + 1`. The append base SHALL be computed per-collection so each typed-child kind appends within its own append-window.

#### Scenario: paragraph.runs.append(...) lands after source children

- **GIVEN** a paragraph loaded from disk with three runs at positions 1, 2, 3
- **WHEN** consumer code calls `paragraph.runs.append(Run(text: "z"))` (the new run defaults to `position == nil`) and then `paragraph.toXMLSortedByPosition()`
- **THEN** the emitted XML SHALL contain the new run AFTER the three source runs (at effective position 4), NOT before them

#### Scenario: All-nil collection emits in caller-provided order

- **GIVEN** a paragraph constructed entirely API-side with three runs all at `position == nil`
- **WHEN** consumer code calls `paragraph.toXMLSortedByPosition()`
- **THEN** the three runs SHALL emit at positions 1, 2, 3 in the order they appear in the `paragraph.runs` array

#### Scenario: Sparse explicit positions still append correctly

- **WHEN** a paragraph has runs at positions 1 and 100 (both explicit), and one append-mode run is added
- **THEN** the append-mode run SHALL emit at effective position 101, not at position 2

##### Example: position partition outcomes

| Existing children | Append-mode child | Effective emit position of appendee |
| ----------------- | ----------------- | ----------------------------------- |
| (empty) | one run | 1 |
| [pos 1, pos 2] | one run | 3 |
| [pos 1, pos 2, pos 3] | one run | 4 |
| [pos 1, pos 100] | one run | 101 |
| [pos 1, pos 2] | two runs | 3, 4 |

---

### Requirement: Run.toXML SHALL auto-emit xml:space="preserve" when text contains semantically significant whitespace

`Run.toXML()` SHALL inspect the assigned `text` string and emit `<w:t xml:space="preserve">` instead of `<w:t>` when ANY of the following hold: (a) the text begins with a whitespace character; (b) the text ends with a whitespace character; (c) the text contains two or more consecutive whitespace characters anywhere. Single internal whitespace (e.g., `"hello world"`) SHALL NOT trigger the flag. Empty text SHALL NOT trigger the flag.

#### Scenario: Leading whitespace triggers the preserve flag

- **WHEN** a Run with `text == " leading"` is emitted via `toXML()`
- **THEN** the emitted `<w:t>` element SHALL include the attribute `xml:space="preserve"`

#### Scenario: Trailing whitespace triggers the preserve flag

- **WHEN** a Run with `text == "trailing "` is emitted via `toXML()`
- **THEN** the emitted `<w:t>` element SHALL include the attribute `xml:space="preserve"`

#### Scenario: Consecutive internal whitespace triggers the preserve flag

- **WHEN** a Run with `text == "two  spaces"` is emitted via `toXML()`
- **THEN** the emitted `<w:t>` element SHALL include the attribute `xml:space="preserve"`

#### Scenario: Single internal whitespace does not trigger the flag

- **WHEN** a Run with `text == "hello world"` is emitted via `toXML()`
- **THEN** the emitted `<w:t>` element SHALL NOT include `xml:space="preserve"`

##### Example: trigger conditions

| Run text | xml:space="preserve"? |
| -------- | --------------------- |
| `""` (empty) | no |
| `"hello"` | no |
| `"hello world"` (single internal space) | no |
| `" leading"` | yes |
| `"trailing "` | yes |
| `"   "` (all spaces) | yes |
| `"two  spaces"` (double internal) | yes |
| `"a\tb"` (internal tab — single whitespace) | no |
| `"a\t\tb"` (consecutive tabs) | yes |
| `"\nleading-newline"` | yes |

---

### Requirement: Round-trip SHALL preserve byte-equivalent output for unmutated input across all three fixes

For any `.docx` round-trip (Reader → Writer → Reader) where the caller does NOT touch `Hyperlink.text` setter, does NOT change any `position` field from its Reader-assigned value, and does NOT modify any Run text, the public observable behaviour of `Paragraph.toXMLSortedByPosition()` and `Document.write(to:)` SHALL be byte-equivalent to the v0.21.4 baseline. Reader-assigned positions SHALL flow through emit unchanged. Pre-existing `xml:space="preserve"` flags on source-loaded Runs SHALL be preserved through emit.

#### Scenario: No-op round-trip of legitimate corpus document is unaffected

- **WHEN** a `.docx` from the existing test corpus is read and written back without any caller mutation
- **THEN** the output SHALL match the v0.21.4 byte-equivalence baseline and the existing test suite SHALL pass without modification

#### Scenario: Pre-existing xml:space flag is preserved on no-op round-trip

- **GIVEN** a source `.docx` containing `<w:r><w:t xml:space="preserve">  spaces  </w:t></w:r>`
- **WHEN** the document is read by `DocxReader` and written back by `DocxWriter` without any caller modification of the run text
- **THEN** the output SHALL contain `<w:t xml:space="preserve">  spaces  </w:t>` (the autosense in `Run.toXML()` re-emits the flag because the text still has leading and trailing whitespace)
