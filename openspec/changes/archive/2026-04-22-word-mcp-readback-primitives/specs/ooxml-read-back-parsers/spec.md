## ADDED Requirements

### Requirement: FieldParser parses fldChar regions in a Paragraph into typed ParsedField values

The `ooxml-swift` package SHALL provide a `FieldParser` type that accepts a `Paragraph` and returns `[ParsedField]`. Each `ParsedField` SHALL carry `{ startRunIdx: Int, endRunIdx: Int, cachedResultRunIdx: Int?, instrText: String, field: ParsedFieldValue }` where `ParsedFieldValue` is an enum with cases for each recognized `FieldCode`-conforming type plus a `.unknown(instrText: String)` fallback. The parser SHALL recognize field spans by the five-run `<w:fldChar fldCharType="begin">` → `<w:instrText>` → `<w:fldChar fldCharType="separate">` → `<w:t>` → `<w:fldChar fldCharType="end">` pattern inside `Run.rawXML` strings.

#### Scenario: SequenceField SEQ round-trips through parse

- **WHEN** a Paragraph is built containing a `SequenceField(identifier: "Figure", format: .arabic, resetLevel: 1, cachedResult: "3").toFieldXML()` as a Run's rawXML, and `FieldParser.parse(paragraph:)` is called on it
- **THEN** the result contains exactly one `ParsedField` with `field == .sequence(SequenceField)` whose `identifier == "Figure"`, `format == .arabic`, `resetLevel == 1`

#### Scenario: Unknown field type preserved as opaque case

- **WHEN** a Paragraph contains a raw `<w:fldChar begin/><w:instrText> TIME \@ "hh:mm" </w:instrText><w:fldChar separate/><w:t>12:34</w:t><w:fldChar end/>` sequence that FieldParser does not recognize
- **THEN** the result contains one `ParsedField` with `field == .unknown(instrText: " TIME \\@ \"hh:mm\" ")` and the `startRunIdx`/`endRunIdx` correctly pointing at the enclosing runs

#### Scenario: Cross-run field span tracked with correct indices

- **WHEN** a Paragraph has `<w:fldChar begin/>` in run index 2, `<w:instrText>` split across runs 3 and 4, `<w:fldChar separate/>` in run 5, `<w:t>cached</w:t>` in run 6, `<w:fldChar end/>` in run 7
- **THEN** the returned `ParsedField` has `startRunIdx == 2`, `endRunIdx == 7`, `cachedResultRunIdx == 6`

### Requirement: FieldCode conforming types provide static parse(instrText:) for round-trip

The `ooxml-swift` package SHALL add a `static func parse(instrText: String) -> Self?` method to the `FieldCode` protocol's existing conforming types (`SequenceField`, `StyleRefField`, `ReferenceField`, `IFField`, `CalculationField`, `DateTimeField`, `DocumentInfoField`, `MergeField`). Each implementation SHALL return a parsed value when the `instrText` matches that field type's grammar and `nil` otherwise. `FieldParser` SHALL dispatch by trying each registered type in order until one returns non-nil.

#### Scenario: SequenceField.parse recognizes SEQ grammar

- **WHEN** `SequenceField.parse(instrText: " SEQ Figure \\* ARABIC \\s 1 ")` is called
- **THEN** the result is `SequenceField(identifier: "Figure", format: .arabic, resetLevel: 1)`

#### Scenario: SequenceField.parse returns nil on non-SEQ grammar

- **WHEN** `SequenceField.parse(instrText: " STYLEREF 1 \\s ")` is called
- **THEN** the result is `nil`

#### Scenario: StyleRefField.parse recognizes STYLEREF grammar

- **WHEN** `StyleRefField.parse(instrText: " STYLEREF 1 \\s ")` is called
- **THEN** the result is `StyleRefField(headingLevel: 1, suppressNonDelimiter: true)`

### Requirement: OMMLParser parses m:oMath XML into a MathComponent AST

The `ooxml-swift` package SHALL provide an `OMMLParser` type that accepts an `<m:oMath>` XML string (with or without `<m:oMathPara>` wrapper) and returns `[MathComponent]`. The parser SHALL handle the nine existing `MathComponent` types (`MathRun`, `MathFraction`, `MathSubSuperScript`, `MathRadical`, `MathNary`, `MathDelimiter`, `MathFunction`, `MathLimit`, `MathMatrix`). Unrecognized `<m:...>` subtrees SHALL be preserved as `MathComponent.unknownXML(String)` where the payload is the exact XML substring.

#### Scenario: Round-trip MathFraction through OMMLParser

