## Why

che-word-mcp has four insert/modify-text tools (`insert_caption`, `insert_equation`, `insert_image_from_path`, `replace_text`) that bypass ooxml-swift's existing abstractions (e.g. `FieldCode` protocol) and instead use string concatenation or hardcoded paragraph-index addressing. Each is broken in a distinct way, but the root cause is shared: the Layer 1 primitives they should rely on either do not exist or are not reused:

- `insert_caption` writes literal `{ SEQ Figure \* ARABIC }` characters into the .docx instead of a real `<w:fldChar>` field — auto-numbering is dead (issue #9, critical).
- `replace_text` uses per-run `contains(find)` and scans only body paragraphs + tables — cross-run matches fail, and headers/footers/footnotes/endnotes are never reached (issue #7, critical).
- `insert_image_from_path` requires explicit width+height, has no PDF support, and cannot insert into a table cell (issue #8).
- `insert_equation` does LaTeX → OMML by `replacingOccurrences(of:)` — it produces a flat `<m:r><m:t>` tree that Word renders as plain text, not math (issue #6).

Fixing these individually would keep accreting one-off helpers in `ooxml-swift/Models/*` and `Server.swift`. Consolidating into a single shared set of Layer 1 primitives (field codes, math AST, replacement engine, image dimensions, insert location) is the minimum architecturally coherent response.

## What Changes

### Layer 1 primitives (ooxml-swift)

- **BREAKING** `FieldCode` protocol gets new conformances in `Field.swift`: `SequenceField` (SEQ, for captions), `StyleRefField` (chapter number in caption), `RefField` (cross-references). Replaces the string-concatenation path in `insertCaption()` (Refs #9).
- **NEW** `MathComponent` protocol + nine core types (`MathRun`, `MathFraction`, `MathRadical`, `MathSubSuperScript`, `MathNary`, `MathDelimiter`, `MathFunction`, `MathLimit`, `MathMatrix`), each with a `toOMML() -> String` emitter. Replaces `Field.swift:290-370` string substitution (Refs #6).
- **BREAKING** `Document.replaceText()` is rewritten with a flatten-then-map algorithm (paragraph runs → single string with offset map → find range → splice back preserving run boundaries). A new `ReplaceOptions` struct exposes `scope: .bodyAndTables | .all`, `regex: Bool`, `matchCase: Bool`. `.all` scope covers body, tables, headers, footers, footnotes, endnotes (Refs #7).
- **NEW** `ImageDimensions.detect(path:)` for PNG/JPEG/EMF format detection (PDF deferred), and `InsertLocation` enum (`.paragraphIndex(Int)`, `.afterImageId(String)`, `.afterTableIndex(Int)`, `.intoTableCell(tableIndex: Int, row: Int, col: Int)`). `Document.insertImage(at:)` accepts `InsertLocation` (Refs #8 Gaps A+D).

### Layer 4 MCP API (che-word-mcp)

- **BREAKING** `insert_caption` accepts Chinese labels (`"圖"` / `"表"` / `"公式"`) in addition to `Figure` / `Table` / `Equation`, and accepts any of `paragraph_index` / `after_image_id` / `after_table_index` as the anchor. Caption output is now a real SEQ field (round-trip verified in Word by opening the written .docx) (Refs #9).
- **BREAKING** `insert_equation` accepts a new `components:` argument shaped as a JSON tree matching `MathComponent` — produces correct OMML. The existing `latex:` argument is retained as an escape hatch but is explicitly documented as supporting only a narrow pseudo-LaTeX subset: fractions (`\frac`), sub/superscripts (`_{}` / `^{}`), radicals (`\sqrt{}`), Greek letters, and a fixed operator list. A true LaTeX parser is deferred (Refs #6 Phase 1-2).
- `insert_image_from_path` defaults to `auto_aspect: true` (one of width / height auto-computed via `ImageDimensions`), and adds `into_table_cell: { table_index, row, col }` for table-cell insertion (Refs #8 Gaps A+D).
- `replace_text` adds `scope: "body" | "all"` (default `"body"` for backwards compat, `"all"` scans headers/footers/footnotes/endnotes) and `regex: Bool` (default `false`). The underlying cross-run match is applied universally — no per-run fallback (Refs #7).

### Explicit Phase 2 scope (deferred to a later change)

- LaTeX parser for full LaTeX syntax support (`insert_equation(latex:)` beyond the documented subset) — Refs #6 Phase 3.
- PDF image ingestion in `insert_image_from_path` (requires CoreGraphics renderer) — Refs #8 Gap B.
- Caption CRUD tools: `list_captions`, `get_caption`, `update_caption`, `delete_caption`, `update_all_fields` (requires field parser) — Refs #9 Phase 4-5.
- `insert_image_from_path` text anchor (Gap C) and alignment/wrap (Gap E) — Refs #8.

## Non-Goals

(Captured in `design.md` — scope exclusions and rejected approaches live there.)

## Capabilities

### New Capabilities

- `ooxml-content-insertion-primitives`: Layer 1 abstractions for authoring OOXML content in `ooxml-swift` — field codes (SEQ, StyleRef, Ref conforming to `FieldCode`), math AST (`MathComponent` types with `toOMML()`), text replacement engine (flatten-map algorithm with scope-aware traversal across body/table/header/footer/footnote/endnote, regex support), image dimensions detection, and insert-location abstraction (`InsertLocation` covering paragraph index / after-image / after-table / into-table-cell).

- `che-word-mcp-insertion-tools`: Layer 4 MCP tools (`insert_caption`, `insert_equation`, `insert_image_from_path`, `replace_text`) in `che-word-mcp` built on the Layer 1 primitives. Produces valid OOXML (fields, math, cross-run-safe text splicing), accepts Chinese labels, supports auto-aspect images and table-cell insertion, and exposes scope/regex options on text replacement.

### Modified Capabilities

*(none — this change is exclusively on the write-side. Existing read-side capabilities remain unchanged.)*

## Impact

- **Affected specs**: 2 new (listed above). No existing specs modified.
- **Affected code**:
  - `packages/ooxml-swift/Sources/OOXMLSwift/Models/Field.swift` — extend `FieldCode` with `SequenceField`, `StyleRefField`, `RefField`.
  - `packages/ooxml-swift/Sources/OOXMLSwift/Models/MathComponent.swift` — new file (~300 lines).
  - `packages/ooxml-swift/Sources/OOXMLSwift/Models/TextReplacementEngine.swift` — new file (flatten-map + scope traversal).
  - `packages/ooxml-swift/Sources/OOXMLSwift/Models/ImageDimensions.swift` — new file.
  - `packages/ooxml-swift/Sources/OOXMLSwift/Models/InsertLocation.swift` — new file.
  - `packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift` — rewrite `replaceText` / `replaceInParagraph`, add header/footer/footnote/endnote traversal, add `insertImage(at: InsertLocation)`.
  - `mcp/che-word-mcp/Sources/CheWordMCP/Server.swift` — rewrite `insertCaption()`, `insertEquation()`, `insertImageFromPath()`, `replaceText()` implementations.
- **Tests**:
  - `packages/ooxml-swift/Tests/OOXMLSwiftTests/` — new test files for each new primitive.
  - `mcp/che-word-mcp/Tests/CheWordMCPTests/` — integration tests using fixtures in `test-files/` (XCSkip if absent, per the project convention from #81).
- **Dependencies**: ooxml-swift `0.7.x` → `0.8.0` bump (breaking `FieldCode`/`replaceText` API changes). che-word-mcp Package.swift `from:` updated accordingly and tagged `v2.x.0`.
- **APIs**: che-word-mcp MCP tool signatures change. Documented BREAKING in both repos' CHANGELOG.
- **Issues closed on landing**: #6 (partial — Phase 1+2 only), #7 (fully), #8 (Gaps A+D only), #9 (Phase 1-3 — core bug + Chinese label + after_image/table anchor).
