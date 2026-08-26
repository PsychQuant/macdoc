## ADDED Requirements

### Requirement: Raw-channel slot designation by paraId

When a document's `word/document.xml` rides the raw channel (no DSL upgrade), slot designation by paragraph id SHALL still succeed as long as the designated `w14:paraId` occurs exactly once inside the carried part's XML. The exported script SHALL represent each such slot as a `// @slot-raw <name> <paraId>` directive with the paragraph's concatenated `<w:t>` text as its default value. The designation SHALL fail loudly when the paraId is absent from both the DSL log and the raw part (the error naming both lookup domains), and when the paraId occurs more than once in the raw part (the error naming the duplicate count; no first-match guessing).

#### Scenario: slot on a table-bearing official form

- **GIVEN** a document containing at least one table, whose coverage report shows the main part on the raw channel with a DSL ratio of zero
- **WHEN** the operator designates a slot with a paraId present exactly once in the document part
- **THEN** the export succeeds and the script contains a `// @slot-raw` directive carrying the paragraph's current text as the default

#### Scenario: unknown paraId names both lookup domains

- **WHEN** the operator designates a slot whose paraId exists neither as a body-paragraph op in the DSL log nor inside the raw document part
- **THEN** the export refuses with a slot-designation failure whose reason names both the DSL log and the raw part as searched domains

#### Scenario: duplicate paraId refuses

- **GIVEN** a raw document part in which the designated paraId occurs twice
- **WHEN** the operator designates a slot with that paraId
- **THEN** the export refuses with a slot-designation failure naming the duplicate occurrence count

### Requirement: Raw-channel slot substitution preserves everything outside the designated paragraph

Executing a raw-channel-slotted script SHALL apply each substitution as run-level surgery on the carried XML: the designated `<w:p>` element keeps its paragraph properties, its run children are replaced by a single run carrying the dominant text run's run properties and one text element with the substituted value (XML-escaped). Every byte of the carried part outside the designated paragraphs, and every other part, SHALL remain identical to the unslotted rebuild. When a provided slot value equals the exported default, the execution SHALL leave the carried part untouched for that slot (identity shortcut), so an all-default execution reproduces the reference byte-equal and the existing byte-equal verification applies unchanged.

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
