## ADDED Requirements

### Requirement: Raw-channel slot designation by paraId

When a document's `word/document.xml` rides the raw channel (no DSL upgrade), slot designation by paragraph id SHALL still succeed as long as the designated `w14:paraId` is carried by exactly one `<w:p>` element inside the carried part's XML, determined by structure-aware scanning (element nesting and attribute positions, never bare token search — `w14:paraId` also legitimately appears on `<w:tr>` elements and inside text content). The exported script SHALL represent each such slot as a `// @slot-raw <name> <paraId>` directive with the paragraph's concatenated `<w:t>` text as its default value. The designation SHALL fail loudly in each of these cases (closed list): (a) the paraId is absent from both the DSL log and the raw part — the error naming both lookup domains; (b) the paraId is carried by more than one `<w:p>` element — the error naming the count, no first-match guessing; (c) the paraId occurs in the raw part but not on any `<w:p>` element (e.g. only on a `<w:tr>`, or only inside text content) — the error naming the actual carrier.

#### Scenario: slot on a table-bearing official form

- **GIVEN** a document containing at least one table, whose coverage report shows the main part on the raw channel with a DSL ratio of zero
- **WHEN** the operator designates a slot with a paraId present exactly once in the document part
- **THEN** the export succeeds and the script contains a `// @slot-raw` directive carrying the paragraph's current text as the default

#### Scenario: unknown paraId names both lookup domains

- **WHEN** the operator designates a slot whose paraId exists neither as a body-paragraph op in the DSL log nor inside the raw document part
- **THEN** the export refuses with a slot-designation failure whose reason names both the DSL log and the raw part as searched domains

#### Scenario: duplicate paraId refuses

- **GIVEN** a raw document part in which two `<w:p>` elements carry the designated paraId
- **WHEN** the operator designates a slot with that paraId
- **THEN** the export refuses with a slot-designation failure naming the duplicate occurrence count

#### Scenario: paraId on a non-paragraph element refuses

- **GIVEN** a raw document part in which the designated paraId appears only on a `<w:tr>` element (Word writes `w14:paraId` on table rows too)
- **WHEN** the operator designates a slot with that paraId
- **THEN** the export refuses with a slot-designation failure naming the actual carrier instead of corrupting the table

#### Scenario: paraId occurring only inside text content refuses

- **GIVEN** a raw document part where the literal string `w14:paraId="X"` appears only inside a `<w:t>` text node
- **WHEN** the operator designates a slot with paraId X
- **THEN** the export refuses (absence case) — text content is never a designation anchor

### Requirement: Raw-channel slot substitution preserves everything outside the designated paragraph

Executing a raw-channel-slotted script SHALL apply each substitution as run-level surgery on the carried XML: the designated `<w:p>` element — located with the same structure-aware scanning as designation, including paragraphs nested inside `<w:txbxContent>` and self-closing forms — keeps its paragraph properties, and its remaining children are replaced by a single run carrying the dominant text run's run properties and one text element with the substituted value (XML-escaped; values containing characters forbidden by XML 1.0 SHALL be refused, not written). Every byte of the carried part outside the designated paragraphs, and every other part, SHALL remain identical to the unslotted rebuild, and the substituted part SHALL remain well-formed XML — the execution SHALL verify well-formedness after surgery and fail loudly rather than write a corrupt part. Execution SHALL apply the designation guards again at import time (unknown slot name bound in the directive, paraId no longer locatable, or carried by more than one `<w:p>` SHALL fail loudly, never silently skip). When a provided slot value equals the exported default, the execution SHALL leave the carried part untouched for that slot (identity shortcut), so an all-default execution reproduces the reference byte-equal and the existing byte-equal verification applies unchanged.

#### Scenario: all-default execution stays byte-equal

- **GIVEN** a raw-channel-slotted script executed with every slot at its default value
- **WHEN** the output is verified against the reference document
- **THEN** every XML part is byte-identical to the reference

#### Scenario: substituted value changes only the designated paragraph

- **GIVEN** a raw-channel-slotted script executed with a new value for one slot
- **WHEN** the designated paragraph's fragment is excised from both the reference part and the output part
- **THEN** the two remainders are byte-identical and the output carries the new value inside the designated paragraph

##### Example: two-run paragraph collapses to the dominant run

- **GIVEN** a designated paragraph containing run A ("申請修正第", plain) and run B ("2", underlined), where run A's text is longer
- **WHEN** the slot executes with the value "3"
- **THEN** the paragraph carries a single run with run A's run properties and the text "3", the paragraph properties are unchanged, and all sibling paragraphs are byte-identical

#### Scenario: substitution on a paragraph containing a nested text-box paragraph

- **GIVEN** a designated `<w:p>` that contains a `<w:txbxContent>` with its own inner `<w:p>`
- **WHEN** the slot executes with a new value
- **THEN** the surgery replaces the entire designated paragraph (depth-aware close matching, not first `</w:p>`), the output part parses as well-formed XML, and sibling content is byte-identical
