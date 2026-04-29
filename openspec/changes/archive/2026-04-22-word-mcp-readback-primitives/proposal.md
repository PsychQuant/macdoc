## Why

che-word-mcp's write-side for fields and math is mature (v2.0 `SequenceField`, `StyleRefField`, `ReferenceField` via `FieldCode` protocol; `MathComponent` AST with 9 types), but **there is no read-side counterpart**. Three GitHub issues (#17, #19, #21) are all blocked by this single gap:

- **#17** caption CRUD (`list_captions`, `get_caption`, `update_caption`, `delete_caption`): requires walking paragraphs, recognizing `pStyle="Caption"` + `<w:fldChar>` SEQ regions, parsing each region back into a typed `SequenceField` + cached result value. Currently zero way to enumerate existing captions.
- **#19** `update_all_fields` (Word Ctrl+A → F9 equivalent): requires iterating every `<w:fldChar begin>...<w:fldChar end>` span in the document, classifying the `instrText` (SEQ / STYLEREF / REF / PAGE / ...), and recomputing the cached `<w:t>` value between `separate` and `end`. Currently fields stay frozen at whatever `cachedResult` was written.
- **#21** equation CRUD (`list_equations`, `get_equation`, `update_equation`, `delete_equation`): requires parsing `<m:oMath>` XML subtrees back into `MathComponent` trees so callers can enumerate and edit them. Currently equations are write-only — once inserted they cannot be listed, let alone modified.

All three share one missing architectural piece: **read-side parsers** — `FieldParser` (OOXML `<w:fldChar>` sequence → typed `FieldCode`) and `OMMLParser` (OOXML `<m:oMath>` → `MathComponent` AST). Once those exist, the 3 issue clusters become thin MCP serialization layers wrapping them. Fixing issues one-at-a-time would reinvent the same parsers three times in per-tool code.

## What Changes

### Layer 1 primitives (ooxml-swift — bumps to 0.10.0)

- **NEW `FieldParser`** in `packages/ooxml-swift/Sources/OOXMLSwift/Parsing/FieldParser.swift`. Given a `Paragraph`, returns `[ParsedField]` where each `ParsedField` is `{ range: (startRunIdx, endRunIdx), field: FieldCode, cachedResult: String? }`. Scans run-level `rawXML` for `<w:fldChar fldCharType="begin">...<w:fldChar fldCharType="end">` spans, reads the `<w:instrText>` inside, dispatches to typed-field parsers (`SequenceField.parse(instrText:)`, `StyleRefField.parse`, `ReferenceField.parse`). Unknown field types are preserved as `ParsedField.unknown(instrText: String)` so callers don't lose data.

- **NEW `OMMLParser`** in `packages/ooxml-swift/Sources/OOXMLSwift/Parsing/OMMLParser.swift`. Given an `<m:oMath>` XML string (typically from a `Run.rawXML`), returns a `[MathComponent]` tree. Handles the 9 existing `MathComponent` types (`MathRun`, `MathFraction`, `MathSubSuperScript`, `MathRadical`, `MathNary`, `MathDelimiter`, `MathFunction`, `MathLimit`, `MathMatrix`) via XMLParser-based dispatch on tag names (`<m:f>`, `<m:sSub>`, `<m:rad>`, `<m:nary>`, etc.). Unrecognized subtrees are preserved as opaque `MathComponent.unknownXML(String)` cases to avoid data loss on round-trip.

- **NEW `FieldCode.parse(instrText:)` static method** on the existing `FieldCode` protocol — each conforming type (`SequenceField`, `StyleRefField`, `ReferenceField`, `IFField`, `CalculationField`, etc.) implements parsing of its own `instrText` grammar (e.g., `" SEQ Figure \* ARABIC \s 1 "` → `SequenceField(identifier: "Figure", format: .arabic, resetLevel: 1)`). Parser returns `nil` when the instrText does not match that field type, allowing cascading dispatch.

- **NEW field counter recomputation**: `WordDocument.updateAllFields()` iterates every `ParsedField` in body + headers + footers + footnotes + endnotes, maintains per-identifier SEQ counters (reset on matching heading level when `\s N` present), and writes recomputed cached results back into each field's `<w:t>` between `separate` and `end`. This is the F9-equivalent for #19.

### Layer 4 MCP tools (che-word-mcp — bumps to 3.1.0)

- **`list_captions(doc_id)`** — returns array of `{ index, label, sequence_number, caption_text, paragraph_index }` by scanning paragraphs with `pStyle == "Caption"` and parsing their SEQ fields. Refs #17.

- **`get_caption(doc_id, index)`** — returns full `{ label, sequence_number, chapter_number?, caption_text, paragraph_index, field_instr_text }`. Refs #17.

