## ADDED Requirements

### Requirement: SequenceField emits valid OOXML SEQ field XML

The `ooxml-swift` package SHALL provide a `SequenceField` struct conforming to `FieldCode` whose `fieldInstruction` follows the pattern `SEQ <identifier>[ <formatSwitch>][ \s <resetLevel>][ \h]` and whose `toFieldXML()` emits the five-run structure `<w:r><w:fldChar w:fldCharType="begin"/></w:r>`, `<w:r><w:instrText xml:space="preserve"> ... </w:instrText></w:r>`, `<w:r><w:fldChar w:fldCharType="separate"/></w:r>`, `<w:r><w:t>cachedResult</w:t></w:r>`, `<w:r><w:fldChar w:fldCharType="end"/></w:r>`. The `identifier` MUST accept non-ASCII characters (e.g. `圖`, `表`, `公式`). The `format: SequenceFormat` enum SHALL cover at minimum `.arabic`, `.alphabetic`, `.lowerAlphabetic`, `.roman`, `.lowerRoman`.

#### Scenario: SequenceField with ASCII identifier, arabic format, no chapter reset

- **WHEN** `SequenceField(identifier: "Figure", format: .arabic, resetLevel: nil, cachedResult: "1").toFieldXML()` is called
- **THEN** the output contains `<w:instrText xml:space="preserve"> SEQ Figure </w:instrText>` and the full five-run fldChar structure

#### Scenario: SequenceField with Chinese identifier and chapter reset

- **WHEN** `SequenceField(identifier: "圖", format: .arabic, resetLevel: 1, cachedResult: "1").toFieldXML()` is called
- **THEN** the output contains `<w:instrText xml:space="preserve"> SEQ 圖 \s 1 </w:instrText>`

### Requirement: StyleRefField emits valid OOXML STYLEREF field XML

The `ooxml-swift` package SHALL provide a `StyleRefField` struct conforming to `FieldCode` whose `fieldInstruction` follows the pattern `STYLEREF <headingLevel>[ \s]` and whose `toFieldXML()` emits the five-run fldChar structure.

#### Scenario: StyleRefField for level-1 heading with suppress-non-delimiter

- **WHEN** `StyleRefField(headingLevel: 1, suppressNonDelimiter: true, cachedResult: "4").toFieldXML()` is called
- **THEN** the output contains `<w:instrText xml:space="preserve"> STYLEREF 1 \s </w:instrText>`

### Requirement: ReferenceField emits valid OOXML reference field XML

The `ooxml-swift` package SHALL provide a `ReferenceField` struct conforming to `FieldCode` covering the three reference field types via a `ReferenceFieldType` enum (`.ref`, `.pageRef`, `.noteRef`). Its `fieldInstruction` MUST follow the pattern `<TYPE> <bookmarkName>[ \p][ \h]` and its `toFieldXML()` MUST emit the five-run fldChar structure. The spec requirement "RefField" is satisfied by `ReferenceField(type: .ref, ...)`.

#### Scenario: ReferenceField.ref pointing to a bookmark with hyperlink

- **WHEN** `ReferenceField(type: .ref, bookmarkName: "fig_returns", includeAboveBelow: false, createHyperlink: true, cachedResult: "圖 4-1").toFieldXML()` is called
- **THEN** the output contains `<w:instrText xml:space="preserve"> REF fig_returns \h </w:instrText>`

#### Scenario: ReferenceField.pageRef for page-of-bookmark reference

- **WHEN** `ReferenceField.pageOf("fig_returns", hyperlink: true).toFieldXML()` is called
- **THEN** the output contains `<w:instrText xml:space="preserve"> PAGEREF fig_returns \h </w:instrText>`

### Requirement: MathComponent protocol requires toOMML emission

The `ooxml-swift` package SHALL provide a `MathComponent` protocol with a single required method `func toOMML() -> String`. All concrete math types MUST conform to this protocol and emit valid OMML (ECMA-376 Part 1 §22.1) XML fragments.

#### Scenario: MathRun emits a single math run element

