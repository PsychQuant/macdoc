## 1. XMLHardeningError new enum (per-domain pattern)

> Implements requirement: **OOXMLError SHALL expose three new cases for input hardening**
> Covers design decision: D6 — single consolidated `XMLHardeningError.swift` extension
>
> **Apply-time deviation note (2026-04-29)**: design + spec assumed an existing `OOXMLError` enum, but survey of `Sources/OOXMLSwift/` reveals 13 per-domain error enums (`WordError` / `RevisionError` / `ImageError` / `WrapCaptionError` / etc., one per `Error: LocalizedError` conformance, located in `Sources/OOXMLSwift/Errors/` or alongside the model). No global `OOXMLError` exists. To match codebase pattern, this change creates a NEW per-domain enum `XMLHardeningError` in `Sources/OOXMLSwift/Errors/XMLHardeningError.swift` with the three cases. Acceptance criteria preserved verbatim — only the symbol name changes from `OOXMLError` → `XMLHardeningError` throughout the implementation. Spec/design will be aligned at archive time.

- [x] 1.1 Create `Sources/OOXMLSwift/Errors/XMLHardeningError.swift` with `public enum XMLHardeningError: Error, LocalizedError, Equatable` and the three cases: `dtdNotAllowed(part: String)`, `invalidAttributeName(name: String, context: String)`, `attributeValueTooLarge(name: String, byteSize: Int, cap: Int)`. Provide `errorDescription` returning a human-readable string per case (e.g., `"DTD declarations are not permitted in OOXML input (part: \(part))"`).
- [x] 1.2 Verify acceptance: OOXMLError SHALL expose three new cases for input hardening — `swift build` succeeds and the three cases of the new `XMLHardeningError` enum are pattern-matchable in a `switch` over `XMLHardeningError`.

## 2. F10 — DTD pre-scan reject (TDD: write tests first)

> Implements requirement: **DocxReader SHALL reject input containing a DTD declaration before constructing XMLDocument**
> Covers design decisions: D1 — Throw, do not silently filter (F10/F12/F14); D2 — DTD pre-scan via raw `Data.range(of:)`, not via `XMLDocument` post-parse (F10)

- [x] 2.1 [P] Write `testReadRejectsDocxWithDOCTYPEInDocumentXML` in `Tests/OOXMLSwiftTests/Issue7XMLHardeningTests.swift` — fixture .docx whose `word/document.xml` begins with `<!DOCTYPE w:document>...`; assert `XCTAssertThrowsError` matches `XMLHardeningError.dtdNotAllowed(part: "word/document.xml")`.
- [x] 2.2 [P] Write `testReadRejectsDocxWithDOCTYPEInHeaderXML` and `testReadRejectsDocxWithLowercaseDoctypeVariant` covering `word/header1.xml` (mixed/lowercase `<!doctype>` variants).
- [x] 2.3 Add `private static func rejectDTD(_ data: Data, part: String) throws` to `Sources/OOXMLSwift/IO/DocxReader.swift` using `Data.range(of: "<!DOCTYPE".data(using: .ascii)!)` plus the lowercase variant; throws `XMLHardeningError.dtdNotAllowed(part:)`.
- [x] 2.4 Insert `try Self.rejectDTD(documentData, part: "word/document.xml")` immediately before each of the 12 `XMLDocument(data:)` call sites in `Sources/OOXMLSwift/IO/DocxReader.swift` (L127, L149, L158, L205, L263, L295, L349, L398, L407, L490, L583 — confirm exact line numbers during apply); pass the corresponding part name as the `part` argument.
- [x] 2.5 Run `swift test --filter Issue7XMLHardeningTests` — confirm 2.1/2.2/2.3 tests pass green.
- [x] 2.6 Verify acceptance: DocxReader SHALL reject input containing a DTD declaration before constructing XMLDocument — every one of the 12 `XMLDocument(data:)` call sites in `DocxReader.swift` is preceded by a `try Self.rejectDTD(...)` invocation; absence of any one is a regression.

## 3. F11 — XMLParser SAX root-attr parser (TDD: write tests first)

> Implements requirement: **DocxReader SHALL parse root-element attributes via XMLParser SAX, not via string-prefix matching**
> Covers design decision: D3 — Foundation `XMLParser` SAX for root attributes, removing string-prefix fallback (F11)

