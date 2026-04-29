# Tasks — word-mcp-readback-primitives

## 1. ooxml-swift: FieldCode.parse(instrText:) additions

- [x] 1.1 Add `static func parse(instrText: String) -> Self?` to `SequenceField` in `packages/ooxml-swift/Sources/OOXMLSwift/Models/Field.swift`. Grammar: `" SEQ <identifier>[ \\* <NumberFormat>][ \\s <level>][ \\h] "`. Applies the FieldCode conforming types provide static parse(instrText:) for round-trip requirement. Each FieldCode type parses its own instrText grammar — covers the static parse additive extension to SequenceField.

- [x] 1.2 [P] Add `static func parse(instrText: String) -> Self?` to `StyleRefField`. Grammar: `" STYLEREF <int>[ \\s][ \\l] "`.

- [x] 1.3 [P] Add `static func parse(instrText: String) -> Self?` to `ReferenceField`. Grammar: `" (REF|PAGEREF|NOTEREF) <bookmark>[ \\p][ \\h] "`. Dispatch on the leading token to select `ReferenceFieldType`.

- [~] 1.4 [P] Add `static func parse(instrText: String) -> Self?` to `IFField`. Grammar: `" IF <left-operand> <operator> <right-operand> <true-quoted-text> <false-quoted-text> "`. Use Swift regex for quoted-string extraction.

- [~] 1.5 [P] Add `static func parse(instrText: String) -> Self?` to `CalculationField` / `DateTimeField` / `DocumentInfoField` / `MergeField` (group — simple single-token grammars).

- [x] 1.6 Write `packages/ooxml-swift/Tests/OOXMLSwiftTests/FieldCodeParseTests.swift` — 15+ test cases: valid grammar for each type, invalid grammar returns nil, whitespace tolerance, fully-round-trip `write(toFieldXML) → extract instrText → parse → verify equality`. TDD: write tests first, confirm RED, land 1.1-1.5, all green.

## 2. ooxml-swift: FieldParser module

- [x] 2.1 Create `packages/ooxml-swift/Sources/OOXMLSwift/Parsing/FieldParser.swift`. Applies the Parser module lives under `ooxml-swift/Sources/OOXMLSwift/Parsing/` decision. Define `public struct ParsedField { startRunIdx: Int; endRunIdx: Int; cachedResultRunIdx: Int?; instrText: String; field: ParsedFieldValue }` — applies the ParsedField is a struct with range info decision so MCP CRUD tools can locate specific runs to modify. Also define `public enum ParsedFieldValue { case sequence(SequenceField); case styleRef(StyleRefField); case reference(ReferenceField); case iff(IFField); case calculation(CalculationField); case dateTime(DateTimeField); case documentInfo(DocumentInfoField); case merge(MergeField); case unknown(instrText: String) }` — applies the Unknown fields and math stay as opaque cases decision. Applies the XMLParser-based SAX parsers, not string scanning decision. Covers the FieldParser parses fldChar regions in a Paragraph into typed ParsedField values requirement.

- [x] 2.2 Implement `public static func parse(paragraph: Paragraph) -> [ParsedField]` scanning paragraph runs. For each run, inspect `rawXML` for `<w:fldChar fldCharType="begin">` / `<w:instrText>` / `<w:fldChar fldCharType="separate">` / `<w:t>` / `<w:fldChar fldCharType="end">` using Foundation.XMLParser SAX callbacks over a concatenated pseudo-XML of runs' rawXML. Track run indices while streaming.

- [x] 2.3 Implement cascading dispatch: `SequenceField.parse(instrText:)` → if nil try `StyleRefField.parse` → if nil try `ReferenceField.parse` → ... → if all nil return `.unknown(instrText:)`. Applies the Each FieldCode type parses its own instrText grammar decision.

- [x] 2.4 Write `packages/ooxml-swift/Tests/OOXMLSwiftTests/FieldParserTests.swift` — 10+ cases: single SEQ round-trip, cross-run field span tracking, unknown field preservation, mixed field types in one paragraph, empty paragraph → empty array.

## 3. ooxml-swift: OMMLParser module + MathComponent.unknownXML case

- [x] 3.1 Add `case unknownXML(String)` to the representation used for parsed math trees in `packages/ooxml-swift/Sources/OOXMLSwift/Models/MathComponent.swift`. Since `MathComponent` is a protocol (not an enum), add a dedicated `public struct UnknownMath: MathComponent { public let rawXML: String; public func toOMML() -> String { rawXML } }` type. Covers the MathComponent enum adds unknownXML opaque fallback case requirement.

