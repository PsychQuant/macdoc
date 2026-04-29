# Tasks — word-mcp-insertion-primitives

## 1. Layer 1 — FieldCode extensions (ooxml-swift)

- [x] 1.1 Add `StyleRefField` struct conforming to `FieldCode` in `packages/ooxml-swift/Sources/OOXMLSwift/Models/Field.swift`. **Existing code survey**: `SequenceField` (line 912) and `ReferenceField` (line 866) already satisfy their respective spec requirements (SequenceField emits valid OOXML SEQ field XML and ReferenceField emits valid OOXML reference field XML) — no new code needed for those, just verification tests in 1.2. Only StyleRefField is newly added — applies the Extend existing `FieldCode` protocol; do not introduce a new `FieldBuilder` decision; covers the StyleRefField emits valid OOXML STYLEREF field XML requirement (Refs #9)
- [x] 1.2 Write XCTest cases for `StyleRefField` (new), plus verification tests for existing `SequenceField` and `ReferenceField` covering ASCII identifiers, Chinese identifiers (`圖`, `表`, `公式`), and chapter-reset paths (TDD: write all three test cases first, confirm only StyleRefField case is RED, land 1.1, then all green)

## 2. Layer 1 — Math AST (ooxml-swift)

- [x] 2.1 [P] Add `MathComponent` protocol (requires `toOMML() -> String`) plus core types `MathRun`, `MathFraction`, `MathSubSuperScript`, `MathRadical` in new `packages/ooxml-swift/Sources/OOXMLSwift/Models/MathComponent.swift`. The existing broken `MathEquation.toXML()` at `Field.swift:294-363` (the one referenced in #6 diagnosis — it does `replacingOccurrences(of: "\\frac{", with: "(")`) MUST be annotated `@available(*, deprecated, message: "Use MathComponent AST; MathEquation will be removed in ooxml-swift 1.0")` so new code is steered toward the AST — covers the MathComponent protocol requires toOMML emission and Core math components emit valid OMML requirements (Refs #6)
- [x] 2.2 Add advanced math types `MathNary`, `MathDelimiter`, `MathFunction`, `MathLimit`, `MathMatrix` to the same file with correct OMML emission — covers the N-ary and delimiter math components emit valid OMML requirement (Refs #6)
- [x] 2.3 Write XCTest cases for all nine `MathComponent` types including nested composition (e.g. fraction inside radical, subscript on n-ary bounds)

## 3. Layer 1 — Text replacement engine (ooxml-swift)

- [x] 3.1 [P] Implement `TextReplacementEngine` (`flattenRuns`, `reconstructRuns`) plus `ReplaceOptions` struct (`scope: ReplaceScope` enum, `regex: Bool`) in new `packages/ooxml-swift/Sources/OOXMLSwift/Models/TextReplacementEngine.swift` — applies the `replaceText` uses flatten-then-map for cross-run correctness and `ReplaceOptions.scope` is an enum, not booleans decisions; covers the TextReplacementEngine uses flatten-then-map algorithm and TextReplacementEngine supports scope and regex options requirements (Refs #7)
- [x] 3.2 Rewrite `Document.replaceText(find:with:options:)` in `packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift` to delegate to `TextReplacementEngine` and traverse body, table cells, headers, footers, footnotes, endnotes when `options.scope == .all` — covers the Document.replaceText scope .all traverses all text containers requirement (Refs #7)
- [x] 3.3 Write XCTest cases for cross-run match across three runs, replacement inheriting start-run formatting, scope-all traversal hitting header and footnote, regex with capture-group backreference

## 4. Layer 1 — Image dimensions + insert location (ooxml-swift)

- [x] 4.1 [P] Implement `ImageDimensions.detect(path:)` reading PNG IHDR (bytes 16-23) and JPEG SOF0/SOF2 segments in new `packages/ooxml-swift/Sources/OOXMLSwift/Models/ImageDimensions.swift`, throwing `ImageDimensionsError.unsupportedFormat` for other extensions — covers the ImageDimensions detects PNG and JPEG native dimensions requirement (Refs #8)
- [x] 4.2 Add `InsertLocation` enum in new `packages/ooxml-swift/Sources/OOXMLSwift/Models/InsertLocation.swift` and extend `Document.insertImage(at:relationshipId:dimensions:)` and `Document.insertParagraph(at:paragraph:)` to accept it — applies the `InsertLocation` enum covers the four anchor types decision; covers the InsertLocation enum covers four anchor types requirement (Refs #8)
- [x] 4.3 Write XCTest cases for PNG 800×600 IHDR read, JPEG SOF read, `unsupportedFormat` error on `.tiff`, and all four `InsertLocation` resolution paths including table-cell insertion and `afterImageId` with unknown rId

## 5. Layer 1 — Downstream verification + release (ooxml-swift)

- [x] 5.1 Run `swift test` in `packages/ooxml-swift/`; run `swift build` in every consumer package (`word-to-md-swift`, `marker-word-converter-swift`, `mcp/che-word-mcp`, and any others listed in macdoc CLAUDE.md) to confirm the BREAKING signature changes do not produce unresolved compile errors — applies the Merge 4 issues into one change with a two-capability spec split migration plan
- [x] 5.2 Update `packages/ooxml-swift/CHANGELOG.md` with a `0.8.0` entry listing BREAKING signature changes (`replaceText`, `insertImage`), new public types, and migration snippets; tag `v0.8.0`; push tag and create GitHub release — applies the Breaking changes are acknowledged, not hidden decision

## 6. Layer 4 — che-word-mcp tool rewrites

- [x] 6.1 Bump `mcp/che-word-mcp/Package.swift` ooxml-swift dep to `from: "0.8.0"` and confirm `swift build` succeeds (interim: path: deps for coordinated release; switch to url: v0.8.0 in task 7.x)
- [x] 6.2 Rewrite `insertCaption()` in `mcp/che-word-mcp/Sources/CheWordMCP/Server.swift` to: (a) accept the six-value label set, (b) assemble runs from `SequenceField` + `StyleRefField` (when `include_chapter_number`), (c) resolve `paragraph_index` / `after_image_id` / `after_table_index` via `InsertLocation` — covers the insert_caption accepts Chinese and English labels, insert_caption produces real SEQ field XML, and insert_caption accepts three anchor types requirements (Refs #9)
- [x] 6.3 Rewrite `insertEquation()` in Server.swift to accept `components:` as primary path (JSON tree → `MathComponent` tree → OMML) and `latex:` as the documented-subset fallback with an unambiguous unrecognized-token error — applies the `insert_equation` JSON shape: prefer `components:` over `latex:` decision; covers the insert_equation components produces valid OMML and insert_equation latex fallback supports documented subset requirements (Refs #6)
- [x] 6.4 Rewrite `insertImageFromPath()` in Server.swift to default `auto_aspect: true` (call `ImageDimensions.detect` when only one of width/height is given or when neither is given) and accept `into_table_cell: { table_index, row, col }` mapping to `InsertLocation.intoTableCell` — covers the insert_image_from_path computes missing dimension from aspect and insert_image_from_path supports table-cell insertion requirements (Refs #8)
- [x] 6.5 Rewrite `replaceText()` MCP tool in Server.swift to accept `scope: "body" | "all"` (default `"body"`) and `regex: Bool` (default `false`), passing options through to `Document.replaceText` via `ReplaceOptions` — covers the replace_text defaults scope to body, replace_text matches across run boundaries, and replace_text supports regex option requirements (Refs #7)

## 7. Layer 4 — Testing, schemas, release, issue closure

- [~] 7.1 Add XCTest cases in `mcp/che-word-mcp/Tests/CheWordMCPTests/` for each rewritten tool (happy path + at least one BREAKING migration example per tool); update each tool's `inputSchema` description string with a BREAKING note plus migration hint — covers the MCP tool schemas document BREAKING changes requirement. **Partial**: BREAKING notices captured in CHANGELOG 2.0.0; inline inputSchema description updates and integration tests deferred to follow-up (need Word round-trip fixtures).
- [x] 7.2 Update `mcp/che-word-mcp/CHANGELOG.md` with a BREAKING section listing each of the four tools with migration notes
- [x] 7.3 Tag `mcp/che-word-mcp` as `v2.0.0`, push tag and create GitHub release (include CHANGELOG excerpt in release notes)
- [x] 7.4 Run `/plugin-tools:plugin-update che-word-mcp` to sync `psychquant-claude-plugins` marketplace per `common-release-flow.md` post-release mandatory chain. Done: built release binary (`swift build -c release`), created GitHub release v2.0.0 + uploaded `CheWordMCP` asset (caught missing release during Phase 1.5 auto-sync), bumped plugin.json + marketplace.json 1.17.0 → 2.0.0, pushed to marketplace, ran `claude plugin update` — local install now at v2.0.0.
- [x] 7.5 Close issues #6 (Phase 1-2 only, note Phase 3 LaTeX parser deferred), #7 (fully resolved), #8 (Gaps A+D only, note Gaps B/C/E deferred), #9 (Phase 1-3 only, note Phase 4-5 CRUD deferred) with comments linking to `openspec/changes/archive/<date>-word-mcp-insertion-primitives/` — auto-closed via commit `Closes` trailer + retroactive Closing Summary comments posted
