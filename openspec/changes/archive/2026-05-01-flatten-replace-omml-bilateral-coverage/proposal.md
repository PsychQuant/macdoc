## Why

`Paragraph.flattenedDisplayText()` and `Document.replaceInParagraphSurfaces` claim mirror invariant ("reading and writing operate on the same text universe") but both have a symmetric blind spot: direct-child OMML (`<m:oMath>` / `<m:oMathPara>` not wrapped in `<w:r>`) is silently dropped at 4 wrapper positions — `<w:p>`, `<w:hyperlink>`, `<mc:Fallback>`, and nested hyperlink/fldSimple combinations. This affects the most common Pandoc / Quarto / LaTeX→docx output (display math via `$$...$$` emits direct-child OMML), causing anchor lookups against paragraphs containing display math to silently 0-match and replacements crossing equation boundaries to behave inconsistently. Cluster fix tracked in che-word-mcp #99 / #100 / #101 / #102 / #103 surfaced from #92 verify findings.

This change resolves the cluster bilaterally (read AND write) and introduces two library-wide design principles that govern all current and future OOXML mutator behavior.

## What Changes

- **Read-side flatten** (`InsertLocation.swift:flattenedDisplayText`): walk direct-child OMML at all 4 wrapper positions in source XML order. Use existing `OMMLParser.parse(xml:)` to extract `visibleText`. No parser changes — `unrecognizedChildren` / `HyperlinkChild.rawXML` / `AlternateContent.rawXML` raw passthrough preserved.
- **Write-side replace** (`Document.swift:replaceInParagraphSurfaces`): walk direct-child OMML at all 4 wrapper positions for boundary detection. **BREAKING for `replace_text` MCP tool error semantics**: replacements crossing OMML boundaries refuse with new typed result `ReplaceResult.refusedDueToOMMLBoundary(occurrences:)` instead of returning silent `0`. Replacements wholly within `<w:t>` ranges proceed unchanged.
- **New ReplaceResult enum** (NEW public API, NEW `Sources/OOXMLSwift/Models/ReplaceResult.swift`): `.replaced(count:)` / `.refusedDueToOMMLBoundary(occurrences:)` with structured occurrence info `(matchSpan: Range<Int>, ommlSpans: [Range<Int>])` — informative refusal so callers can decide how to proceed.
- **Library design principles** (NEW capability spec): two foundational invariants — (1) *Correctness primacy* (refuse > incorrect approximation; bar = human-like correctness, not just structural OOXML validity); (2) *Human-like operations* (operations must correspond to conscious human Word user actions; no surprising intermediate state; no silent destruction). Future mutators MUST be measured against these.
- **Documentation refresh** (`InsertLocation.swift:264-266` docstring): tighten mirror description to reflect documented asymmetry — reads include OMML visibleText (anchor universe); writes treat OMML as opaque structural units.
- **Resolves che-word-mcp #99 / #100 / #101 / #102 / #103** as cluster.

## Non-Goals

- **Equation content mutation**: this change does NOT add the ability to edit text inside `<m:oMath>` (e.g., changing `δ` to `θ`). That requires a dedicated equation-editing tool with its own spec contract — out of scope, deferred to follow-up issue.
- **Destructive escape hatch (`omml_handling: "drop"` parameter)**: the principles allow explicit-destructive operations as long as the caller opts in. This change does NOT introduce that parameter — it ships principle-locked default refuse + informative result first; escape hatch lands as separate change after soak.
- **Typed field promotion**: direct-child OMML stays in `unrecognizedChildren` / `HyperlinkChild.rawXML` / `AlternateContent.rawXML` raw passthrough. NOT promoted to typed `Paragraph.directOMath: [DirectOMath]` or similar — keeps round-trip fidelity untouched, parser/writer unchanged.
- **Symmetric mirror invariant**: rejected. Read-write asymmetry is principle-driven feature: reads include OMML visibleText (accurate to what user sees); writes treat OMML as structural unit (accurate to what user can consciously edit). Not a gap to close.
- **Visitor protocol abstraction**: rejected. Lightweight module-private helper preferred over OOP protocol because 4 wrapper positions are OOXML schema-fixed (not extensible) — protocol would force Paragraph / Hyperlink / FieldSimple / AlternateContent to mutually depend, violating module structure for hypothetical "future 5th wrapper".

## Capabilities

### New Capabilities

- `ooxml-paragraph-text-mirror`: defines mirror invariant between `Paragraph.flattenedDisplayText()` and `Document.replaceInParagraphSurfaces` — surface coverage symmetry (same wrapper positions walked both directions) with documented asymmetry (read includes OMML visibleText; write treats OMML as opaque). Includes typed `ReplaceResult` informative refusal contract.
- `ooxml-library-design-principles`: foundational normative principles governing all `ooxml-swift` mutator design — Correctness primacy and Human-like operations. Future mutator changes SHALL conform.

### Modified Capabilities

(none — no existing spec covers paragraph-text mirror behavior; both new capabilities listed above)

## Impact

- Affected specs:
  - NEW: `openspec/specs/ooxml-paragraph-text-mirror/spec.md` (created on archive of this change)
  - NEW: `openspec/specs/ooxml-library-design-principles/spec.md` (created on archive of this change)
- Affected code:
  - New:
    - `packages/ooxml-swift/Sources/OOXMLSwift/Models/ReplaceResult.swift` — new public enum
    - `packages/ooxml-swift/Tests/OOXMLSwiftTests/Issue99FlattenReplaceOMMLBilateralTests.swift` — cluster RED→GREEN tests (5 issue coverage)
  - Modified:
    - `packages/ooxml-swift/Sources/OOXMLSwift/Models/InsertLocation.swift` — extend `flattenedDisplayText` walker; new private helper `walkOMMLBearingChildren`; refresh docstring
    - `packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift` — change `replaceInParagraphSurfaces` return type from `Int` to `ReplaceResult`; add OMML boundary detection
    - `packages/ooxml-swift/Sources/OOXMLSwift/Models/TextReplacementEngine.swift` — extend `replaceInContentXML` to expose offset-map for OMML boundary checks
    - `packages/ooxml-swift/CHANGELOG.md` — entry under Unreleased
  - Removed: (none)
- Downstream impact:
  - **che-word-mcp `replace_text` MCP tool**: must handle new `ReplaceResult.refusedDueToOMMLBoundary(...)` — translate to user-facing error message with occurrence info. Currently returns `count` directly; needs adapter. Tracked as separate che-word-mcp follow-up after this change ships.
  - **All other ooxml-swift consumers** of `replaceInParagraphSurfaces` (none external currently — internal-only API): no impact.
