# Design — word-mcp-readback-primitives

## Context

v2.0.0 shipped a clean write-side for OOXML fields and math via ooxml-swift:

- **Fields**: `FieldCode` protocol + `toFieldXML()` default that emits the 5-run `<w:fldChar>` structure. Concrete types: `SequenceField`, `StyleRefField`, `ReferenceField`, `IFField`, `CalculationField`, `DateTimeField`, `DocumentInfoField`, `MergeField`.
- **Math**: `MathComponent` protocol + 9 concrete types (`MathRun`, `MathFraction`, `MathSubSuperScript`, `MathRadical`, `MathNary`, `MathDelimiter`, `MathFunction`, `MathLimit`, `MathMatrix`) each with a `toOMML()` emitter.

But there is no inverse. Once written, these structures are opaque strings inside `Run.rawXML`. che-word-mcp tools can create but not enumerate them. Issues #17 / #19 / #21 are symptoms of the same architectural gap.

Relevant existing code:

| Location | Current state |
|----------|---------------|
| `Field.swift:506-534` | `FieldCode` protocol + `toFieldXML()` emits `<w:r><w:fldChar begin/><w:instrText>...</w:instrText><w:fldChar separate/><w:t>cached</w:t><w:fldChar end/></w:r>` |
| `Field.swift` — `SequenceField`, `StyleRefField`, etc. | Each has `fieldInstruction: String` getter (write side). No parser. |
| `MathComponent.swift` | 9 types, each `toOMML() -> String` (write side). No parser. |
| `Run.swift:9` | `public var rawXML: String?` is where field and math XML hides. |
| Server.swift `insertCaption` (v2.0+) | Writes `SequenceField` / `StyleRefField` as `Run.rawXML`. Cached result is always written as `"1"` (correct on F9). |
| Server.swift `insertEquation` (v2.0+) | Writes `<m:oMathPara><m:oMath>...</m:oMath></m:oMathPara>` as a single `Run.rawXML`. |

Constraints:

