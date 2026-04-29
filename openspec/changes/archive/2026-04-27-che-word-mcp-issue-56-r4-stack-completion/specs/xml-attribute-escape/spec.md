## ADDED Requirements

### Requirement: ooxml-swift SHALL provide a single shared XML attribute escape helper

`ooxml-swift` SHALL expose `internal func escapeXMLAttribute(_ s: String) -> String` from `Sources/OOXMLSwift/IO/XMLAttributeEscape.swift` as the single source of truth for escaping caller-provided strings before interpolation into an OOXML attribute value. The helper SHALL escape the five XML attribute special characters as follows:

- `&` → `&amp;`
- `<` → `&lt;`
- `>` → `&gt;`
- `"` → `&quot;`
- `'` → `&apos;`

The choice of `&apos;` (rather than `&#39;`) SHALL match Microsoft Word's own emit output for byte-equivalent round-trip with documents authored in Word.

All `fileprivate` or duplicated escape implementations across `Run.swift`, `Revision.swift`, `Paragraph.swift`, `Style.swift`, `Numbering.swift`, `Table.swift`, `Field.swift`, `MathComponent.swift`, `DocxWriter.swift`, and any other emit site SHALL be deleted and replaced with calls to the shared helper.

#### Scenario: Helper escapes all five XML special characters

- **WHEN** `escapeXMLAttribute(#"a&b<c>d"e'f"#)` is invoked
- **THEN** the return value equals `"a&amp;b&lt;c&gt;d&quot;e&apos;f"`

#### Scenario: Helper preserves benign characters

- **WHEN** `escapeXMLAttribute("hello world 你好 123")` is invoked
- **THEN** the return value equals `"hello world 你好 123"` (no transformation applied to non-special characters including non-ASCII text)

### Requirement: Caller-provided String values for w:val, w:color, w:name, w:fill, w:author, w:moveId attributes SHALL be routed through escapeXMLAttribute

Every emit site in `ooxml-swift` that interpolates a caller-provided `String` (from public API parameters, MCP tool arguments, or model field reads where the model field originates from caller writes) into an OOXML attribute value of the following attribute names SHALL route the value through `escapeXMLAttribute(_:)` before interpolation:

- `w:val`, `w:val2`
- `w:color`, `w:fill`, `w:themeColor`, `w:themeFill`
- `w:name`, `w:rsidR`, `w:rsidRPr`
- `w:author`, `w:date`
- `w:id` (when emitted from a String field, not Int)
- `w:moveId`, `w:displacedByCustomXml`
- Any custom or vendor-namespaced attribute (`xmlns:*`, `vendor:*`)

Specific known-affected emit sites that SHALL be remediated as part of this change include: `ParagraphProperties.style` (`w:pStyle w:val`), `Style.id`/`name`/`aliases`/`basedOn`/`nextStyle`/`linkedStyleId` (`w:style w:styleId`/`w:name w:val`/etc.), `Numbering.lvlText`/`fontName` (`w:lvlText w:val`/`w:rFonts`), `Revision.MoveTracking.moveId` (`w:name`), `Table.CellShading.color`/`fill`, `Table.Border.color`, `Field.ParagraphBorder.color` (5 sides), `MathComponent.MathDelimiter.open`/`close`/`separator`, `DocxWriter.LatentStyle.name`. The R3-NEW-6 audit-table-as-self-attestation pattern (deny-list claiming "all sites covered") is forbidden as a verification approach.

#### Scenario: apply_style with attacker-controlled style name does not inject OOXML

- **GIVEN** a paragraph and the MCP tool input `apply_style(style: "Foo\"><w:bookmarkStart w:id=\"99\" w:name=\"PWNED\"/><w:pStyle w:val=\"")`
- **WHEN** the paragraph is emitted via `Paragraph.toXML()`
- **THEN** the emitted `<w:pStyle w:val="..."/>` element contains the user input fully escaped (`&quot;`, `&lt;`, `&gt;`) inside `w:val`
- **AND** no `<w:bookmarkStart>` element appears in the emit
- **AND** parsing the emitted XML yields a paragraph with `style` field equal to the original attacker input string (round-trip preserved)

#### Scenario: create_style with special-char id round-trips byte-equivalent

- **GIVEN** the MCP tool input `create_style(id: "Heading&Title", name: "<Test>", basedOn: "Normal'Quoted")`
- **WHEN** the style is emitted via `Style.toXML()`
- **THEN** the emit contains `w:styleId="Heading&amp;Title"`, `<w:name w:val="&lt;Test&gt;"/>`, `<w:basedOn w:val="Normal&apos;Quoted"/>`
- **AND** re-parsing yields a `Style` with `id == "Heading&Title"`, `name == "<Test>"`, `basedOn == "Normal'Quoted"`

### Requirement: Issue56R4StackTests SHALL include an allow-list audit table for emit sites NOT routed through escapeXMLAttribute

`packages/ooxml-swift/Tests/OOXMLSwiftTests/Issue56R4StackTests.swift` SHALL contain a comment block titled "Allow-list: emit sites NOT routed through escapeXMLAttribute, with rationale" that explicitly enumerates each emit site exempted from the escape requirement, with a justification for each exemption (e.g., "constants only", "test fixture builder", "numeric attribute via String(Int)"). The R3-style "audit table covering all sites" comment is forbidden because deny-list verification cannot be falsified by reviewer scan.

#### Scenario: Allow-list comment names every exempted emit site

- **GIVEN** the contents of `Issue56R4StackTests.swift`
- **WHEN** a reviewer searches for the audit comment block
- **THEN** the block exists, is titled "Allow-list", and lists each exempted file:line site with a rationale string
- **AND** for any site NOT in the allow-list, the implementation routes the value through `escapeXMLAttribute(_:)`

<!-- @trace
source: che-word-mcp-issue-56-r4-stack-completion
updated: 2026-04-26
code:
  - packages/ooxml-swift/Sources/OOXMLSwift/IO/XMLAttributeEscape.swift
  - packages/ooxml-swift/Tests/OOXMLSwiftTests/Issue56R4StackTests.swift
-->