- **WHEN** `MathRun(text: "x", style: .italic).toOMML()` is called
- **THEN** the output equals `<m:r><m:rPr><m:sty m:val="i"/></m:rPr><m:t>x</m:t></m:r>`

### Requirement: Core math components emit valid OMML

The `ooxml-swift` package SHALL provide `MathFraction`, `MathSubSuperScript`, and `MathRadical` structs conforming to `MathComponent`. `MathFraction.toOMML()` MUST emit `<m:f><m:fPr>...</m:fPr><m:num>...</m:num><m:den>...</m:den></m:f>`. `MathSubSuperScript.toOMML()` MUST emit `<m:sSubSup>` when both sub and sup are present, `<m:sSub>` when only sub is present, and `<m:sSup>` when only sup is present. `MathRadical.toOMML()` MUST emit `<m:rad>`.

#### Scenario: MathFraction with nested runs

- **WHEN** `MathFraction(numerator: [MathRun(text: "a")], denominator: [MathRun(text: "b")]).toOMML()` is called
- **THEN** the output contains `<m:f>`, `<m:num><m:r><m:t>a</m:t></m:r></m:num>`, `<m:den><m:r><m:t>b</m:t></m:r></m:den>`

#### Scenario: MathSubSuperScript with only superscript

- **WHEN** `MathSubSuperScript(base: [MathRun(text: "x")], sub: nil, sup: [MathRun(text: "2")]).toOMML()` is called
- **THEN** the output starts with `<m:sSup>` and contains the base `x` and sup `2`

### Requirement: N-ary and delimiter math components emit valid OMML

The `ooxml-swift` package SHALL provide `MathNary` (sum, integral, product), `MathDelimiter`, `MathFunction`, `MathLimit`, and `MathMatrix` structs conforming to `MathComponent`. `MathNary.toOMML()` MUST emit `<m:nary>` with `<m:naryPr><m:chr m:val="∑|∫|∏"/></m:naryPr>` for the operator. `MathDelimiter.toOMML()` MUST emit `<m:d>`. `MathFunction.toOMML()` MUST emit `<m:func>`. `MathLimit.toOMML()` MUST emit `<m:limLow>` or `<m:limUpp>`. `MathMatrix.toOMML()` MUST emit `<m:m>`.

#### Scenario: MathNary for summation with bounds

- **WHEN** a `MathNary(operator: .sum, subscript: [MathRun(text: "i=1")], superscript: [MathRun(text: "n")], base: [MathRun(text: "i")]).toOMML()` is called
- **THEN** the output contains `<m:nary>`, `<m:chr m:val="∑"/>`, and the sub/sup/base content

### Requirement: TextReplacementEngine uses flatten-then-map algorithm

The `ooxml-swift` package SHALL provide a `TextReplacementEngine` that, given a `Paragraph` and a `find` string, flattens `paragraph.runs` into a single string with an offset map (character index → (runIndex, charIndex in run)), locates matches on the flattened string, and reconstructs `paragraph.runs` preserving run-level formatting at the splice boundaries. Matches that cross run boundaries MUST succeed. The replacement text MUST inherit the formatting of the starting run.

#### Scenario: Cross-run match succeeds when earlier implementation failed

- **WHEN** a paragraph has runs `["均值方程式：", "", "r_t = ..."]` (three separate runs) and `replace(find: "均值方程式：r_t", with: "Mean: r_t")` is called
- **THEN** the replacement is applied across run boundaries and the result paragraph contains exactly one replacement

#### Scenario: Replacement inherits start-run formatting

- **WHEN** a paragraph has bold run `["old"]` followed by italic run `[" word"]` and `replace(find: "old word", with: "new")` is called
- **THEN** the resulting run containing `"new"` carries the bold formatting from the start run

### Requirement: TextReplacementEngine supports scope and regex options