- Foundation's `XMLParser` is SAX-style (event callbacks). For nested structures it requires explicit stack management. ooxml-swift already uses this pattern in `DocxReader.parseParagraph` — the new parsers follow the same style for consistency.
- ooxml-swift is consumed by ~5 packages via `url:` deps. Adding a new opaque `MathComponent.unknownXML(String)` case is technically a breaking change for exhaustive `switch` consumers, but in practice all in-monorepo consumers do partial matches (e.g., `if let run = c as? MathRun`) so the risk is minimal.
- `updateAllFields` must traverse headers / footers / footnotes / endnotes in addition to body (v0.8.0's `replaceText(scope: .all)` established this traversal).

## Goals and Non-Goals

**Goals:**

1. `FieldParser` can parse every field type currently written by `FieldCode.toFieldXML()` back into the corresponding struct, losslessly round-tripping `write → read → write`.
2. `OMMLParser` can parse every `MathComponent` type currently written by `toOMML()` back into the corresponding type, losslessly round-tripping.
3. `WordDocument.updateAllFields()` correctly recomputes SEQ counters with scope reset semantics (`\s N` resets the counter at each heading level N).
4. Unknown field types (e.g., `TIME`, `USERNAME`) and unrecognized math subtrees are preserved as opaque cases, never dropped. Round-tripping a doc with unknown fields does not corrupt them.
5. che-word-mcp exposes 9 CRUD MCP tools that thinly wrap the parsers — each tool under 100 lines of handler code.

**Non-Goals (explicitly out of scope):**

1. **Field evaluation beyond SEQ counters.** `update_all_fields` will update `SEQ Figure`, `SEQ Table`, etc. It will NOT evaluate `IF`, `=` (formula), `DATE`, `TIME`, `PAGE`, `NUMPAGES`, or other runtime-dependent fields. Those fields' cached values stay as-written. Word updates them on F9; we only handle SEQ here because it's the caption dependency.
2. **Cross-reference field parsing depth.** `REF fig_returns \h` can parse back into `ReferenceField(bookmarkName: "fig_returns", createHyperlink: true)`, but we don't resolve the reference target — the cached result stays as whatever was written. Resolving targets requires a two-pass walker (first pass to collect bookmarks, second to resolve refs); deferred.
3. **OMML → LaTeX or MathML conversion.** Parsed `MathComponent` trees stay as Swift values. No export back to LaTeX; the v2.0.0 `insert_equation(latex:)` path's narrow LaTeX subset is write-only.
4. **Nested math in non-math runs.** `OMMLParser` expects to be handed an `<m:oMath>` XML string. Stray `<m:r>` inside a non-math paragraph is not our problem (that's a malformed docx).
5. **Backward-compat with 2.x caption writes that used literal character SEQ codes.** v2.0.0 fixed that bug — we don't try to recognize `"{ SEQ Figure \* ARABIC }"` literal text as a caption. Users on older docx need a one-time rewrite via manual edit.
6. **Performance optimization for documents with >1000 fields or equations.** Parser is O(N × field_text_length); on pathological inputs it may be slow. Deferred; no benchmarks suggest this is a real problem.
7. **Delta updates / incremental parsing.** Every `list_captions` call re-parses the whole doc. Caching is a separate concern, handled by che-word-mcp if needed later.
8. **Equation-level undo.** `update_equation` replaces the target in place; if the caller got the index wrong, they need to reopen the doc from disk. Protected by v3.0.0's `revert_to_disk`.

## Decisions

### XMLParser-based SAX parsers, not string scanning

Both `FieldParser` and `OMMLParser` use `Foundation.XMLParser` delegate callbacks with explicit stack management. Regex-based or string-split approaches would be faster to write but break on whitespace variation, nested subtrees, and CDATA.

**Rationale**: `DocxReader.parseParagraph` already uses this pattern for the rest of the docx body — staying consistent makes the parsers debuggable with the same mental model. The one-time cost of SAX boilerplate is paid back by correctness on real-world documents (we already saw string-substitution break in the broken `MathEquation.processLatex` path before v2.0.0).

**Alternative considered**: `XMLDocument` (tree model). Rejected because Foundation's `XMLDocument` is not available on all Swift platforms we support, and it allocates the entire tree in memory when we only need streaming.

### Each FieldCode type parses its own instrText grammar

Rather than a monolithic `FieldParser.parse(instrText: String) -> FieldCode?` that switches on leading token, each `FieldCode`-conforming type gets a `static func parse(instrText: String) -> Self?` that returns nil on non-match. `FieldParser` dispatches by trying each registered type in turn.

**Rationale**: Keeps each field type's parse logic next to its `fieldInstruction` getter (the two are inverse operations). Adding a new field type requires no change to `FieldParser` — just add conformance. This mirrors how `FieldCode` is already a protocol with per-type write logic.

**Alternative considered**: Central dispatch with a leading-token lookup table (`["SEQ": SequenceField.parse, "STYLEREF": ...]`). Rejected because some field instr text (e.g., `=` formula, `IF` with expressions) requires more than leading-token recognition; per-type parsers handle their own disambiguation.

### ParsedField is a struct with range info

`ParsedField` contains `{ startRunIdx: Int, endRunIdx: Int, cachedResultRunIdx: Int?, field: FieldCode, instrText: String }`. The `cachedResultRunIdx` points at the `<w:t>` run between `separate` and `end` that holds the displayed value. For `update_all_fields`, we modify this run's text in place.

**Rationale**: Knowing the exact run range matters for `update_caption`, `delete_caption`, `update_equation` — they need to find and modify specific runs, not full paragraphs. The `(startRunIdx, endRunIdx)` range also lets MCP tools do fine-grained replacement without touching surrounding paragraph text.

**Alternative considered**: Return only the parsed values without location. Rejected — the CRUD tools become impossible.

### Unknown fields and math stay as opaque cases

- `ParsedField.unknown(instrText: String, runRange: (Int, Int))` for any field type `FieldParser` doesn't recognize (e.g., `TIME \@ "hh:mm"`, custom MERGEFORMAT flags).
- `MathComponent.unknownXML(String)` for any `<m:...>` subtree `OMMLParser` doesn't recognize (e.g., `<m:box>`, `<m:borderBox>`, advanced accent marks).

Callers get full round-trip preservation — they can list unknown fields/equations, but update/delete only works on recognized ones.

**Rationale**: OOXML has long-tail features we don't support. Silently dropping them on round-trip corrupts documents. The opaque-case pattern matches what DocxReader already does for unrecognized paragraph-level elements.

**Trade-off**: Adding `unknownXML` to `MathComponent` is technically a source-breaking change for any exhaustive `switch` consumer. Acceptable because in-monorepo consumers use runtime `as?` checks, not exhaustive switches. Documented in CHANGELOG 0.10.0.

### updateAllFields implements SEQ only (Phase 1)

`WordDocument.updateAllFields()` walks all fields but only mutates SEQ field cached results. Other field types have their cached results preserved verbatim.

**Rationale**: SEQ is the only field type whose caching matters for the caption workflow (#19 is explicitly "F9-equivalent for captions"). IF / =formula / DATE / TIME evaluation opens a Pandora's box of runtime dependencies (current date? document properties? cross-references?). Phase 1 scope is the SEQ counters.

**Extension point**: The API returns `[String: Int]` (identifier → final counter value) so callers know which identifiers were updated. Adding more field types later is adding more branches in one method — no API change.

### Parser module lives under `ooxml-swift/Sources/OOXMLSwift/Parsing/`

New subdirectory for read-side parsers, separate from `Models/` (data types). `DocxReader.swift` stays as the top-level container reader; `FieldParser.swift` and `OMMLParser.swift` join it under a Parsing/ folder.

**Rationale**: `Models/` contains write-side structs + emitters. Putting parsers next to them (`Field.swift` containing both read AND write) would balloon the file. A dedicated `Parsing/` folder mirrors `Models/` and establishes a home for future read-side additions (e.g., revision parser extensions).

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Parser edge cases on real-world .docx produce `nil` returns that cascade up | Add `ParsedField.unknown` / `MathComponent.unknownXML` as fallbacks; 20+ test cases against fixture documents (Word-exported + pandoc-exported samples). |
| XML parsing is ~20× slower than string concat — large doc with 100+ fields could take >1s on `list_captions` | Document the O(N) cost in CHANGELOG; profile against a 200-page thesis fixture before merging; if >500ms, cache parsed fields on the `SessionState` from v3.0.0 (invalidate on any edit tool) |
| OMMLParser getting handed a Run with `rawXML` that is NOT `<m:oMath>` (could be SDT, content control, custom XML) | Return empty array + one `.unknownXML(rawXML)` — conservative. Document this. |
| `updateAllFields` SEQ reset on heading level 1 requires parsing `STYLEREF 1 \s` correctly — if we get it wrong, captions renumber wrong | Test with known thesis fixture having 4 chapters × 3 figures = 12 captions; assert final counters are `(1,1,1,1,2,2,2,3,3,3,4,4)` (3 per chapter when reset). |
| `MathComponent.unknownXML` addition is a source-breaking change for exhaustive switches | In practice no in-monorepo consumer does exhaustive switch on `MathComponent` (checked via grep); CHANGELOG 0.10.0 lists this. If a user hits it, they add a `default:` case. |
| Unknown field type (`TIME`, `MERGEFIELD`) in a doc being `update_all_fields`'d gets silently skipped | Document: only SEQ fields are updated. Unknown fields preserved verbatim. Return value `[String: Int]` enumerates which identifiers were touched. |
| Cross-run field spans (e.g., `fldChar begin` in run 3, `end` in run 7, with formatted text runs between) | `FieldParser` uses SAX over the paragraph's full flattened `rawXML` stream — it doesn't care about run boundaries. Emit `startRunIdx`/`endRunIdx` from the position in the stream. |

## Migration Plan

1. **ooxml-swift**: land `FieldParser.swift`, `OMMLParser.swift`, `FieldCode.parse(instrText:)` extensions, `MathComponent.unknownXML` case, `WordDocument.updateAllFields()`. Full `swift test` passes. Tag `v0.10.0`, push, create release.
2. **che-word-mcp**: bump `Package.swift` dep to `from: "0.10.0"`. Build and smoke-test.
3. Add 9 MCP tool schemas in Server.swift (new section block near insert_caption / insert_equation). Add 9 handlers.
4. Add integration tests (`CaptionCRUDTests.swift`, `EquationCRUDTests.swift`, `UpdateAllFieldsTests.swift`).
5. Full `swift test` passes. `mcpb/manifest.json` bump to `3.1.0`. Universal build + codesign. Rebuild `.mcpb`. Tag `v3.1.0`, push, create GitHub release with `CheWordMCP` + `che-word-mcp.mcpb` assets.
6. Plugin marketplace bump `plugin.json` + `marketplace.json` to `3.1.0`. Push + `claude plugin marketplace update` + `claude plugin update`.
7. Close issues #17, #19, #21 with Closing Summary comments referencing v3.1.0.

**Rollback**: users pin to che-word-mcp `3.0.x` via plugin marketplace pinning; wrapper version-aware auto-download (v2.0.1) honors pins. ooxml-swift 0.10.0 is additive, so 0.9.0 consumers keep working.

## Open Questions

1. Does `list_captions` return captions in document order (top-to-bottom) or indexed by SEQ counter (Figure 1, Figure 2, ...)? Current plan: document order by `paragraph_index`. The `sequence_number` is still returned so callers can sort.
2. When `update_caption(new_label)` changes the label (e.g., `Figure` → `Table`), should the SEQ counter restart or continue? Current plan: the new identifier starts at whatever its current max + 1 is in the rest of the doc (i.e., treats update as if the caller had inserted a new caption with the new label). Called out as a Non-Goal subtlety; may need follow-up.
3. `delete_equation` when the equation is the only content in a paragraph — remove the run or the whole paragraph? Current plan: remove the paragraph if it's now empty, else keep paragraph with remaining runs. Keeps doc structure tidy.
4. OMMLParser's handling of `<m:oMathPara>` wrapper — strip it and parse children as top-level `MathComponent`, or preserve `MathParagraph` wrapper type? Current plan: strip and treat children as math content; the `displayMode` flag is inferred from whether a wrapper was present.

## References

- PsychQuant/che-word-mcp issues #17, #19, #21 diagnosis comments (2026-04-22 batch).
- ECMA-376 Part 1 §17.16 (Fields) and §22.1 (OMML).
- Existing Spectra change `word-mcp-insertion-primitives` v2.0.0 — shipped the write-side primitives this change inverts.
- `v3.0.0` session-lifecycle — parallel-map pattern used here as well (no single-struct refactor).
