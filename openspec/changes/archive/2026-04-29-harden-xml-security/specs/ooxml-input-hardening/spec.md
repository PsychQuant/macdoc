## ADDED Requirements

### Requirement: DocxReader SHALL reject input containing a DTD declaration before constructing XMLDocument

`DocxReader.read(from:)` and every internal helper that constructs `XMLDocument(data:)` SHALL pre-scan the input `Data` for the literal byte sequence `<!DOCTYPE` (case-insensitive across ASCII variants) and throw `OOXMLError.dtdNotAllowed(part:)` when present. The throw SHALL occur before `XMLDocument(data:)` is invoked so that no entity expansion can begin. The `part` parameter SHALL identify which OOXML part triggered the reject (e.g., `"word/document.xml"`, `"word/header1.xml"`, `"word/footnotes.xml"`).

#### Scenario: Document part with DOCTYPE declaration is rejected

- **WHEN** `DocxReader.read(from:)` receives a `.docx` whose `word/document.xml` content begins with `<?xml version="1.0"?><!DOCTYPE document SYSTEM "external.dtd"><w:document>…`
- **THEN** the read SHALL throw `OOXMLError.dtdNotAllowed(part: "word/document.xml")` and SHALL NOT call `XMLDocument(data:)` on the offending part

##### Example: case-insensitive detection

| Input bytes (prefix) | Outcome |
| -------------------- | ------- |
| `<!DOCTYPE w:document>` | throw `dtdNotAllowed` |
| `<!doctype w:document>` | throw `dtdNotAllowed` |
| `<!Doctype w:document>` | throw `dtdNotAllowed` |
| `<w:document xmlns:w="…">` (no DOCTYPE) | proceed to `XMLDocument(data:)` |

#### Scenario: All container parts share the DTD reject guard

- **WHEN** any of `word/document.xml`, `word/header*.xml`, `word/footer*.xml`, `word/footnotes.xml`, `word/endnotes.xml`, `word/styles.xml`, `word/numbering.xml`, `word/comments.xml`, `word/_rels/document.xml.rels`, or any other XML part read by `DocxReader` contains a `<!DOCTYPE` declaration
- **THEN** the read SHALL throw `OOXMLError.dtdNotAllowed(part:)` with the part path identifying the source

---

### Requirement: DocxReader SHALL parse root-element attributes via XMLParser SAX, not via string-prefix matching

The helper that extracts root-element attributes from a part's raw `Data` (currently `parseContainerRootAttributes`) SHALL be implemented using `Foundation.XMLParser` in SAX mode. On the first `parser:didStartElement:namespaceURI:qualifiedName:attributes:` callback the implementation SHALL capture the `attributes` dictionary, call `parser.abortParsing()`, and return the captured map. The implementation SHALL handle arbitrary namespace prefix variants and the prior `rootElementOpenPrefix:` parameter SHALL NOT exist on the public API of this helper. Failure to parse (truly malformed XML) SHALL return `[:]`.

#### Scenario: Custom-prefix root element is parsed correctly

- **WHEN** `parseContainerRootAttributes(from: data)` is called with a part whose root open tag is `<wordml:document xmlns:wordml="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="…">`
- **THEN** the returned map SHALL contain both `xmlns:wordml` and `xmlns:r` keys with their respective URI values

#### Scenario: Default-namespace root element is parsed correctly

- **WHEN** the part's root open tag is `<document xmlns="http://schemas.openxmlformats.org/wordprocessingml/2006/main">`
- **THEN** the returned map SHALL contain the default-namespace declaration keyed under `xmlns` and SHALL NOT return `[:]`

#### Scenario: Truly malformed XML returns empty map

- **WHEN** the input bytes do not parse as well-formed XML (e.g., unterminated tag)
- **THEN** the helper SHALL return `[:]` and the caller's existing fallback to the hardcoded namespace template SHALL apply

---

### Requirement: Root-attribute names SHALL match the XML 1.0 NameChar regex on both ingest and emit

`DocxReader.splitAttributes` and `DocxWriter.renderDocumentRootOpenTag` SHALL validate every attribute name against the regex `^[A-Za-z_:][A-Za-z0-9._:-]*$` before accepting (reader) or writing (writer) the attribute. On violation, the reader SHALL throw `OOXMLError.invalidAttributeName(name: name, context: "split-attributes")` and the writer SHALL throw `OOXMLError.invalidAttributeName(name: name, context: "document root")`. The throw SHALL prevent the attribute from transiting into `documentRootAttributes` (reader) or into the emitted XML (writer).