- [x] 3.1 [P] Write `testParseRootAttrsHandlesCustomPrefix` — give `parseContainerRootAttributes(from:)` a `Data` containing `<wordml:document xmlns:wordml="..." xmlns:r="...">`; assert returned map contains both keys with correct URIs.
- [x] 3.2 [P] Write `testParseRootAttrsHandlesDefaultNamespace` — input `<document xmlns="...">`; assert returned map contains the default-namespace declaration keyed under `xmlns`.
- [x] 3.3 [P] Write `testParseRootAttrsReturnsEmptyOnMalformedXML` — input is unterminated tag; assert returned map is `[:]` (caller fallback path preserved).
- [x] 3.4 In `Sources/OOXMLSwift/IO/DocxReader.swift`, define a `private final class RootAttrSAXDelegate: NSObject, XMLParserDelegate` that captures the first `didStartElement`'s `attributes` dictionary and calls `parser.abortParsing()`.
- [x] 3.5 Replace the body of `parseContainerRootAttributes(from:)` to instantiate `XMLParser(data:)`, set the delegate, call `parse()`, and return the captured attributes (or `[:]` on no-element-seen). Remove the `rootElementOpenPrefix:` parameter from the public signature; update all 4 call sites (header / footer / footnotes / endnotes) to use the simpler 1-arg form.
- [x] 3.6 Delete the now-dead string-prefix scanning helper code in `parseContainerRootAttributes` (the `raw.range(of:)` + while-loop attribute slicing block). Keep `splitAttributes` (used elsewhere — see Task Group 4 + 5).
- [x] 3.7 Run `swift test --filter Issue7XMLHardeningTests` — confirm 3.1/3.2/3.3 tests pass and existing root-attr round-trip tests in the broader suite still pass.
- [x] 3.8 Verify acceptance: DocxReader SHALL parse root-element attributes via XMLParser SAX, not via string-prefix matching — `parseContainerRootAttributes` no longer accepts a `rootElementOpenPrefix:` parameter; all 4 callers (header / footer / footnotes / endnotes) compile against the new signature.

## 4. F12 — Attribute-name whitelist (TDD: write tests first)

> Implements requirement: **Root-attribute names SHALL match the XML 1.0 NameChar regex on both ingest and emit**
> Covers design decisions: D1 — Throw, do not silently filter (F10/F12/F14); D4 — Attribute-name whitelist regex, applied at both ingest and emit (F12)

- [x] 4.1 [P] Write `testSplitAttributesRejectsLeadingDigitInName` — pass `splitAttributes` an attribute string with `0xmlns:w="..."`; assert throw of `XMLHardeningError.invalidAttributeName(name: "0xmlns:w", context: "split-attributes")`.
- [x] 4.2 [P] Write `testSplitAttributesAcceptsConformantNames` — pass `xmlns:w="..." mc:Ignorable="..." xml:space="..."`; assert all three round-trip without throw.
- [x] 4.3 [P] Write `testRenderDocumentRootOpenTagRejectsWhitespaceInName` — pass `["xmlns w": "..."]` to `DocxWriter.renderDocumentRootOpenTag`; assert throw of `XMLHardeningError.invalidAttributeName(name: "xmlns w", context: "document root")`.
- [x] 4.4 Add `private static let attrNameRegex = try! NSRegularExpression(pattern: #"^[A-Za-z_:][A-Za-z0-9._:-]*$"#)` plus `private static func validateAttrName(_ name: String, context: String) throws` helper to a shared location accessible by both `DocxReader` and `DocxWriter` (e.g., a new `Sources/OOXMLSwift/IO/XMLNameValidator.swift` internal file, or a static on `XMLHardeningError`).
- [x] 4.5 Call `try validateAttrName(name, context: "split-attributes")` inside `DocxReader.splitAttributes` immediately after each name is parsed and before it is inserted into the result dictionary; convert `splitAttributes` signature to `throws`.
- [x] 4.6 Update `splitAttributes`'s 1 caller (`parseContainerRootAttributes`) to `try` the call. Convert `parseContainerRootAttributes` to `throws` if it is not already; update its callers (header / footer / footnotes / endnotes raw-byte ingestion) to propagate or `try?`.
- [x] 4.7 Convert `DocxWriter.renderDocumentRootOpenTag` to `throws` (or a `Result` if rest of writer is non-throwing); call `try validateAttrName(name, context: "document root")` in the loop that builds `pieces`. Update the 1 call site at `DocxWriter.swift` ~L669 to `try` accordingly.
- [x] 4.8 Run `swift test --filter Issue7XMLHardeningTests` and the full suite — confirm 4.1/4.2/4.3 pass and no previously-green tests fail due to the new `throws` signatures.
- [x] 4.9 Verify acceptance: Root-attribute names SHALL match the XML 1.0 NameChar regex on both ingest and emit — both `DocxReader.splitAttributes` and `DocxWriter.renderDocumentRootOpenTag` invoke the shared `validateAttrName` helper before accepting / writing.