- **WHEN** a `MathFraction(numerator: [MathRun(text: "a")], denominator: [MathRun(text: "b")]).toOMML()` string (wrapped in `<m:oMath>`) is parsed by `OMMLParser.parse(xml:)`
- **THEN** the result is `[.fraction(MathFraction(numerator: [.run(MathRun(text: "a"))], denominator: [.run(MathRun(text: "b"))]))]`

#### Scenario: m:oMathPara wrapper stripped

- **WHEN** an XML string `<m:oMathPara><m:oMath><m:r><m:t>x</m:t></m:r></m:oMath></m:oMathPara>` is parsed
- **THEN** the result is `[.run(MathRun(text: "x"))]` — the `oMathPara` wrapper is stripped

#### Scenario: Nested composition (fraction inside radical) round-trips

- **WHEN** an OMML string representing `√(a/b)` — a MathRadical containing a MathFraction — is parsed
- **THEN** the result is `[.radical(MathRadical(radicand: [.fraction(MathFraction(numerator: [.run(MathRun(text: "a"))], denominator: [.run(MathRun(text: "b"))]))], degree: nil))]`

#### Scenario: Unknown m:borderBox preserved as unknownXML

- **WHEN** an OMML string containing `<m:borderBox><m:borderBoxPr>...</m:borderBoxPr><m:e>...</m:e></m:borderBox>` (not supported by any current MathComponent type) is parsed
- **THEN** the result contains a `.unknownXML` case whose payload is the exact `<m:borderBox>...</m:borderBox>` substring

### Requirement: MathComponent enum adds unknownXML opaque fallback case

The `ooxml-swift` package SHALL add an `unknownXML(String)` case to whatever representation is used for `MathComponent`-containing collections returned by `OMMLParser`. Callers SHALL NOT lose data when round-tripping documents containing math subtrees that the current parser does not recognize.

#### Scenario: unknownXML round-trips verbatim

- **WHEN** an unrecognized math subtree XML is parsed and then re-emitted via the caller's `toOMML()` equivalent logic
- **THEN** the emitted XML is byte-for-byte identical to the input `unknownXML(String)` payload

### Requirement: WordDocument.updateAllFields recomputes SEQ counters across all containers

The `ooxml-swift` package SHALL add `WordDocument.updateAllFields() -> [String: Int]` that iterates every `ParsedField` in the body, all headers, all footers, all footnotes, and all endnotes. For each `.sequence(SequenceField)` value encountered, the method SHALL maintain a per-identifier counter, incrementing on each occurrence and resetting at heading boundaries when the paired `SequenceField.resetLevel` matches the preceding STYLEREF scope. The recomputed count SHALL be written back into the field's cached-result run. The return value SHALL be a dictionary mapping each encountered SEQ identifier to its final counter value.

Non-SEQ field types (IF, CalculationField, DateTimeField, DocumentInfoField, MergeField, StyleRefField, ReferenceField) SHALL have their existing cached result preserved verbatim — they are not evaluated.

#### Scenario: Single SEQ identifier increments sequentially

- **WHEN** a document contains three captions with `SequenceField(identifier: "Figure")` fields and `updateAllFields()` is called
- **THEN** the three fields' cached result runs now contain `"1"`, `"2"`, `"3"` in document order
- **AND** the return value contains `["Figure": 3]`

#### Scenario: Distinct identifiers have independent counters

- **WHEN** a document contains interleaved `SequenceField(identifier: "Figure")` and `SequenceField(identifier: "Table")` captions (3 Figures, 2 Tables)
- **THEN** Figure fields are renumbered `"1"`, `"2"`, `"3"` and Table fields are renumbered `"1"`, `"2"` independently
- **AND** the return value is `["Figure": 3, "Table": 2]`

#### Scenario: Chapter-reset captions restart on heading level 1

- **WHEN** a document has chapter headings with `pStyle == "Heading 1"` and captions using `SequenceField(identifier: "Figure", resetLevel: 1)`, with 2 figures in chapter 1 and 3 figures in chapter 2
- **THEN** after `updateAllFields()`, the figures' cached results are `"1"`, `"2"` (chapter 1) then `"1"`, `"2"`, `"3"` (chapter 2 — restarted)
- **AND** the return value's `Figure` counter reflects the final value within the last chapter scope (`3`)

#### Scenario: Non-SEQ fields are not mutated

- **WHEN** a document contains both SEQ fields and IF / DATE / PAGE fields
- **THEN** after `updateAllFields()`, only the SEQ fields' cached results change; other fields' cached `<w:t>` values are byte-identical to before the call