#### Scenario: Attribute name with invalid leading character is rejected on ingest

- **WHEN** `splitAttributes` encounters an attribute named `0xmlns:w` (leading digit, illegal per XML 1.0 NameChar)
- **THEN** the helper SHALL throw `OOXMLError.invalidAttributeName(name: "0xmlns:w", context: "split-attributes")`

#### Scenario: Attribute name with embedded whitespace is rejected on emit

- **WHEN** `renderDocumentRootOpenTag` is given a `[String: String]` map containing the key `"xmlns w"` (embedded space)
- **THEN** the helper SHALL throw `OOXMLError.invalidAttributeName(name: "xmlns w", context: "document root")` and SHALL NOT write the partial open tag

#### Scenario: Spec-compliant names pass through unchanged

- **WHEN** the attribute name matches `^[A-Za-z_:][A-Za-z0-9._:-]*$` (e.g., `xmlns:w`, `mc:Ignorable`, `xml:space`)
- **THEN** the helper SHALL accept the name and proceed to value handling

---

### Requirement: DocxReader SHALL enforce a 64 KB cap on each attribute value

`DocxReader.splitAttributes` SHALL measure each parsed attribute value's UTF-8 byte length and throw `OOXMLError.attributeValueTooLarge(name:byteSize:cap:)` when the byte length exceeds 65 536 bytes. The throw SHALL occur during attribute parsing so that no oversized value transits into `documentRootAttributes`. Truncation SHALL NOT be performed.

#### Scenario: Oversized attribute value is rejected

- **WHEN** `splitAttributes` encounters `mc:Ignorable="aaaa…"` where the value is 100 000 bytes long
- **THEN** the helper SHALL throw `OOXMLError.attributeValueTooLarge(name: "mc:Ignorable", byteSize: 100000, cap: 65536)`

#### Scenario: Attribute value at exactly 64 KB is accepted

- **WHEN** `splitAttributes` encounters an attribute whose UTF-8 byte length is exactly 65 536 bytes
- **THEN** the helper SHALL accept the value (cap is "exceeds", not "equals")

##### Example: cap boundary

| Value byte length | Outcome |
| ----------------- | ------- |
| 64 | accept |
| 200 (typical `mc:Ignorable`) | accept |
| 65 535 | accept |
| 65 536 | accept (boundary) |
| 65 537 | throw `attributeValueTooLarge` |
| 1 048 576 (1 MB) | throw `attributeValueTooLarge` |

---

### Requirement: OOXMLError SHALL expose three new cases for input hardening

The `OOXMLError` enum in `Sources/OOXMLSwift/Models/OOXMLError.swift` SHALL define the cases:

```swift
case dtdNotAllowed(part: String)
case invalidAttributeName(name: String, context: String)
case attributeValueTooLarge(name: String, byteSize: Int, cap: Int)
```

Each case SHALL carry enough payload for the caller to log, surface to the user, and disambiguate the source of the offence without re-parsing the input. The cases SHALL be added to the existing enum so consumers continue to handle `OOXMLError` in a single `catch`.

#### Scenario: Caller distinguishes hardening errors from other OOXMLError cases

- **WHEN** a caller wraps `try DocxReader.read(from:)` in `do/catch` and switches on the caught `OOXMLError`
- **THEN** the caller SHALL be able to match `.dtdNotAllowed`, `.invalidAttributeName`, and `.attributeValueTooLarge` distinctly from other `OOXMLError` cases (e.g., `.unsupportedVersion`, `.malformedArchive`)

---

### Requirement: Hardening SHALL preserve behaviour for valid input

For any input that does not contain a DTD declaration, contains only well-formed root-element attribute names per XML 1.0 NameChar, and contains no attribute value exceeding 65 536 bytes, the public observable behaviour of `DocxReader.read(from:)` and `DocxWriter.write(to:)` SHALL be identical to the v0.21.2 baseline. No additional throws, no new error semantics, no SemVer-breaking changes for valid input SHALL be introduced.

#### Scenario: Round-trip of legitimate corpus document is unaffected

- **WHEN** a `.docx` from the existing test corpus (no DTD, no oversized attributes, conformant attribute names) is read and written back
- **THEN** the output SHALL match the v0.21.2 byte-equivalence baseline and the existing test suite SHALL pass without modification