The `ooxml-swift` package SHALL provide a `ReplaceOptions` struct exposing `scope: ReplaceScope` (enum with cases `.bodyAndTables` and `.all`) and `regex: Bool`. When `scope = .all`, replacements MUST additionally traverse headers, footers, footnotes, and endnotes. When `regex = true`, the `find` string MUST be interpreted as an `NSRegularExpression` pattern (ICU flavor).

#### Scenario: Replace with all scope covers header and footer

- **WHEN** a document has text "Draft" in the body, header, and footer and `replaceText(find: "Draft", with: "Final", options: ReplaceOptions(scope: .all))` is called
- **THEN** all three occurrences are replaced and the returned count equals 3

#### Scenario: Replace with regex supports capture groups

- **WHEN** `replaceText(find: "Chapter (\\d+)", with: "Ch. $1", options: ReplaceOptions(regex: true))` is called on a document containing "Chapter 4"
- **THEN** the result contains "Ch. 4"

### Requirement: Document.replaceText scope .all traverses all text containers

The `ooxml-swift` package's `Document.replaceText(find:with:options:)` method SHALL iterate body paragraphs, table cell paragraphs, header paragraphs (from `document.headers`), footer paragraphs (from `document.footers`), footnote paragraphs (from `document.footnotes`), and endnote paragraphs (from `document.endnotes`) when `options.scope == .all`. Each container MUST apply the flatten-then-map algorithm independently.

#### Scenario: Footnote replacement under scope .all

- **WHEN** a document has a footnote containing "see ref 1" and `replaceText(find: "ref 1", with: "reference 1", options: ReplaceOptions(scope: .all))` is called
- **THEN** the footnote content is updated and the returned count is at least 1

### Requirement: ImageDimensions detects PNG and JPEG native dimensions

The `ooxml-swift` package SHALL provide `ImageDimensions.detect(path:) throws -> ImageDimensions` that reads the native pixel width and height from PNG (via IHDR chunk at bytes 16-23) and JPEG (via SOF0/SOF2 segment scanning). The struct MUST expose `widthPx: Int`, `heightPx: Int`, and `aspectRatio: Double` (computed). For unsupported formats, the function MUST throw `ImageDimensionsError.unsupportedFormat(ext: String)`.

#### Scenario: Detect PNG dimensions from IHDR

- **WHEN** `ImageDimensions.detect(path: "test.png")` is called on a file whose PNG IHDR declares 800×600
- **THEN** the returned struct has `widthPx == 800`, `heightPx == 600`, `aspectRatio == 800.0/600.0`

#### Scenario: Unsupported format throws

- **WHEN** `ImageDimensions.detect(path: "test.tiff")` is called
- **THEN** the function throws `ImageDimensionsError.unsupportedFormat(ext: "tiff")`

### Requirement: InsertLocation enum covers four anchor types

The `ooxml-swift` package SHALL provide an `InsertLocation` enum with exactly these cases: `.paragraphIndex(Int)`, `.afterImageId(String)`, `.afterTableIndex(Int)`, and `.intoTableCell(tableIndex: Int, row: Int, col: Int)`. `Document.insertImage(at: InsertLocation, relationshipId: String, dimensions: ImageDimensions)` and `Document.insertParagraph(at: InsertLocation, paragraph: Paragraph)` SHALL accept this enum and resolve to the correct body-children index or table-cell paragraph list. An invalid location (e.g. `afterImageId` with unknown rId) MUST throw `WordError.invalidInsertLocation`.

#### Scenario: Insert image into table cell

- **WHEN** `Document.insertImage(at: .intoTableCell(tableIndex: 0, row: 1, col: 2), relationshipId: "rId5", dimensions: ImageDimensions(widthPx: 400, heightPx: 300))` is called on a document whose first table has at least 2 rows and 3 columns
- **THEN** the image is added as a paragraph inside table[0].rows[1].cells[2].paragraphs and no body-level paragraph is inserted

#### Scenario: afterImageId with unknown id throws

- **WHEN** `Document.insertParagraph(at: .afterImageId("rId999"), paragraph: ...)` is called on a document containing no image with rId999
- **THEN** the method throws `WordError.invalidInsertLocation`
