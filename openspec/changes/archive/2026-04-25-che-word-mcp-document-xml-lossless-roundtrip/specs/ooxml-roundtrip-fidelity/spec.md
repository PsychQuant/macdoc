## ADDED Requirements

### Requirement: WordDocument preserves <w:document> root element attributes byte-equivalent across no-op round-trip

The `WordDocument` model SHALL expose a public field `documentRootAttributes: [String: String]` capturing every attribute (including all `xmlns:*` namespace declarations and `mc:Ignorable`) found on the source `<w:document>` root element. `DocxReader.read(from:)` SHALL populate this field from the parsed source document. `DocxWriter.writeDocument(_:to:)` SHALL emit the root open tag using these captured attributes verbatim, in the order they were collected.

When `documentRootAttributes` is empty (e.g., for documents constructed via initializers without a source ZIP), the Writer SHALL fall back to emitting only `xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"` and `xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"` — preserving create-from-scratch behavior unchanged.

#### Scenario: 34-namespace document round-trips byte-equivalent root

- **GIVEN** a source `.docx` whose `<w:document>` root declares 34 `xmlns:*` attributes (`w`, `r`, `a`, `m`, `v`, `o`, `mc`, `wp`, `wpg`, `wps`, `w10`, `w14`, `w15`, `w16`, `w16cex`, `w16cid`, `w16du`, `w16sdtdh`, `w16sdtfl`, `w16se`, `wne`, `wpc`, `wpi`, `cx`, `cx1`–`cx8`, `aink`, `am3d`, `oel`) plus `mc:Ignorable="w14 w15 w16se w16cid"`
- **WHEN** the document is loaded via `DocxReader.read(from:)` and saved via `DocxWriter.write(_:to:)` with no body mutations
- **THEN** the resulting `word/document.xml` root open tag contains all 34 `xmlns:*` declarations and the `mc:Ignorable` attribute, byte-equivalent to the source
- **AND** `xmllint --noout` parses the output cleanly (no "unbound prefix" errors)

#### Scenario: Create-from-scratch document emits minimal namespace set

- **GIVEN** a `WordDocument` constructed via `WordDocument()` initializer (no source ZIP)
- **WHEN** the document is saved via `DocxWriter.write(_:to:)`
- **THEN** the resulting `word/document.xml` root open tag declares exactly `xmlns:w` and `xmlns:r` (no other namespaces)

### Requirement: Bookmark elements round-trip lossless across no-op save

`DocxReader` SHALL parse `<w:bookmarkStart w:id="..." w:name="..."/>` and `<w:bookmarkEnd w:id="..."/>` elements found as direct children of `<w:p>` and populate `Paragraph.bookmarks` with `Bookmark` instances and the appropriate range markers via the schema-coverage capability. After `DocxWriter.write(_:to:)` emits the paragraph, every source bookmark SHALL appear in the output XML with its original `w:id`, `w:name`, and source-document position preserved.

#### Scenario: 45-bookmark thesis preserves all bookmarks across no-op save

- **GIVEN** a source `.docx` containing 45 `<w:bookmarkStart>` / `<w:bookmarkEnd>` pairs (typical academic thesis cross-reference structure)
- **WHEN** the document is loaded via `DocxReader.read(from:)` and saved via `DocxWriter.write(_:to:)` with no body mutations
- **THEN** the output `word/document.xml` contains 45 `<w:bookmarkStart>` elements with the original `w:id` + `w:name` attributes
- **AND** the output contains 45 `<w:bookmarkEnd>` elements with the original `w:id` attributes
- **AND** every `<w:hyperlink w:anchor="...">` reference in the document still resolves to a bookmark name present in the document

### Requirement: Structural wrapper elements round-trip lossless across no-op save

`DocxReader` SHALL parse the following `<w:p>` child wrappers and populate the corresponding `Paragraph` parallel arrays:
- `<w:hyperlink>` → `Paragraph.hyperlinks: [Hyperlink]` with `runs: [Run]` populated from inner `<w:r>` children, plus `relationshipId` (when `r:id` attribute present), `anchor` (when `w:anchor` attribute present), and `rawAttributes` / `rawChildren` for any unrecognized attributes/elements.
- `<w:fldSimple>` → `Paragraph.fieldSimples: [FieldSimple]` with `instr: String` from the `w:instr` attribute, `runs: [Run]` from inner `<w:r>` children, and `rawAttributes` for any unrecognized attributes.
- `<mc:AlternateContent>` → `Paragraph.alternateContents: [AlternateContent]` with `rawXML: String` (verbatim source XML) and `fallbackRuns: [Run]` extracted from inner `<mc:Fallback>` `<w:r>` children for tool-mediated edit access.

After `DocxWriter.write(_:to:)` emits the paragraph, every source wrapper SHALL appear in the output XML with its original attributes and inner content preserved.

#### Scenario: Hyperlink with cross-reference text round-trips with anchor and inner text

- **GIVEN** a source paragraph containing `<w:hyperlink w:anchor="tab:foo"><w:r><w:t>[tab:foo]</w:t></w:r></w:hyperlink>`
- **WHEN** the document is loaded and saved with no mutations
- **THEN** the output paragraph contains `<w:hyperlink w:anchor="tab:foo">` with an inner `<w:r>` whose `<w:t>` text is exactly `[tab:foo]`

#### Scenario: SEQ Table caption fldSimple preserves instr and result text

