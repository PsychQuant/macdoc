## ADDED Requirements

### Requirement: WordDocument exposes style inheritance traversal

The `WordDocument` model SHALL expose a `getStyleInheritanceChain(styleId: String) -> [Style]` method that returns the ordered chain from the queried style upward through `basedOn` references to the root style.

If the queried style does not exist, the method SHALL return an empty array.

If the chain contains a cycle (one style's basedOn references another that references back to the original), the method SHALL stop traversal at the first revisited style and return the chain prefix; callers MAY detect cycle via the chain length being shorter than expected.

#### Scenario: Linear inheritance chain

- **GIVEN** a document with styles `Normal` (no basedOn), `Heading 1` (basedOn=`Normal`), `Heading 1 Bold` (basedOn=`Heading 1`)
- **WHEN** `getStyleInheritanceChain(styleId: "Heading 1 Bold")` is called
- **THEN** the result is `[Heading 1 Bold, Heading 1, Normal]` in that order

#### Scenario: Missing style returns empty

- **WHEN** `getStyleInheritanceChain(styleId: "Nonexistent")` is called
- **THEN** the result is `[]`

### Requirement: WordDocument exposes style linking and naming

The `WordDocument` model SHALL expose `linkStyles(paragraphStyleId: String, characterStyleId: String) throws` which sets `<w:link w:val="characterStyleId"/>` on the paragraph style and `<w:link w:val="paragraphStyleId"/>` on the character style.

The model SHALL expose `addStyleNameAlias(styleId: String, lang: String, name: String) throws` which appends a localized `<w:name>` entry to the target style's `<w:name>` family.

Both methods SHALL throw `WordError.styleNotFound(styleId)` when the target style does not exist.

Both methods SHALL mark `word/styles.xml` dirty by calling `modifiedParts.insert("word/styles.xml")`.

#### Scenario: Link paragraph and character styles

- **GIVEN** a document with paragraph style `Heading 1` and character style `Heading 1 Char`
- **WHEN** `linkStyles(paragraphStyleId: "Heading1", characterStyleId: "Heading1Char")` is called
- **THEN** `Heading 1` style XML contains `<w:link w:val="Heading1Char"/>`
- **AND** `Heading 1 Char` style XML contains `<w:link w:val="Heading1"/>`

### Requirement: WordDocument exposes latentStyles management

The `WordDocument` model SHALL include a `latentStyles: [LatentStyle]` collection populated by the reader from `<w:latentStyles>` in styles.xml.

The model SHALL expose `setLatentStyles(_ styles: [LatentStyle])` which replaces the collection wholesale and marks `word/styles.xml` dirty.

The `LatentStyle` struct SHALL contain: `name: String`, `uiPriority: Int?`, `semiHidden: Bool`, `unhideWhenUsed: Bool`, `qFormat: Bool`.

#### Scenario: Set latentStyles persists in styles.xml

- **GIVEN** a document with empty `latentStyles`
- **WHEN** `setLatentStyles([LatentStyle(name: "Heading 9", uiPriority: 9, semiHidden: true, unhideWhenUsed: false, qFormat: false)])` is called
- **AND** the document is saved and re-read
- **THEN** the re-read document's `latentStyles` contains one entry with name="Heading 9"

### Requirement: WordDocument exposes numbering definition lifecycle

The `WordDocument` model SHALL expose:

- `createNumberingDefinition(levels: [Level]) -> Int` — creates a new `<w:abstractNum>` and a paired `<w:num>`, returns the new numId.
- `overrideNumberingLevel(numId: Int, level: Int, startValue: Int) throws` — adds `<w:lvlOverride w:ilvl="level"><w:startOverride w:val="startValue"/></w:lvlOverride>` to the target `<w:num>`.
- `assignNumberingToParagraph(paragraphIndex: Int, numId: Int, level: Int) throws` — adds `<w:pPr><w:numPr><w:numId w:val="numId"/><w:ilvl w:val="level"/></w:numPr></w:pPr>` to the target paragraph.
- `gcOrphanNumbering() -> [Int]` — scans every paragraph's `<w:numId>` references, deletes any `<w:num>` from numbering.xml whose numId is not referenced anywhere, returns the deleted numIds in order.

The first three methods SHALL mark `word/numbering.xml` dirty (and additionally `word/document.xml` for `assignNumberingToParagraph`).

`createNumberingDefinition` SHALL throw `WordError.invalidIndex(0)` if `levels` is empty or `WordError.invalidIndex(levels.count)` if `levels.count > 9` (Word supports max 9 levels).

`overrideNumberingLevel` and `assignNumberingToParagraph` SHALL throw `WordError.numIdNotFound(numId)` when the target numId does not exist.

#### Scenario: GC removes orphan numIds

- **GIVEN** a document with numIds `[1, 2, 3]` in numbering.xml, where only numId `1` is referenced by any paragraph
- **WHEN** `gcOrphanNumbering()` is called
- **THEN** the return value is `[2, 3]` in numId order
- **AND** numbering.xml now contains only numId `1`
- **AND** `word/numbering.xml` is marked dirty

#### Scenario: createNumberingDefinition rejects empty levels

- **WHEN** `createNumberingDefinition(levels: [])` is called
- **THEN** the method throws `WordError.invalidIndex(0)`

### Requirement: WordDocument exposes section property extensions

The `WordDocument` model SHALL expose:

- `setSectionLineNumbers(sectionIndex: Int, countBy: Int, start: Int?, restart: LineNumberRestart) throws` — emits `<w:lnNumType w:countBy="..." w:start="..." w:restart="..."/>` in the target sectPr.
- `setSectionVerticalAlignment(sectionIndex: Int, alignment: VerticalAlignment) throws` — emits `<w:vAlign w:val="..."/>`.
- `setSectionPageNumberFormat(sectionIndex: Int, start: Int?, format: PageNumberFormat) throws` — emits `<w:pgNumType w:start="..." w:fmt="..."/>`.
- `setSectionBreakType(sectionIndex: Int, type: SectionBreakType) throws` — emits `<w:type w:val="..."/>`.
- `setTitlePageDistinct(sectionIndex: Int, enabled: Bool) throws` — emits or removes `<w:titlePg/>`.
- `getAllSections() -> [SectionInfo]` — returns one entry per section in document order with sectionIndex, paragraph range, and sectPr summary.

All mutating methods SHALL mark `word/document.xml` dirty (sectPr lives inside document.xml, not its own part).

All mutating methods SHALL throw `WordError.invalidIndex(sectionIndex)` when the section index is out of bounds.

The new types SHALL include: `LineNumberRestart` enum (`continuous` / `newSection` / `newPage`), `VerticalAlignment` enum (`top` / `center` / `bottom` / `both`), `PageNumberFormat` enum (`decimal` / `lowerRoman` / `upperRoman` / `lowerLetter` / `upperLetter`).

#### Scenario: Set section vertical alignment to center

- **GIVEN** a document with one section
- **WHEN** `setSectionVerticalAlignment(sectionIndex: 0, alignment: .center)` is called
- **THEN** the section's sectPr XML contains `<w:vAlign w:val="center"/>`
- **AND** `word/document.xml` is marked dirty

#### Scenario: Set Roman numeral page numbers on section 0

- **GIVEN** a document with one section
- **WHEN** `setSectionPageNumberFormat(sectionIndex: 0, start: 1, format: .lowerRoman)` is called
- **THEN** the section's sectPr XML contains `<w:pgNumType w:start="1" w:fmt="lowerRoman"/>`

