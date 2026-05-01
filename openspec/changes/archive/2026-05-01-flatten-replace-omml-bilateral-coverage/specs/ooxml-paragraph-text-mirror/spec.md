## ADDED Requirements

### Requirement: flattenedDisplayText walks direct-child OMML at all 4 wrapper positions

The `Paragraph.flattenedDisplayText()` method SHALL include the visible text of `<m:oMath>` and `<m:oMathPara>` elements appearing as direct children of: (a) the paragraph itself (`<w:p>`), (b) any hyperlink wrapper (`<w:hyperlink>`), (c) any `<mc:Fallback>` block, AND (d) any nested wrapper combination (e.g., `<w:hyperlink>` containing `<w:fldSimple>` containing OMML). The OMML visible text SHALL appear at the position dictated by the source XML, not at a fixed wrapper-class iteration position.

#### Scenario: Direct-child OMML in paragraph

- **WHEN** `flattenedDisplayText()` is invoked on a paragraph whose source XML is `<w:p><w:r><w:t>see eq </w:t></w:r><m:oMath><m:r><m:t>δ</m:t></m:r></m:oMath><w:r><w:t> here</w:t></w:r></w:p>`
- **THEN** the returned string SHALL equal `"see eq δ here"`

##### Example: Position-ordered output across run / OMML / run sequence
- **GIVEN** paragraph runs at positions 1, 3 with `<w:t>` content "see eq " and " here"; direct-child OMML at position 2 with visible text "δ"
- **WHEN** `flattenedDisplayText()` is called
- **THEN** result is `"see eq δ here"` (positions interleaved by source XML order, NOT runs-then-OMML hardcoded order)

#### Scenario: Direct-child OMML in hyperlink

- **WHEN** `flattenedDisplayText()` is invoked on a paragraph containing `<w:hyperlink><m:oMath><m:r><m:t>θ</m:t></m:r></m:oMath></w:hyperlink>`
- **THEN** the returned string SHALL include `"θ"`

#### Scenario: Direct-child OMML in mc:Fallback

- **WHEN** `flattenedDisplayText()` is invoked on a paragraph whose `<mc:AlternateContent>` has a `<mc:Fallback>` containing `<m:oMath><m:r><m:t>κ</m:t></m:r></m:oMath>` as direct child (no `<w:r>` wrapper)
- **THEN** the returned string SHALL include `"κ"`

#### Scenario: Nested wrapper containing OMML

- **WHEN** `flattenedDisplayText()` is invoked on a paragraph containing `<w:hyperlink><w:fldSimple w:instr="REF eq1 \h"><w:r><m:oMath><m:r><m:t>η</m:t></m:r></m:oMath></w:r></w:fldSimple></w:hyperlink>`
- **THEN** the returned string SHALL include `"η"`

### Requirement: replaceInParagraphSurfaces detects OMML boundaries at all 4 wrapper positions

The `Document.replaceInParagraphSurfaces` static method SHALL walk the same 4 wrapper positions as `flattenedDisplayText` for boundary detection. When a replacement match span intersects any direct-child OMML element at any of those positions, the method SHALL refuse the replacement at that occurrence and return that occurrence in `ReplaceResult.refusedDueToOMMLBoundary(occurrences:)`. Replacement occurrences whose match span lies wholly within `<w:t>` ranges (no OMML intersection) SHALL proceed normally and be counted in `ReplaceResult.replaced(count:)`.

#### Scenario: Replacement wholly within <w:t> proceeds

- **WHEN** `replaceInParagraphSurfaces(find: "here", with: "there", ...)` is invoked on a paragraph whose XML is `<w:p><w:r><w:t>see eq </w:t></w:r><m:oMath>δ</m:oMath><w:r><w:t> here</w:t></w:r></w:p>`
- **THEN** the result SHALL be `ReplaceResult.replaced(count: 1)`
- **AND** run 3's `<w:t>` content SHALL become `" there"`
- **AND** the OMML element SHALL remain unchanged

#### Scenario: Replacement crossing OMML refuses

- **WHEN** `replaceInParagraphSurfaces(find: "eq δ here", with: "ref X", ...)` is invoked on the same paragraph
- **THEN** the result SHALL be `ReplaceResult.refusedDueToOMMLBoundary(occurrences:)` with at least one occurrence whose `matchSpan` covers character positions 4 through 13 inclusive AND whose `ommlSpans` includes the OMML at position 7
- **AND** no `<w:t>` content in the paragraph SHALL change
- **AND** the OMML element SHALL remain unchanged

##### Example: Refused occurrence structure
- **GIVEN** paragraph flattens to `"see eq δ here"` (positions 0-12) with OMML "δ" at position 7
- **WHEN** find "eq δ here" (matches at position 4-12)
- **THEN** result is `ReplaceResult.refusedDueToOMMLBoundary(occurrences: [(matchSpan: 4..<13, ommlSpans: [7..<8])])`
- **AND** no mutation occurs

#### Scenario: Mixed wholly-within and cross-OMML matches in same paragraph

