## ADDED Requirements

### Requirement: Hyperlink mutation API SHALL round-trip on source-loaded hyperlinks

When a `Hyperlink` instance was populated by `DocxReader` and the public mutation API (`Hyperlink.text` setter, `Document.replaceInParagraphSurfaces`, `Document.updateHyperlink(text:)`) is invoked to change its content, `Hyperlink.toXML()` SHALL emit the mutated content. The writer SHALL prefer `runs` over `children` so that mutations to `runs` are observable. `children` SHALL serve only as a fallback when `runs.isEmpty`.

#### Scenario: replaceText on source-loaded hyperlink emits new text

- **WHEN** a document is loaded via `DocxReader.read(from:)`, then `document.replaceText("old", with: "new")` is invoked, and the document is saved back to XML
- **THEN** the saved XML contains a `<w:hyperlink>` whose run text is "new"
- **AND** the saved XML does NOT contain "old" inside any `<w:hyperlink>` element

##### Example: round-trip after replace_text mutation

- **GIVEN** source XML `<w:p><w:hyperlink r:id="rId1"><w:r><w:t>old</w:t></w:r></w:hyperlink></w:p>`
- **WHEN** `document.replaceText("old", with: "new")` is called and the document is re-emitted
- **THEN** the emitted XML for that paragraph contains `<w:r><w:t>new</w:t></w:r>` inside the `<w:hyperlink>` and contains no occurrence of `>old<` inside the hyperlink

#### Scenario: updateHyperlink text setter on source-loaded hyperlink emits new text

- **WHEN** a document is loaded via `DocxReader.read(from:)`, the hyperlink at a known position is updated via `document.updateHyperlink(id: "rId1@0", text: "Updated")`, and the document is saved
- **THEN** the saved XML contains `<w:r><w:t>Updated</w:t></w:r>` inside the corresponding `<w:hyperlink>` element

### Requirement: insertComment SHALL emit anchor markers on paragraphs that already have source-loaded comment markers

When `Document.insertComment` is invoked on a paragraph whose `commentRangeMarkers` array is non-empty (because the paragraph was loaded from a `.docx` with existing comment ranges), the new comment SHALL produce matching `<w:commentRangeStart>`, `<w:commentRangeEnd>`, and `<w:commentReference>` raw markers in the paragraph alongside the new `commentId`. The `commentRangeMarkers.isEmpty` guard introduced for double-emit avoidance in the bookmark-syncing path SHALL NOT prevent emission of markers for newly-added commentIds.

#### Scenario: insertComment on source paragraph with existing comments emits new anchors

- **GIVEN** a paragraph parsed from source XML that contains a `<w:commentRangeStart w:id="3"/>` and `<w:commentRangeEnd w:id="3"/>` pair
- **WHEN** `document.insertComment(text: "new note", paragraphIndex: i)` is invoked on that paragraph and the document is re-emitted
- **THEN** the paragraph XML contains BOTH the original id=3 markers AND new `<w:commentRangeStart>` / `<w:commentRangeEnd>` / `<w:commentReference>` markers for the new commentId

##### Example: comment ID 3 preserved, new ID 4 added

- **GIVEN** source paragraph XML `<w:p><w:commentRangeStart w:id="3"/><w:r><w:t>text</w:t></w:r><w:commentRangeEnd w:id="3"/><w:r><w:commentReference w:id="3"/></w:r></w:p>`
- **WHEN** `insertComment(text: "second", paragraphIndex: 0)` runs and produces commentId 4
- **THEN** the re-emitted XML contains both `<w:commentRangeStart w:id="3"/>` and `<w:commentRangeStart w:id="4"/>` (and matching End / Reference for both ids)

### Requirement: Direct-emit XML attribute values SHALL be escaped to prevent injection

Any `RunProperties` or `ParagraphProperties` field whose value is interpolated directly into an XML attribute via Swift string interpolation SHALL be passed through an XML attribute escape function before emission. The escape function SHALL replace `&`, `<`, `>`, `"`, and `'` with the corresponding XML entities (`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&#39;`). The set of fields covered SHALL include at minimum `rStyle`. The `rStyle` fix SHALL be paired with an audit of `color`, `fontName`, `fontSize`, and other direct-emit attribute sites; each audited site SHALL either route through the escape function or be documented (in test commentary) as escape-safe by construction.

#### Scenario: rStyle value with embedded quote round-trips without injection

- **GIVEN** a `RunProperties` with `rStyle == "x\"/><injected/><w:dummy w:val=\"y"`
- **WHEN** the run is emitted via `toXML()` and the resulting XML is re-parsed
- **THEN** the parsed `<w:rStyle>` element has exactly one attribute `w:val` whose value equals the original `rStyle` string
- **AND** the parsed XML contains no `<injected>` element and no `<w:dummy>` element

##### Example: escape table

| Input rStyle | Emitted attribute fragment | Notes |
| --- | --- | --- |
| `Heading1` | `w:val="Heading1"` | normal case, no escape needed |
| `x"/><inj/>` | `w:val="x&quot;/&gt;&lt;inj/&gt;"` | injection attempt sanitized |
| `A & B` | `w:val="A &amp; B"` | ampersand escaped |
| `O'Connor` | `w:val="O&#39;Connor"` | apostrophe escaped |
