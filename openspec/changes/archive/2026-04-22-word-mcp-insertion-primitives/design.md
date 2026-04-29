# Design — word-mcp-insertion-primitives

## Context

Four GitHub issues (PsychQuant/che-word-mcp #6, #7, #8, #9) report independent failures in che-word-mcp's write-side MCP tools. Root-cause analysis in each issue's `## Diagnosis` comment surfaces a shared pattern: the tools bypass ooxml-swift's existing abstractions and use ad-hoc string manipulation.

Relevant existing code:

| File | Current state |
|------|---------------|
| `Field.swift:506-534` | Already defines `FieldCode` protocol with a `toFieldXML()` default that emits correct `<w:fldChar>` begin/separate/end structure. `IFField` and TOC use it. `SequenceField` / `StyleRefField` / `RefField` do not exist. |
| `Field.swift:290-370` | `insertEquation()` does `replacingOccurrences(of: "\\frac{", with: "(")` — flat string substitution producing `<m:r><m:t>processed_string</m:t></m:r>`. No AST. |
| `Document.swift:150-194` | `replaceText()` iterates `body.children` covering `.paragraph` and `.table` (tables added in v0.5.5 / commit `fe13374`). Internal `replaceInParagraph` still uses per-run `contains(find)`, so cross-run matches fail. Headers/footers/footnotes/endnotes never reached. |
| `Server.swift:8663-8712` | `insertCaption()` builds `"{ SEQ \(label) \\* ARABIC }"` as a Swift String and hands it to `Paragraph(text:)`. Word renders the literal characters. `validLabels = ["Figure", "Table", "Equation"]` rejects Chinese. |
| `Server.swift:5514` | `insertImageFromPath()` requires both `width` and `height` params; no format detection, no PDF path, no table-cell insert location. |
| `Footer.swift:113-117`, `Header.swift:85-89` | PAGE field **does** use the correct `<w:fldChar>` structure — confirms the pattern works; `insertCaption` just didn't follow it. |

Constraints:

- macOS 14+, Swift 5.9+ (macdoc CLAUDE.md platform requirements).
- ooxml-swift is currently consumed via `url:` remote dep by che-word-mcp and several other packages; bumping to 0.8.0 requires all consumers to follow.
- che-word-mcp is distributed through `psychquant-claude-plugins` marketplace — see `common-release-flow.md`: any binary-level release must sync the plugin marketplace.
- No external code depends on the broken behaviors (verified by diagnosis: `insertCaption` never produced valid output, so no workflow can have been relying on it).

## Goals and Non-Goals

**Goals:**

1. `insert_caption` produces a real `<w:fldChar>` SEQ field that Word auto-numbers on F9.
2. `insert_caption` accepts Chinese identifiers (`圖`, `表`, `公式`) and anchors via `after_image_id` / `after_table_index` (not only `paragraph_index`).
3. `replace_text` matches across run boundaries (primary failure mode in thesis workflows).
4. `replace_text` reaches headers, footers, footnotes, endnotes when `scope: "all"`.
5. `insert_image_from_path` auto-computes missing dimension from the image's native aspect; supports insertion into table cells.
6. `insert_equation` emits structurally correct OMML for a defined subset (via the `components:` parameter path).
7. ooxml-swift exposes reusable Layer 1 primitives (`FieldCode` extensions, `MathComponent`, `TextReplacementEngine`, `ImageDimensions`, `InsertLocation`) that future write-side tools can rely on.

**Non-Goals (explicitly out of scope):**

1. **Full LaTeX parser** — only a pseudo-LaTeX subset (`\frac{}{}`, `_{}`, `^{}`, `\sqrt{}`, Greek letters, fixed operator list) is documented for `insert_equation(latex:)`. The recommended path is `components:`. A real parser is a separate change.
2. **PDF image ingestion** — needs a CoreGraphics renderer. Deferred.
3. **Caption CRUD tools** (`list_captions`, `get_caption`, `update_caption`, `delete_caption`, `update_all_fields`) — require a field parser that reads existing `<w:fldChar>` spans back out to typed values. Deferred.
4. **Caption style guarantee** — we do not create the `"Caption"` style if absent; we tag the paragraph with `pStyle="Caption"` and rely on the target document having it. A `styleOverride:` param is introduced but filling in style definitions is out of scope.
5. **Text anchor for `insert_image_from_path`** (find a phrase, insert next to it) — separate workflow from position-based insertion; deferred.
6. **Image alignment / wrap** (inline vs anchored, center, behind-text) — deferred; all images remain inline.
7. **`update_all_fields` Ctrl-F9 equivalent** — out of scope; users open the .docx in Word and press F9 themselves. MCP-side field recalculation is a Phase 2 capability.
8. **Revision-tracking compatibility** — if `replace_text` runs inside a document with tracked changes enabled, the rewrite is applied as a plain edit (not as a `<w:ins>` / `<w:del>` pair). Proper revision-tracked replacement is a follow-up that should modify `docx-revision-parsing`'s write-side counterpart.

## Decisions

### Extend existing `FieldCode` protocol; do not introduce a new `FieldBuilder`

`Field.swift` already has a protocol with the exact shape needed:

```swift
public protocol FieldCode {
    var fieldInstruction: String { get }
    var cachedResult: String? { get }
}
extension FieldCode {
    func toFieldXML() -> String { ... } // emits <w:fldChar> structure
}
```

The initial diagnosis for #9 suggested a new `FieldBuilder` struct. That is duplicate abstraction. We add three new conformances (`SequenceField`, `StyleRefField`, `RefField`) and `insertCaption()` in the MCP tool assembles the run sequence from those.

**Rationale**: `FieldCode.toFieldXML()` already produces the correct five-run structure (begin → instrText → separate → cached → end). Adding a parallel abstraction would split "how to write fields" across two places. `IFField` already follows this pattern; the new field types do the same.

**Alternative considered**: Ad-hoc per-tool builder (status quo for `insertCaption`). Rejected — produces broken output and duplicates the `<w:fldChar>` XML for each field type added later.

### Merge 4 issues into one change with a two-capability spec split

Issues #6/#7/#8/#9 each describe a surface-level bug but share architectural voids. A single change creates cohesive Layer 1 primitives.

Specs split by layer:

- `ooxml-content-insertion-primitives` — Layer 1, in the `ooxml-swift` package. Pure data/algorithm; no MCP coupling.
- `che-word-mcp-insertion-tools` — Layer 4, in the `che-word-mcp` MCP server. Consumes Layer 1.

**Rationale**: Existing specs (e.g. `docx-container-parsing` vs `word-mcp-markdown-export`) already follow this layer-per-spec convention. It also means Layer 1 tasks can be completed and published (ooxml-swift 0.8.0 tag) before Layer 4 starts, giving a clean internal release.

**Alternative considered**: Four separate changes, one per issue. Rejected — each would reinvent a partial abstraction, and the architectural deduplication we need (`FieldCode` extensions, flatten-map, InsertLocation) would land in four different places.

### `replaceText` uses flatten-then-map for cross-run correctness

Algorithm:

1. Given `paragraph.runs`, build `(flatString: String, offsetMap: [(runIdx: Int, charIdx: String.Index)])`. Each character in `flatString` maps to a specific `(runIdx, charIdx)` pair.
2. Find occurrences in `flatString` (via `.range(of:)` for plain, or `NSRegularExpression` for regex).
3. For each match, compute the splice plan: start run + start offset, end run + end offset. Produce a new run sequence where:
   - Runs before the match are preserved.
   - The start run is split (prefix kept) and the replacement text takes on the **start run's formatting**.
   - Runs strictly between start and end are deleted.
   - The end run is split (suffix kept).
   - Runs after are preserved.
4. Return number of matches replaced.

**Rationale**: This is the only algorithm that preserves run formatting at the edges of a match while correctly handling cross-run matches. Alternatives like "merge all runs into one, lose formatting" are unacceptable (breaks bold/italic across the match).

**Alternative considered**: Normalize-runs-first (merge adjacent runs with identical properties before matching). Rejected — doesn't help when different properties sit at the match boundary, which is the common case (English + LaTeX math, tracked-changes phantom empty run).

### `ReplaceOptions.scope` is an enum, not booleans

```swift
public enum ReplaceScope {
    case bodyAndTables       // matches current behavior (default)
    case all                 // + headers, footers, footnotes, endnotes
}
```

**Rationale**: Adding `includeHeaders: Bool`, `includeFooters: Bool`, etc. balloons the API surface. `.all` covers all write-addressable text containers. If users need finer control later, the enum can grow cases (`.allExceptFootnotes`, etc.) without breaking existing callers.

**Alternative considered**: Boolean flags. Rejected — combinatorial API that also makes the common case (all-or-nothing) verbose.

### `InsertLocation` enum covers the four anchor types

```swift
public enum InsertLocation {
    case paragraphIndex(Int)
    case afterImageId(String)          // rId from insert_image return value
    case afterTableIndex(Int)
    case intoTableCell(tableIndex: Int, row: Int, col: Int)
}
```

Used by `Document.insertImage(at:)` and by `insertCaption`'s "put caption above/below the referenced object" logic.

**Rationale**: All four tools share the same four anchor types. A single tagged union means one switch in the Document-level implementation; adding a fifth anchor later (e.g. bookmark-based) is one case add.

**Alternative considered**: Three optional parameters (`paragraphIndex: Int?`, `afterImageId: String?`, `afterTableIndex: Int?`) with a runtime check that exactly one is set. Rejected — the "exactly one" invariant is expressed weakly at runtime; the enum expresses it in the type system.

### `insert_equation` JSON shape: prefer `components:` over `latex:`

`components:` is the primary contract. Shape:

```json
{
  "type": "fraction",
  "numerator": [{"type": "run", "text": "a"}],
  "denominator": [
    {"type": "run", "text": "b + "},
    {"type": "subSuperScript", "base": [{"type": "run", "text": "c"}],
     "sup": [{"type": "run", "text": "2"}]}
  ]
}
```

Top level is a single `MathComponent`. `type` discriminator picks the Swift type. Nested `[MathComponent]` accepts arrays (runs of content).

`latex:` remains as an escape hatch but is documented with a strict subset grammar:

```
<expr>     ::= <atom> | <expr><atom>
<atom>     ::= <char> | "\frac{" <expr> "}{" <expr> "}"
             | "\sqrt{" <expr> "}" | "_{" <expr> "}"
             | "^{" <expr> "}" | "\alpha" | "\beta" | ... | "\sum"
```

**Rationale**: LLMs (which call MCP tools) can construct `components:` reliably from a math problem description. Parsing LaTeX correctly requires handling arbitrary TeX macros, which is an iceberg. By exposing `components:` as the primary path, we make the correct-OMML case easy and keep the LaTeX subset as a fallback.

**Alternative considered**: Only `latex:`, with best-effort parsing. Rejected — silent failure on unsupported syntax is worse than an up-front "here's the subset" statement. Users would discover holes at render time.

### Breaking changes are acknowledged, not hidden

- ooxml-swift: bump `0.7.x` → `0.8.0`. `Document.replaceText()` signature changes (adds `ReplaceOptions` — default value preserves behavior, but the old `(find:with:all:)` overload is removed). `insertImage()` signature changes to accept `InsertLocation`. Listed in CHANGELOG.
- che-word-mcp: bump minor (`v1.x` → `v2.0` when merging; maintainer may defer to `v1.next`). `insert_caption`, `insert_equation`, `insert_image_from_path`, `replace_text` MCP tool argument schemas change. Listed in CHANGELOG with explicit migration notes.

**Rationale**: No working user code depends on the broken behaviors (captions with literal characters, per-run match failures, width+height mandate). Cleaning the APIs now costs less than maintaining backcompat shims.

**Alternative considered**: Add new tool names (`insert_caption_v2`, `replace_text_v2`). Rejected — forks documentation, confuses new users, and the broken tools still exist.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Caption style does not exist in the target .docx; captions render in default paragraph style | Document the assumption; introduce `styleOverride:` param (not required for Phase 1 proper, but leave the argument slot so we do not break the API when we add style injection in Phase 2). |
| Chinese `SEQ` identifier triggers historical Word bugs (Word 2007-era) | Phase 1 validation target is Word 2016+. `tests/e2e/` opens the written .docx in (headless?) Word and asserts F9 updates correctly. If 2016+ breaks, fall back to ASCII-transliterated identifier (`SEQ tu` for `圖`) with the Chinese label still visible in text. |
| `flatten-then-map` replacement loses run properties when the replacement spans runs with different formatting | By design: replacement inherits start-run properties. Document this explicitly. If users need otherwise, they should replace within a single formatting region. |
| `.all` scope performance regression on large docs | Benchmark with a 200-page thesis fixture before merging. If >2× slowdown vs `.bodyAndTables`, lazy-traverse header/footer/footnote parts only when their text contains the first character of `find`. |
| MCP JSON `components:` argument verbosity — math with 20 nested fractions produces a huge tree | Accept; it's a known trade-off of structural correctness over textual convenience. If users complain, Phase 2 LaTeX parser lifts the burden. |
| `insert_equation(latex:)` subset users hit the grammar wall | Make the documented subset explicit in the tool's `inputSchema` description with a literal grammar block. Tool returns a clear error message naming the first unrecognized token. |
| Revision-tracking is on when `replace_text` runs | For Phase 1, we silently edit without producing `<w:ins>` / `<w:del>`. Document this. A follow-up change in the `docx-revision-parsing` capability can add revision-tracked rewrite later. |
| ooxml-swift 0.8.0 breaks other consumers (word-to-md-swift, marker-word-converter-swift) | Before tagging 0.8.0, run `swift build` in each consuming package. Any that break must be updated in the same release wave. |

## Migration Plan

1. Land all Layer 1 (ooxml-swift) tasks first. Tag `ooxml-swift v0.8.0` with CHANGELOG entry listing `FieldCode` additions, `replaceText` signature change, new `InsertLocation`, new `MathComponent`.
2. Bump che-word-mcp's `Package.swift` dep to `from: "0.8.0"`.
3. Rewrite the four Server.swift tools in dependency order: `replaceText` → `insertImageFromPath` → `insertCaption` → `insertEquation`. Each is a separate commit referencing the relevant issue (e.g. `fix: insert_caption now produces real SEQ fields (#9)`).
4. After all four tools are rewritten, tag che-word-mcp `v2.0.0`.
5. Follow `common-release-flow.md` post-release chain: `/plugin-update psychquant-claude-plugins` to sync the marketplace.
6. Close issues #7 fully, #9 partial (Phase 1-3), #8 partial (Gaps A+D), #6 partial (Phase 1-2). Each closing comment links back to this change's archive location.

**Rollback:**

- ooxml-swift: users pin to `0.7.x` if they need the old `replaceText` signature. Our forks internal to macdoc are updated as part of step 4, so nothing internal is left behind.
- che-word-mcp: users pin to `v1.x` plugin version. The marketplace honors pinned versions.

## Open Questions

1. **Caption style source**: Do we embed a baseline `"Caption"` style definition into the document when absent, or rely on the target having it? Current plan: rely on target, emit at `pStyle="Caption"`, no style injection. If Phase 1 testing with a minimal-style fixture renders poorly, revisit.
2. **`ImageDimensions` format coverage**: Phase 1 covers PNG (IHDR read), JPEG (SOF segment read). EMF/WMF metafile headers are documented by ECMA but uncommon in the thesis workflow. Include in Phase 1 or defer to Phase 2?
3. **Regex flavor for `replace_text`**: Swift's `NSRegularExpression` (ICU) is the natural fit; however, if users come from an ECMAScript regex background, some features (lookbehind width) differ. Document which flavor; no flavor translation layer.
4. **Where does `escapeXMLForField` live when reused by `SequenceField`/`StyleRefField`**? Currently private to `FieldCode` extension in `Field.swift`. Promote to `internal` / `OOXMLSwift.XMLEscape` helper module, or duplicate? Current plan: extract to `internal enum XMLEscape` on first reuse.

## References

- ECMA-376 Part 1 §17.16 (Fields) and §22.1 (OMML, math).
- `docx` (dolanmiu/docx) 9.6.x: `SequentialIdentifier`, `MathFraction`, `MathRun` — reference API surface.
- `PsychQuant/che-word-mcp` issues #6, #7, #8, #9 diagnosis comments.
- `openspec/specs/docx-container-parsing/spec.md` — write-side counterpart to our `.all`-scope traversal requirement.
- `openspec/specs/word-mcp-markdown-export/spec.md` — MCP tool spec convention (`summarize:` parameter).