- **WHEN** a paragraph contains the same find string twice — once wholly within `<w:t>` and once crossing OMML — and `replaceInParagraphSurfaces(find:, with:, ...)` is called
- **THEN** the wholly-within occurrence SHALL be replaced and counted in `ReplaceResult.replaced(count:)`
- **AND** the cross-OMML occurrence SHALL be reported in `ReplaceResult.refusedDueToOMMLBoundary(occurrences:)`
- **AND** the result SHALL combine both — `ReplaceResult` MUST signal both `count > 0` replaced AND non-empty refused occurrences (concrete combinator shape decided in `tasks.md`; the spec contract is "both signals carried")

### Requirement: ReplaceResult enum carries informative refusal occurrences

The `ReplaceResult` enum SHALL be a public type in `OOXMLSwift` with at minimum two cases: `.replaced(count: Int)` for successful replacement count, and `.refusedDueToOMMLBoundary(occurrences: [Occurrence])` for replacement requests that crossed OMML boundaries. Each `Occurrence` SHALL carry a `matchSpan: Range<Int>` (character positions in the flattened text where the find string matched) AND an `ommlSpans: [Range<Int>]` (one or more OMML element spans intersecting the match). Future cases MAY be added (e.g., refusals due to other structural boundaries) without removing existing cases.

#### Scenario: Successful replacement returns count

- **WHEN** `replaceInParagraphSurfaces` performs N successful replacements with no boundary refusals
- **THEN** the result SHALL be `ReplaceResult.replaced(count: N)`

#### Scenario: Refusal occurrence carries match and OMML span data

- **WHEN** `replaceInParagraphSurfaces` refuses an occurrence due to OMML boundary
- **THEN** the returned occurrence's `matchSpan` SHALL contain the character positions of the find match in the paragraph's flattened text
- **AND** the occurrence's `ommlSpans` SHALL contain at least one range that intersects `matchSpan` AND corresponds to a direct-child OMML element in the paragraph

#### Scenario: Anchor not found returns count zero

- **WHEN** `replaceInParagraphSurfaces` is invoked with a find string that does not appear in any walked surface AND no OMML boundary is intersected (because no match exists)
- **THEN** the result SHALL be `ReplaceResult.replaced(count: 0)` (NOT `refusedDueToOMMLBoundary`)

### Requirement: Mirror invariant — same surface coverage, asymmetric on OMML detected

The mirror invariant between `flattenedDisplayText` (read) and `replaceInParagraphSurfaces` (write) SHALL hold the property: both functions walk the same set of wrapper surfaces (top-level runs, hyperlinks, fieldSimples, alternateContents.fallbackRuns, contentControls) AND both detect direct-child OMML at the same 4 positions. The functions SHALL diverge in their *handling* of detected OMML: read includes OMML visible text in returned string; write treats OMML as an opaque boundary marker that triggers refusal when match spans cross it. This asymmetry SHALL be documented in the `flattenedDisplayText` docstring.

#### Scenario: Read includes OMML visible text

- **WHEN** any paragraph containing direct-child OMML at any of the 4 wrapper positions is queried via `flattenedDisplayText()`
- **THEN** the returned string SHALL include each OMML element's `visibleText`

#### Scenario: Write treats OMML as opaque boundary

- **WHEN** any paragraph containing direct-child OMML at any of the 4 wrapper positions is mutated via `replaceInParagraphSurfaces(find:, with:, ...)` AND the find string match span intersects OMML
- **THEN** the OMML element's source XML SHALL NOT be modified
- **AND** the occurrence SHALL be reported in `ReplaceResult.refusedDueToOMMLBoundary(occurrences:)`

#### Scenario: Surface coverage parity

- **WHEN** a wrapper position is added to one of `flattenedDisplayText` or `replaceInParagraphSurfaces` in future code change
- **THEN** the same wrapper position SHALL be added to the other function in the same change (mirror invariant SHALL NOT regress to one-sided coverage)

### Requirement: Direct-child OMML storage remains raw passthrough

Direct-child OMML elements SHALL remain stored as raw XML in the existing storage locations: `Paragraph.unrecognizedChildren` (filtered by `name == "oMath" || name == "oMathPara"`), `HyperlinkChild.rawXML(_)`, and `AlternateContent.rawXML`. The walker SHALL NOT promote these to typed model fields. The `OMMLParser.parse(xml:)` API SHALL be used to extract `visibleText` on demand at flatten / boundary-check time. Round-trip serialization of paragraphs containing direct-child OMML SHALL produce byte-identical output to the source XML.

#### Scenario: Round-trip preserves direct-child OMML XML

- **WHEN** a `WordDocument` containing a paragraph with direct-child OMML at any of the 4 wrapper positions is read via `DocxReader.read(from:)` and immediately written via `DocxWriter.write(to:)` with no intervening mutation
- **THEN** the written `word/document.xml` SHALL contain the same direct-child OMML element at the same source XML position

#### Scenario: Walker reads from raw storage on demand

- **WHEN** `flattenedDisplayText()` or `replaceInParagraphSurfaces` walker encounters a paragraph child stored as `UnrecognizedChild` with `name == "oMath"` or `name == "oMathPara"`
- **THEN** the walker SHALL invoke `OMMLParser.parse(xml: child.rawXML).visibleText` to extract OMML visible text
- **AND** the walker SHALL NOT mutate `child.rawXML`