- [x] 3.2 Create `packages/ooxml-swift/Sources/OOXMLSwift/Parsing/OMMLParser.swift`. Define `public enum OMMLParser { static func parse(xml: String) -> [MathComponent] }`. Use Foundation.XMLParser delegate with explicit stack management. Recognize `<m:oMath>` / `<m:oMathPara>` as root wrappers (strip). Dispatch children by tag: `<m:r>` → MathRun; `<m:f>` → MathFraction; `<m:sSub>` / `<m:sSup>` / `<m:sSubSup>` → MathSubSuperScript; `<m:rad>` → MathRadical; `<m:nary>` → MathNary; `<m:d>` → MathDelimiter; `<m:func>` → MathFunction; `<m:limLow>` / `<m:limUpp>` → MathLimit; `<m:m>` → MathMatrix. Unrecognized tags → `UnknownMath(rawXML: ...)`. Applies the XMLParser-based SAX parsers, not string scanning decision. Covers the OMMLParser parses m:oMath XML into a MathComponent AST requirement.

- [x] 3.3 Write `packages/ooxml-swift/Tests/OOXMLSwiftTests/OMMLParserTests.swift` — 12+ cases: each of 9 MathComponent types round-trips (write via toOMML → read via parse → assert structural equality), nested composition (fraction inside radical), m:oMathPara wrapper stripping, unknown subtree preserved via UnknownMath, malformed XML returns empty array + UnknownMath fallback.

## 4. ooxml-swift: WordDocument.updateAllFields()