- **`update_caption(doc_id, index, new_caption_text: String?, new_label: String?)`** — modifies the post-SEQ text suffix (the human-readable caption) or the SEQ identifier (which re-renumbers). Refs #17.

- **`delete_caption(doc_id, index)`** — removes the caption paragraph. Refs #17.

- **`update_all_fields(doc_id)`** — calls `WordDocument.updateAllFields()`, returns count of fields updated + per-identifier counter summary. Refs #19.

- **`list_equations(doc_id)`** — returns `{ index, paragraph_index, component_tree }` for every `<m:oMath>` run in the document. Refs #21.

- **`get_equation(doc_id, index)`** — returns the full `MathComponent` tree as JSON (same shape as `insert_equation(components:)` input). Refs #21.

- **`update_equation(doc_id, index, components: MathComponent-JSON)`** — replaces the target `<m:oMath>` with new tree. Refs #21.

- **`delete_equation(doc_id, index)`** — removes the equation run (or its containing paragraph if sole content). Refs #21.

### Non-Goals

See `design.md` (Goals/Non-Goals section).

## Capabilities

### New Capabilities

- `ooxml-read-back-parsers`: Layer 1 read-side parsers in ooxml-swift — `FieldParser` (recognizes `<w:fldChar>` field spans inside paragraph runs and parses them into typed `FieldCode` values), `OMMLParser` (recognizes `<m:oMath>` XML and parses it into `MathComponent` AST), plus the `WordDocument.updateAllFields()` SEQ counter recomputation that closes the F9 gap. Unknown field types / math subtrees are preserved as opaque cases so round-tripping never loses data.

- `che-word-mcp-field-equation-crud`: Layer 4 MCP tools in che-word-mcp for read / update / delete of captions (4 tools), equations (4 tools), and `update_all_fields` (1 tool) — 9 tools total, all built on the Layer 1 parsers. Opens the CRUD half of the OOXML fields and math capabilities that v2.0.0 only shipped the write half of.

### Modified Capabilities

*(none — this change introduces two new capabilities. Existing specs are unaffected.)*

## Impact

- **Affected specs**: 2 new (`ooxml-read-back-parsers`, `che-word-mcp-field-equation-crud`). No existing specs modified.
- **Affected code**:
  - `packages/ooxml-swift/Sources/OOXMLSwift/Parsing/FieldParser.swift` — **new file** (~200 lines). XMLParser-based dispatch over `fldChar` spans.
  - `packages/ooxml-swift/Sources/OOXMLSwift/Parsing/OMMLParser.swift` — **new file** (~300 lines). Recursive XMLParser over `<m:oMath>` subtree.
  - `packages/ooxml-swift/Sources/OOXMLSwift/Models/Field.swift` — add `static func parse(instrText:)` to `FieldCode` protocol + implementations on `SequenceField`, `StyleRefField`, `ReferenceField`, `IFField`, `CalculationField`, `DateTimeField`, `DocumentInfoField`, `MergeField` (~100 lines).
  - `packages/ooxml-swift/Sources/OOXMLSwift/Models/MathComponent.swift` — add `enum MathComponent.unknownXML(String)` case for opaque fallback.
  - `packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift` — add `func updateAllFields() -> [String: Int]` (per-identifier counter summary). Requires header/footer/footnote/endnote traversal from v0.8.0's `replaceText(.all)` pattern.
  - `mcp/che-word-mcp/Sources/CheWordMCP/Server.swift` — 9 new tool schemas + 9 handlers (~500 lines).
- **Tests**:
  - `packages/ooxml-swift/Tests/OOXMLSwiftTests/FieldParserTests.swift` — new, ~20 XCTest cases (round-trip each field type, handle unknown types).
  - `packages/ooxml-swift/Tests/OOXMLSwiftTests/OMMLParserTests.swift` — new, ~30 XCTest cases (parse each of 9 MathComponent types, nested composition, malformed XML recovery).
  - `packages/ooxml-swift/Tests/OOXMLSwiftTests/UpdateAllFieldsTests.swift` — new, ~10 cases (single SEQ, mixed SEQ identifiers, STYLEREF + SEQ combination, chapter reset).
  - `mcp/che-word-mcp/Tests/CheWordMCPTests/CaptionCRUDTests.swift` + `EquationCRUDTests.swift` + `UpdateAllFieldsTests.swift` — integration tests against fixture docx.
- **Dependencies**: No new external deps (XMLParser is Foundation, already used throughout ooxml-swift).
- **Versions**: ooxml-swift `0.9.x` → `0.10.0` (minor bump — additive protocol extensions, new opaque enum case, new public API). che-word-mcp `3.0.0` → `3.1.0` (minor bump — additive MCP tools, no breaking schema changes).
- **Issues closed on landing**: #17 (fully — 4 caption CRUD tools), #19 (fully — `update_all_fields`), #21 (fully — 4 equation CRUD tools).