- **GIVEN** a source paragraph containing `<w:fldSimple w:instr=" SEQ Table \* ARABIC "><w:r><w:t>1</w:t></w:r></w:fldSimple>`
- **WHEN** the document is loaded and saved with no mutations
- **THEN** the output paragraph contains a `<w:fldSimple>` with `w:instr=" SEQ Table \* ARABIC "` (whitespace preserved) and an inner `<w:r>` whose `<w:t>` text is exactly `1`

#### Scenario: AlternateContent math block preserves verbatim XML and exposes fallback runs

- **GIVEN** a source paragraph containing `<mc:AlternateContent><mc:Choice Requires="wps14"><w:drawing>...</w:drawing></mc:Choice><mc:Fallback><w:r><w:t>Pearson (Spearman)</w:t></w:r></mc:Fallback></mc:AlternateContent>`
- **WHEN** the document is loaded
- **THEN** `Paragraph.alternateContents` contains one entry whose `rawXML` is the byte-identical source XML
- **AND** the entry's `fallbackRuns` contains one Run with text `Pearson (Spearman)`
- **WHEN** the document is saved with no mutations
- **THEN** the output paragraph contains the original `<mc:AlternateContent>` block byte-equivalent to source

### Requirement: Tool-mediated edits inside structural wrappers SHALL apply (no silent failure)

When an MCP tool that walks `Paragraph.runs` (such as `replace_text`, `format_text`, `update_paragraph`) targets text content located inside a structural wrapper (`Hyperlink`, `FieldSimple`, or `AlternateContent.fallbackRuns`), the tool SHALL find and modify the targeted content. The wrapper's typed `runs` (or `fallbackRuns`) field SHALL be the editable surface; modifications SHALL persist through the next `save_document` call.

For `AlternateContent` specifically: edits applied to `fallbackRuns` SHALL affect the saved `<mc:Fallback>` content. The `<mc:Choice>` content remains preserved verbatim from `rawXML` (Word reconciles divergence per its own rules — out of scope for this requirement).

#### Scenario: replace_text finds and replaces text inside hyperlink

- **GIVEN** a paragraph containing a hyperlink whose runs include text `[tab:foo]`
- **WHEN** `replace_text` is called with `find: "[tab:foo]"` and `replace: "Table 1"`
- **THEN** the hyperlink's `runs` reflect the replacement (text now `Table 1`)
- **AND** after `save_document`, the saved `word/document.xml` contains `<w:hyperlink>` with inner `<w:r><w:t>Table 1</w:t></w:r>`
- **AND** the hyperlink's `w:anchor` attribute is preserved unchanged

#### Scenario: format_text bolds run inside fldSimple SEQ caption

- **GIVEN** a paragraph containing `<w:fldSimple w:instr=" SEQ Table \* ARABIC ">` with one inner Run at `runs[0]`
- **WHEN** `format_text` is called with `paragraph_index` matching the paragraph and `run_index: 0` and `bold: true`
- **THEN** the FieldSimple's `runs[0]` properties reflect `bold: true`
- **AND** after `save_document`, the saved XML emits the run with `<w:rPr><w:b/></w:rPr>` inside the `<w:fldSimple>` block
- **AND** the `w:instr` attribute is preserved

### Requirement: Real-world docx round-trip smoke test validates end-to-end lossless guarantee

A test suite (`RealWorldDocxRoundTripSmokeTests` in `mcp/che-word-mcp/Tests/CheWordMCPTests/`) SHALL iterate over every `.docx` file in `mcp/che-word-mcp/test-files/` (gitignored, populated by developers locally), and for each file SHALL:

1. Load the file via `open_document`.
2. Call `save_document` with no mutations.
3. Reload the saved file.
4. Assert: `xmllint --noout` parses the saved file's `word/document.xml` cleanly (no "unbound prefix" errors).
5. Assert: source bookmark count equals saved bookmark count.
6. Assert: source `<w:hyperlink>` count equals saved `<w:hyperlink>` count.
7. Assert: source `<w:fldSimple>` count equals saved `<w:fldSimple>` count.
8. Assert: source `<mc:AlternateContent>` count equals saved `<mc:AlternateContent>` count.
9. Assert: SHA256 of the concatenated `<w:t>` text content of source equals SHA256 of saved (modulo any whitespace normalization explicitly documented).

When `mcp/che-word-mcp/test-files/` is empty or absent, the test SHALL `XCTSkip` with a message indicating no fixtures are available (mirrors the existing `.note` smoke test pattern from issue #81).

#### Scenario: NTPU master's thesis passes all 9 round-trip assertions

- **GIVEN** the NTPU master's thesis fixture (`20260401-臺北大學-統研所-郭嘉員-碩士論文.docx`, 169 KB, 42 OOXML parts, 45 bookmarks, 13 fonts including DFKai-SB, 6 headers with VML watermarks, 4 footers, 354+ `<w:t>` nodes) is present in `mcp/che-word-mcp/test-files/`
- **WHEN** `RealWorldDocxRoundTripSmokeTests` runs
- **THEN** all 9 assertions pass for this fixture
- **AND** the test reports completion in under 5 seconds

#### Scenario: Empty test-files directory triggers XCTSkip

- **GIVEN** `mcp/che-word-mcp/test-files/` is absent or contains no `.docx` files
- **WHEN** `RealWorldDocxRoundTripSmokeTests` runs
- **THEN** the test exits with `XCTSkip` and a message indicating fixture absence
- **AND** no assertions execute, no failures are reported
