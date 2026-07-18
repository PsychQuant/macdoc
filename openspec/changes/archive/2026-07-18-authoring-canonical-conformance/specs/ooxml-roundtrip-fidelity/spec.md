## MODIFIED Requirements

### Requirement: WordDocument preserves <w:document> root element attributes byte-equivalent across no-op round-trip

The `WordDocument` model SHALL expose a public field `documentRootAttributes: [String: String]` capturing every attribute (including all `xmlns:*` namespace declarations and `mc:Ignorable`) found on the source `<w:document>` root element. `DocxReader.read(from:)` SHALL populate this field from the parsed source document. `DocxWriter.writeDocument(_:to:)` SHALL emit the root open tag using these captured attributes verbatim, in the order they were collected.

When `documentRootAttributes` is empty (e.g., for documents constructed via initializers without a source ZIP), the Writer SHALL fall back to emitting the full Word-canonical namespace cloud — every `xmlns:*` declaration plus `mc:Ignorable`, values and attribute order captured verbatim from the real-Word baseline fixture (`90_template_ja.docx`) — so create-from-scratch documents carry the same root a current Word build writes. This supersedes the previous minimal `xmlns:w` + `xmlns:r` fallback: emitting `w14:paraId` on authored paragraphs requires the `w14` declaration, and the full cloud was chosen over a minimal-valid set for Word-imitation fidelity (change authoring-canonical-conformance, design D4).

#### Scenario: 34-namespace document round-trips byte-equivalent root

- **GIVEN** a source `.docx` whose `<w:document>` root declares 34 `xmlns:*` attributes (`w`, `r`, `a`, `m`, `v`, `o`, `mc`, `wp`, `wpg`, `wps`, `w10`, `w14`, `w15`, `w16`, `w16cex`, `w16cid`, `w16du`, `w16sdtdh`, `w16sdtfl`, `w16se`, `wne`, `wpc`, `wpi`, `cx`, `cx1`–`cx8`, `aink`, `am3d`, `oel`) plus `mc:Ignorable="w14 w15 w16se w16cid"`
- **WHEN** the document is loaded via `DocxReader.read(from:)` and saved via `DocxWriter.write(_:to:)` with no body mutations
- **THEN** the resulting `word/document.xml` root open tag contains all 34 `xmlns:*` declarations and the `mc:Ignorable` attribute, byte-equivalent to the source
- **AND** `xmllint --noout` parses the output cleanly (no "unbound prefix" errors)

#### Scenario: Create-from-scratch document emits the full Word-canonical cloud

- **GIVEN** a `WordDocument` constructed via `WordDocument()` initializer (no source ZIP)
- **WHEN** the document is saved via `DocxWriter.write(_:to:)`
- **THEN** the resulting `word/document.xml` root open tag equals the real-Word baseline fixture's root open tag byte-for-byte (every `xmlns:*` declaration plus `mc:Ignorable`, order preserved)