## 5. F14 — 64 KB attribute-value byte cap (TDD: write tests first)

> Implements requirement: **DocxReader SHALL enforce a 64 KB cap on each attribute value**
> Covers design decisions: D1 — Throw, do not silently filter (F10/F12/F14); D5 — 64 KB per-attribute-value cap (F14)

- [x] 5.1 [P] Write `testSplitAttributesRejectsValueOver64KB` — input attribute string `mc:Ignorable="aaaa…"` with value of 100 000 ASCII bytes; assert throw `XMLHardeningError.attributeValueTooLarge(name: "mc:Ignorable", byteSize: 100000, cap: 65536)`.
- [x] 5.2 [P] Write `testSplitAttributesAcceptsValueAt64KBBoundary` — value of exactly 65 536 ASCII bytes accepted without throw; value of 65 537 bytes throws.
- [x] 5.3 In `Sources/OOXMLSwift/IO/DocxReader.swift` `splitAttributes`, after the value is captured but before insertion, compute `let byteSize = value.utf8.count`; if `byteSize > 65_536`, `throw XMLHardeningError.attributeValueTooLarge(name: name, byteSize: byteSize, cap: 65_536)`. Define `private static let attrValueByteCap = 65_536` constant for readability.
- [x] 5.4 Run `swift test --filter Issue7XMLHardeningTests` — confirm 5.1/5.2 pass.
- [x] 5.5 Verify acceptance: DocxReader SHALL enforce a 64 KB cap on each attribute value — boundary tests at 65 535 / 65 536 / 65 537 bytes match the spec example table; truncation is never performed.

## 6. Audit & regression sweep

> Implements requirement: **Hardening SHALL preserve behaviour for valid input**

- [x] 6.1 Run full `swift test` — assert all 722 baseline tests pass, plus 12 new tests added in groups 2-5 (target test count 734).
- [x] 6.2 Audit-discipline pass per `audit: true` (3 adversary lenses on the new throws): Scoundrel — does the throw leak attacker-controlled bytes verbatim into the error description? (Answer in `Sources/OOXMLSwift/Errors/XMLHardeningError.swift` — name field is bounded by attr-name regex; `byteSize`/`cap` are integers.) Lazy Developer — could a caller silence the throws via `try?` and swallow corruption? (Document in `XMLHardeningError` doc-comment that callers SHOULD propagate, not silence.) Confused Developer — could the `context` string be misread? (Use namespaced strings: `"split-attributes"` not `"reader"`.)
- [x] 6.3 Add file-level doc comment to `Sources/OOXMLSwift/IO/DocxReader.swift` rejectDTD helper referencing this change name and PsychQuant/ooxml-swift#7 so future readers see the invariant origin.
- [x] 6.4 Verify acceptance: Hardening SHALL preserve behaviour for valid input — full test suite still green (722 baseline tests + 12 new hardening tests = 734 pass); no SemVer-breaking change observed for legitimate `.docx` corpus.

## 7. Release prep

- [x] 7.1 Bump `Package.swift` version comment / `CHANGELOG.md` entry under `## [Unreleased] → ## [0.21.3] - 2026-04-29` (date placeholder filled at release time). Group entries by F10/F11/F12/F14 with brief callouts; emphasise "no public API change for valid input".
- [x] 7.2 Add a "Security" section to the v0.21.3 release notes listing the four newly-rejected attack vectors (billion-laughs DTD, prefix-variant root-attr silent failure, attribute-name injection on emit, attribute-value DoS amplification).
