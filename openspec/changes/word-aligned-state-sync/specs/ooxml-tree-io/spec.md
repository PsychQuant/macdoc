## ADDED Requirements

### Requirement: Lossless XmlNode tree representation

The library SHALL provide an `XmlNode` type that represents every well-formed OOXML element, attribute, namespace declaration, comment, processing instruction, and text node read from a docx, with no element class or attribute key dropped during reading.

#### Scenario: All element classes preserved on read

- **WHEN** `XmlTreeReader.read(part:)` parses a docx part containing element classes outside the typed-model coverage (`<w:rsids>`, `<mc:AlternateContent>`, `<w:pict>`, `<w:hdrShapeDefaults>`, `w14:*` extensions, custom XML)
- **THEN** every such element appears as an `XmlNode` in the returned tree with original namespace prefix and attribute order

##### Example: rsids preservation

- **GIVEN** a `word/settings.xml` containing `<w:rsids><w:rsidRoot w:val="00ABC123"/><w:rsid w:val="00DEF456"/></w:rsids>` (300+ rsid entries)
- **WHEN** the part is read into the tree
- **THEN** the resulting tree contains an `XmlNode(name: "rsids", namespace: "w")` whose children are all 300+ rsid `XmlNode` instances in original order, each carrying its `w:val` attribute

#### Scenario: Namespace prefix decisions preserved

- **WHEN** the input docx declares `xmlns:w14` on the root and uses `<w14:paraId/>` deeper in the tree
- **THEN** the tree records the prefix decision so `XmlTreeWriter` re-emits the same prefix at the same position rather than re-declaring the namespace inline

### Requirement: Identity round-trip on untouched sub-trees

`XmlTreeWriter.write(_:to:)` SHALL produce byte-equal output to the original input bytes for every sub-tree the caller did not modify between the matching `XmlTreeReader.read` and `XmlTreeWriter.write` calls.

#### Scenario: No-op round-trip is byte-equal

- **WHEN** `XmlTreeWriter.write(XmlTreeReader.read(docx).tree, to: out)` runs with no mutations
- **THEN** `out` is byte-equal to the input docx for every part the reader consumed

#### Scenario: Touched sub-tree canonicalizes, untouched sub-trees stay byte-equal

- **WHEN** the caller mutates only the text of paragraph index 5 in the body
- **THEN** the serialized output's `word/document.xml` differs from input only inside the `<w:p>` containing paragraph 5; all other paragraphs, the `<w:sectPr>`, and `word/settings.xml` are byte-equal

### Requirement: Identity-noise normalization for diff comparison

The library SHALL provide an `XmlNode.normalizedFingerprint()` API that returns a comparison-stable representation excluding identity-noise attributes. Identity-noise classes covered: `w:rsidR`, `w:rsidRPr`, `w:rsidP`, `w:rsidRDefault`, `w:rsidSect`, `w:rsidTr`, namespace prefix variations on the same namespace URI, and order of attributes that the OOXML schema declares unordered.

#### Scenario: rsid-only differences fingerprint as equal

- **GIVEN** two trees identical in content but with different `w:rsidR` attribute values throughout
- **WHEN** `tree1.normalizedFingerprint() == tree2.normalizedFingerprint()` is evaluated
- **THEN** the fingerprints are equal

#### Scenario: Real content differences fingerprint as unequal

- **GIVEN** two trees identical except one has `<w:t>Hello</w:t>` and the other has `<w:t>World</w:t>`
- **WHEN** their fingerprints are compared
- **THEN** the fingerprints are unequal

### Requirement: Stable sub-tree references across reads

The library SHALL guarantee that `XmlNode` references for elements with stable OOXML IDs (`w14:paraId`, `w:bookmarkId`, `w:id` on comments, `r:id`) survive a write-then-read cycle: reading the output gives nodes whose stable IDs match the corresponding input nodes.

#### Scenario: paraId survives round-trip

- **GIVEN** an input with `<w:p w14:paraId="0AB7C123"/>`
- **WHEN** the tree is written and re-read
- **THEN** the re-read tree contains an `XmlNode` with `w14:paraId="0AB7C123"` byte-equal

### Requirement: Generic-text and mixed-content support

The `XmlNode` type SHALL represent mixed content (interleaved text and child elements) faithfully via ordered children including a dedicated text-node case.

#### Scenario: Mixed content order is preserved

- **GIVEN** input `<w:r><w:t>foo</w:t><w:tab/><w:t>bar</w:t></w:r>`
- **WHEN** the tree is read and serialized back
- **THEN** the output preserves the exact element order: `<w:t>foo</w:t>` before `<w:tab/>` before `<w:t>bar</w:t>`

### Requirement: Pure-Swift implementation

The tree IO module SHALL be implemented in pure Swift without `libxml2`, `Foundation.XMLDocument`, `SwiftSoup`, or any non-`Swift Package Manager` dependency outside the existing ooxml-swift dependency graph.

#### Scenario: No new external dependencies

- **WHEN** `swift package show-dependencies` is run on the package post-implementation
- **THEN** no new entries appear beyond what was present before this change

### Requirement: Round-trip golden corpus

The test suite SHALL include byte-equal round-trip tests against the following committed fixtures: `multi-section-thesis.docx` (3 `<w:sectPr>`), `vml-rich.docx` (`<w:pict>` + `<mc:AlternateContent>`), `cjk-settings.docx` (full `word/settings.xml` with CJK font hints), `comment-anchored.docx` (`<w:commentRangeStart>` + reference triplets).

#### Scenario: Each fixture round-trips byte-equal

- **WHEN** any fixture is read and written with no mutations
- **THEN** the output bytes equal the input bytes for `word/document.xml`, `word/settings.xml`, `word/header*.xml`, `word/footer*.xml`, and `[Content_Types].xml`

### Requirement: Mixed content is ordered children with explicit text nodes（spec-frozen from design Q3）

`XmlNode` SHALL represent mixed content（e.g., `<w:r><w:t>foo</w:t><w:tab/><w:t>bar</w:t></w:r>`）as ordered children where text is an explicit text-kind node interleaved positionally with element children. Text SHALL NOT be stored as a leaf attribute of the parent element; serialization SHALL emit children strictly in stored order.

#### Scenario: interleaved text and element children round-trip in order

- **WHEN** a run containing text, an inline element, then more text is loaded and re-serialized
- **THEN** the output preserves the exact child order and byte content

### Requirement: rawChildren fields are bridge code removed in v1.0.0（spec-frozen from design Q6）

The ad-hoc `rawChildren: [String]` fields on typed models（`Run`, `Paragraph`, `SectionProperties`, `Settings`, …）SHALL be treated as deprecated bridge code superseded by tree coverage. v1.0.0 SHALL remove the fields; the per-issue `Issue<N>RoundTripTests` that motivated them SHALL be retained as regression tests against the tree path.

#### Scenario: removal keeps the round-trip guarantees

- **WHEN** the `rawChildren` fields are removed in the v1.0.0 cleanup
- **THEN** every `Issue<N>RoundTripTests` fixture still round-trips byte-equal through the tree path
