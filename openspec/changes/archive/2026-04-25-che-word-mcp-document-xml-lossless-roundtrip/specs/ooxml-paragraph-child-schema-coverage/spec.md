## ADDED Requirements

### Requirement: WordDocument paragraph child elements have typed model or raw-carrier with position index

Every legal child element of `<w:p>` (per ECMA-376 Part 1 §17.3.1 `CT_P` complex type and the §EG_PContent / §EG_RunLevelElts content groups) SHALL have one of:

1. A typed model (e.g., `Run`, `Hyperlink`, `FieldSimple`, `AlternateContent`) reachable via a parallel array on `Paragraph`, OR
2. A raw-carrier model (e.g., `BookmarkRangeMarker`, `CommentRangeMarker`, `PermissionRangeMarker`, `ProofErrorMarker`, `SmartTagBlock`, `CustomXmlBlock`, `BidiOverrideBlock`) holding the verbatim XML string.

Every model in either category SHALL expose a `position: Int` field. `DocxReader` SHALL assign positions in source-document order while walking `<w:p>` children, starting at 0 and incrementing by 1 per child encountered. The Writer (`Paragraph.toXML()`) SHALL collect every child instance from every parallel array, sort them by `position` ascending, and emit XML in that order.

The set of legal `<w:p>` children SHALL be enumerated against an explicit reference (ECMA-376 spec table) and verified against real-world documents (NTPU master's thesis sampling). Any child element encountered by the Reader that does not match any typed model or raw-carrier SHALL trigger a test failure (`XCTFail`) with the element name in the failure message, so spec gaps are surfaced rather than silently dropped.

#### Scenario: Reader assigns sequential positions to interleaved children

- **GIVEN** a paragraph with source XML `<w:p><w:r><w:t>A</w:t></w:r><w:bookmarkStart w:id="0" w:name="b1"/><w:r><w:t>B</w:t></w:r><w:hyperlink w:anchor="x"><w:r><w:t>C</w:t></w:r></w:hyperlink><w:bookmarkEnd w:id="0"/><w:r><w:t>D</w:t></w:r></w:p>`
- **WHEN** `DocxReader` parses the paragraph
- **THEN** `Paragraph.runs` contains 3 entries with positions 0, 2, 5 (text "A", "B", "D")
- **AND** `Paragraph.bookmarkMarkers` contains 2 entries with positions 1, 4 (bookmarkStart name "b1" id 0, bookmarkEnd id 0)
- **AND** `Paragraph.hyperlinks` contains 1 entry with position 3 (anchor "x", containing a Run with text "C")

##### Example: positions before and after Writer round-trip

| Source order | Element            | Position |
| ------------ | ------------------ | -------- |
| 0            | `<w:r>A</w:r>`     | 0        |
| 1            | `<w:bookmarkStart>` | 1        |
| 2            | `<w:r>B</w:r>`     | 2        |
| 3            | `<w:hyperlink>`    | 3        |
| 4            | `<w:bookmarkEnd>`  | 4        |
| 5            | `<w:r>D</w:r>`     | 5        |

After `Paragraph.toXML()` emit, the output XML order is identical to source order.

#### Scenario: Unknown child element triggers XCTFail with element name

- **GIVEN** the lossless round-trip test suite
- **WHEN** the Reader encounters an `<w:p>` child whose local name does not match any typed model or registered raw-carrier (e.g., a hypothetical `<w:foo>` element)
- **THEN** the test SHALL fail with a message containing the unrecognized element local name
- **AND** the failure message SHALL identify which `<w:p>` child position contained the unknown element

#### Scenario: Writer is order-stable across mutations

- **GIVEN** a Paragraph with 5 children at positions 0, 1, 2, 3, 4
- **WHEN** a mutation tool inserts a new Run between positions 2 and 3 with assigned position 2.5 (or computed midpoint, with `position` typed as a value preserving ordering between integers)
- **AND** `Paragraph.toXML()` is called
- **THEN** the new Run is emitted between the original positions 2 and 3 in the output XML
- **AND** all other children retain their original relative order
