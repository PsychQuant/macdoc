## ADDED Requirements

### Requirement: writeFontTable in overlay mode is skip-by-default to preserve original font declarations

The `ooxml-swift` `DocxWriter.writeFontTable(to:)` SHALL be invoked in overlay mode ONLY when `WordDocument.modifiedParts.contains("word/fontTable.xml") == true`. When the typed model has not marked `fontTable.xml` dirty, the writer SHALL NOT touch the file at `archiveTempDir/word/fontTable.xml`, preserving the original 13-font (or arbitrary-N-font) declaration intact. In scratch mode (no preserved archive), `writeFontTable(to:)` continues writing the hardcoded 3-font default — existing behavior.

#### Scenario: Overlay mode no-op preserves original 13 fonts

- **WHEN** `var doc = try DocxReader.read(from: srcWith13Fonts)` followed by `try DocxWriter.write(doc, to: dest)` runs (zero edits)
- **THEN** `dest`'s extracted `word/fontTable.xml` is byte-equal to `src`'s extracted `word/fontTable.xml`
- **AND** all 13 font entries (including `DFKai-SB`, `華康中楷體`, `PMingLiU`, `Microsoft JhengHei`, `Cambria Math`, etc.) are preserved

#### Scenario: Scratch mode writes hardcoded 3 fonts

- **WHEN** `let doc = WordDocument()` followed by `try DocxWriter.write(doc, to: dest)` runs (initializer-built doc has no archiveTempDir)
- **THEN** `dest`'s `word/fontTable.xml` contains exactly the 3 hardcoded fonts (Calibri, Times New Roman, Calibri Light) — existing scratch-mode behavior unchanged

### Requirement: writeStyles in overlay mode is skip-by-default to preserve theme font references

The `ooxml-swift` `DocxWriter.writeStyles(_, to:)` SHALL be invoked in overlay mode ONLY when `WordDocument.modifiedParts.contains("word/styles.xml") == true`. When typed model has not marked styles dirty, the original `archiveTempDir/word/styles.xml` (containing `rFonts w:eastAsiaTheme="minorEastAsia"` references and other theme-bound styles) is preserved untouched. Scratch mode unchanged.

#### Scenario: Overlay mode no-op preserves theme-bound styles

- **WHEN** a Reader-loaded document with `<w:rFonts w:eastAsia="華康中楷體"/>` in styles.xml is round-tripped without modification
- **THEN** `dest`'s `word/styles.xml` byte-equals `src`'s `word/styles.xml`
- **AND** the `rFonts` reference to `華康中楷體` is preserved

### Requirement: writeHeader and writeFooter in overlay mode are per-instance dirty-checked

`DocxWriter.writeAllParts` SHALL iterate `document.headers` and `document.footers` in overlay mode but skip the writer call for any header/footer whose `fileName` is NOT in `modifiedParts`. Each header/footer is checked independently — modifying header3.xml SHALL NOT cause headers 1, 2, 4, 5, 6 to be re-emitted.

#### Scenario: Modifying one header preserves others byte-for-byte

- **WHEN** `doc.updateHeader(header_id: "rId10", text: "New header 3")` (which has `fileName == "header3.xml"`) followed by save
- **THEN** `dest`'s `word/header3.xml` reflects the new text
- **AND** `dest`'s `word/header1.xml`, `word/header2.xml`, `word/header4.xml`, `word/header5.xml`, `word/header6.xml` byte-equal source

### Requirement: ContentTypesOverlay handles new typed parts via hasNewTypedParts trigger

`DocxWriter.writeContentTypes(to:, document:, overlayMode: true)` SHALL re-emit `[Content_Types].xml` either when (a) `modifiedParts.contains("[Content_Types].xml")`, OR (b) the typed model contains parts whose PartName paths are NOT present in the original `[Content_Types].xml` (e.g., `insert_image_from_path` added `media/imageNew.png` but original `[Content_Types].xml` doesn't have an Override or Default for it). Helper function `hasNewTypedParts(document)` SHALL implement check (b) by computing the symmetric difference between typed-model PartNames and original Override PartNames. When neither condition is true, `writeContentTypes` is skipped — original `[Content_Types].xml` byte-equal preserved.

#### Scenario: No-op round-trip skips writeContentTypes

- **WHEN** Reader-loaded document is saved without modifications
- **THEN** `writeContentTypes` is NOT called in overlay mode
- **AND** `dest`'s `[Content_Types].xml` byte-equals source

#### Scenario: insert_image triggers Content_Types refresh

- **WHEN** typed model adds a new image entry whose path is NOT in original Content_Types Overrides, and save is called
- **THEN** `writeContentTypes` IS called via overlay merge
- **AND** `dest`'s `[Content_Types].xml` contains the new image's Override entry plus all original Overrides preserved