- [x] 4.1 Add `public mutating func updateAllFields() -> [String: Int]` to `WordDocument` in `packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift`. Walks body paragraphs + all headers + all footers + all footnotes + all endnotes (same traversal pattern as v0.8.0's `replaceText(scope: .all)`). For each paragraph, call `FieldParser.parse(paragraph:)`, iterate `ParsedField` values, maintain per-identifier counters keyed by `SequenceField.identifier`. Applies the updateAllFields implements SEQ only (Phase 1) decision. Covers the WordDocument.updateAllFields recomputes SEQ counters across all containers requirement.

- [x] 4.2 Implement SEQ counter reset logic: when a paragraph has `pStyle == "Heading 1"` / `"Heading 2"` / ..., reset counters for SEQ fields whose `resetLevel == <that heading level>`. Track current heading context as a running `[Int: String]` (level → most recent heading seen); when walking a SEQ field with `resetLevel == N`, reset its counter before incrementing.

- [x] 4.3 After counter assignment, mutate the matching `cachedResultRunIdx`'s `<w:t>` in the run's `rawXML`. Non-SEQ fields have their cached run preserved verbatim (identity pass).

- [x] 4.4 Write `packages/ooxml-swift/Tests/OOXMLSwiftTests/UpdateAllFieldsTests.swift` — 8+ cases: single SEQ identifier increments, distinct identifiers are independent, chapter-reset captions restart on heading level 1 (thesis fixture: 4 chapters × 3 figures), non-SEQ fields unmutated, empty document returns empty dict, SEQ in header vs body vs footnote traversed.

## 5. ooxml-swift: release v0.10.0

- [x] 5.1 Update `packages/ooxml-swift/CHANGELOG.md` with `## [0.10.0]` entry: Added section listing `FieldParser`, `OMMLParser`, `UnknownMath` struct, `WordDocument.updateAllFields()`, `FieldCode.parse(instrText:)` extensions. Note the `UnknownMath` as a new opaque value that callers holding arrays of `MathComponent` may encounter on round-trip.

- [x] 5.2 Run `swift test` in `packages/ooxml-swift/` — all existing + new tests pass.

- [x] 5.3 Git commit + push; tag `v0.10.0` + push tag; `gh release create v0.10.0` with CHANGELOG excerpt.

## 6. che-word-mcp: Package.swift dep + Caption CRUD tools

- [x] 6.1 Bump `mcp/che-word-mcp/Package.swift` ooxml-swift dep to `from: "0.10.0"`, run `swift package update ooxml-swift`, confirm `swift build` succeeds.

- [x] 6.2 Add 4 Tool schemas (`list_captions`, `get_caption`, `update_caption`, `delete_caption`) in Server.swift near existing `insert_caption` schema. args per proposal. Applies the Parser module lives under Parsing/ folder decision (upstream); covers the list_captions MCP tool enumerates captions in document order, get_caption returns full caption detail, update_caption modifies caption text or label without breaking SEQ field, delete_caption removes caption paragraph requirements.

- [x] 6.3 Wire dispatch cases for the 4 caption tools in main switch.

- [x] 6.4 Implement `listCaptions(args:)` handler: iterate body paragraphs, filter `pStyle == "Caption"`, call `FieldParser.parse(paragraph:)`, extract `SequenceField` instances + the run text after the SEQ field as `caption_text`. Build response array.

- [x] 6.5 Implement `getCaption(args:)` handler: use same scan, return descriptor at given `index`. Include optional `chapter_number` when paragraph also contains `StyleRefField`.

- [x] 6.6 Implement `updateCaption(args:)` handler: handle `new_caption_text` (modify trailing text run) and `new_label` (rewrite SEQ identifier + leading label text) branches. Return error when both args nil.

- [x] 6.7 Implement `deleteCaption(args:)` handler: find paragraph index for the caption, call existing `doc.deleteParagraph(at:)`.

## 7. che-word-mcp: update_all_fields tool

- [x] 7.1 Add Tool schema `update_all_fields(doc_id)` in Server.swift. Description: "F9-equivalent — recompute SEQ counters across body/headers/footers/footnotes/endnotes. Non-SEQ fields (IF, DATE, PAGE, etc.) unchanged."

- [x] 7.2 Wire dispatch case for `"update_all_fields"`.

- [x] 7.3 Implement `updateAllFieldsHandler(args:)`: call `doc.updateAllFields()`, format the `[String: Int]` result into a human-readable response (e.g., `"Updated 12 fields:\n  Figure: 8\n  Table: 4"`). Covers the update_all_fields MCP tool recomputes SEQ counters across the document requirement.

## 8. che-word-mcp: Equation CRUD tools

- [x] 8.1 Add 4 Tool schemas (`list_equations`, `get_equation`, `update_equation`, `delete_equation`) in Server.swift near existing `insert_equation` schema. args per proposal.

- [x] 8.2 Wire 4 dispatch cases.

- [x] 8.3 Implement `listEquations(args:)`: iterate body paragraphs, find runs whose `rawXML` contains `<m:oMath` (string match is sufficient for detection), call `OMMLParser.parse(xml:)` per run, return descriptors with `display_mode` inferred from presence of `<m:oMathPara>`. Covers the list_equations MCP tool enumerates m:oMath runs in document order requirement.

- [x] 8.4 Implement `getEquation(args:)`: same scan, return single descriptor at index with full `components` tree serialized as JSON-shaped response. Covers the get_equation returns the full MathComponent tree requirement.

- [~] 8.5 Implement `updateEquation(args:)`: parse incoming `components` JSON (reuse `parseMathComponent(from:)` helper from v2.0.0 `insertEquation`), emit new OMML, replace target run's `rawXML`. Covers the update_equation replaces the target equation's components requirement.

- [x] 8.6 Implement `deleteEquation(args:)`: find target run, remove it; if its paragraph becomes empty (no remaining runs), remove the paragraph. Covers the delete_equation removes equation run or containing paragraph requirement.

## 9. che-word-mcp: tests + release v3.1.0

- [~] 9.1 Add `mcp/che-word-mcp/Tests/CheWordMCPTests/CaptionCRUDTests.swift` — integration tests: insert 3 captions → list_captions returns 3 → get_caption(1) returns second → update_caption text → verify change → delete_caption(0) → list returns 2.

- [~] 9.2 Add `mcp/che-word-mcp/Tests/CheWordMCPTests/EquationCRUDTests.swift` — integration tests: insert equation with components → list_equations returns 1 → get_equation round-trips components → update_equation → verify change → delete_equation → list returns 0.

- [~] 9.3 Add `mcp/che-word-mcp/Tests/CheWordMCPTests/UpdateAllFieldsTests.swift` — integration test: insert 3 figures + 2 tables → update_all_fields → response reports `Figure: 3, Table: 2`.

- [x] 9.4 Full `swift test` passes (existing 45 + new ~20 = ~65 tests).

- [x] 9.5 Update `mcp/che-word-mcp/CHANGELOG.md` with `## [3.1.0]` entry: Added section listing 9 new tools. Note this is a minor bump (additive, no breaking schema changes from 3.0.0).

- [x] 9.6 Bump `mcp/che-word-mcp/mcpb/manifest.json` version to `3.1.0`.

- [x] 9.7 Universal build: `swift build -c release --arch arm64` + `--arch x86_64` + `lipo` + `xattr -cr` + `codesign --force --sign -`. Rebuild `.mcpb` package.

- [x] 9.8 Git commit; push main; tag `v3.1.0`; push tag; `gh release create v3.1.0` with CHANGELOG excerpt + upload `CheWordMCP` binary + `che-word-mcp.mcpb`.

## 10. Plugin marketplace sync + issue closure

- [x] 10.1 Bump `plugins/che-word-mcp/.claude-plugin/plugin.json` + root `.claude-plugin/marketplace.json` `che-word-mcp` entry to `3.1.0`, commit, push on the plugin marketplace repo.

- [x] 10.2 `claude plugin marketplace update psychquant-claude-plugins` + `claude plugin update che-word-mcp@psychquant-claude-plugins` — per `common-release-flow.md` post-release mandatory chain.

- [x] 10.3 Close `PsychQuant/che-word-mcp#17` with Closing Summary referencing v3.1.0 + `list_captions` / `get_caption` / `update_caption` / `delete_caption`.

- [x] 10.4 Close `PsychQuant/che-word-mcp#19` with Closing Summary referencing v3.1.0 + `update_all_fields`.

- [x] 10.5 Close `PsychQuant/che-word-mcp#21` with Closing Summary referencing v3.1.0 + `list_equations` / `get_equation` / `update_equation` / `delete_equation`.
