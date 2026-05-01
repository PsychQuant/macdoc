## Context

`Paragraph.flattenedDisplayText()` (`packages/ooxml-swift/Sources/OOXMLSwift/Models/InsertLocation.swift:278-294`) and `Document.replaceInParagraphSurfaces` (`packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift:326-369`) both walk the same 5 wrapper surfaces — top-level runs, hyperlinks.runs, fieldSimples.runs, alternateContents.fallbackRuns, contentControls. The docstring at `InsertLocation.swift:264-266` claims they form a mirror invariant: "reading and writing operate on the same text universe."

The mirror is broken in the OMML axis. Both functions delegate to `flattenRunsWithOMML(_ runs: [Run])` (read) or `TextReplacementEngine.replace(runs:...)` (write), each accepting `[Run]` only. When `<m:oMath>` / `<m:oMathPara>` appears as a *direct child* of a wrapper (not wrapped in `<w:r>`), it lands in `paragraph.unrecognizedChildren` (`Paragraph.swift:100`), `HyperlinkChild.rawXML(String)` (`Hyperlink.swift:156-159`), or `AlternateContent.rawXML` (`AlternateContent.swift:43`) — none of which the run-only walker traverses.

This is the most common Pandoc / Quarto / LaTeX→docx output shape: `$$...$$` display math emits `<m:oMathPara>` as direct child of `<w:p>`. che-word-mcp #99 / #100 / #101 / #102 / #103 are 4 wrapper-position bugs + 1 docstring sync, all surfaced from #92 verify findings (DA-1..DA-5).

Prior art:
- #85 introduced per-run OMML walk for top-level runs only
- #92 extracted `flattenRunsWithOMML` helper so wrapper-Run paths share it
- This change extends to direct-child OMML at all 4 wrapper positions, bilaterally (read AND write)

The `replaceInParagraphSurfaces` precedent for "skip non-mutable elements" exists: `replaceInContentControl` (`Document.swift:380-409`) already skips `<w:delText>` and `<w:instrText>` because they aren't user-visible text. This change extends that *form* to OMML — but on a different *basis* (OMML IS visible; the principle is correctness of mutation, not skipping non-text).

## Goals / Non-Goals

### Goals

- Resolve che-word-mcp #99 / #100 / #101 / #102 / #103 as cluster
- Bilateral mirror coverage: read sees direct-child OMML visibleText; write detects OMML boundaries
- Establish library-wide normative principles applicable to all current and future OOXML mutators
- Informative refusal contract via typed `ReplaceResult` enum
- Zero parser/writer round-trip behavior change (raw passthrough preserved)

### Non-Goals

(See proposal Non-Goals section — equation content mutation, escape hatch, typed field promotion, symmetric mirror, visitor protocol abstraction all explicitly out of scope.)

## Decisions

### Decision 1: Bilateral fix scope (read AND write), not read-only

**Rationale**: Read-only fix would create *worse* mirror invariant — LOOKUP can find anchor crossing OMML, REPLACE silent no-ops on it. The asymmetry from "neither walks OMML" → "only read walks OMML" makes the mirror MORE broken, not less, because callers who use LOOKUP to confirm anchors then call REPLACE will encounter a new failure mode. Bilateral fix establishes a coherent (if asymmetric) contract: reads include, writes detect.

**Alternatives considered**:
- *Read-only* (close #99-#103 as 5 read-side issues): rejected — leaves write-side mirror still broken, worse cumulative UX
- *Write-only* (skip read until equation-editing tool ships): rejected — defeats #99 motivating ask (Pandoc anchor lookup)

### Decision 2: REPLACE semantic = opaque OMML refuse (Semantic A)

**Rationale**: Driven by library design principles (Decision 5). Three semantics evaluated; only A satisfies both Correctness and Human-like principles:
- **Semantic A (refuse)**: `replace_text("eq δ here", with: "ref X")` returns `refusedDueToOMMLBoundary` — match span `[4, 14)`, OMML span `[7, 8)`. Caller decides next step.
- **Semantic B (mutate around OMML)**: rejected. `replace_text("eq δ here", with: "ref X")` produces `<w:r>see </w:r><m:oMath>δ</m:oMath><w:r>ref X</w:r>` → `flattenedDisplayText()` = `"see δref X"`. Structurally valid OOXML, semantically incorrect (user wanted `"see ref X"`, got fragment with stale equation in middle). Violates Correctness principle.
- **Semantic C (drop OMML)**: rejected as default. `replace_text(...)` silently deletes the equation. Violates Human-like principle (no human Word user accidentally deletes equations while changing surrounding prose).

**Alternatives considered**:
- *Semantic A+ (escape hatch param)*: deferred. Explicit `omml_handling: "drop"` parameter would satisfy principles via opt-in destructive. Out of scope this change to ship principle-locked default first; escape hatch in follow-up after soak.
- *Semantic D (read excludes OMML to match write)*: rejected. Defeats #99 — Pandoc anchor `"see eq δ here"` becomes unreachable at LOOKUP. Symmetric mirror at the cost of user value.

### Decision 3: Lightweight unified walker, not protocol abstraction

**Rationale**: 4 wrapper positions are OOXML schema-fixed, not extensible. Module-private static helper `walkOMMLBearingChildren(_ paragraph:, _ visit:)` (or per-direction equivalents) delegates wrapper-position-specific OMML extraction to single source of truth, called from both flatten and replace paths. Avoids forcing `Paragraph` / `Hyperlink` / `FieldSimple` / `AlternateContent` to mutually depend via protocol existential.

**Alternatives considered**:
- *Protocol abstraction (`OMMLBearingNode`)*: rejected. Hypothetical extensibility for "future 5th wrapper" is over-design — OOXML schema doesn't add wrappers. Cost: cross-model dependency churn.
- *4 inline patches in `flattenedDisplayText` and `replaceInParagraphSurfaces`*: rejected. Duplicates OMML extraction logic 8 times (4 positions × 2 directions). Helper extraction is natural extension of #92's `flattenRunsWithOMML` pattern.

### Decision 4: Raw passthrough preserved — direct-child OMML stays in `unrecognizedChildren` / `HyperlinkChild.rawXML` / `AlternateContent.rawXML`

**Rationale**: Walker scans existing raw storage with `child.name == "oMath" || child.name == "oMathPara"` filter (`UnrecognizedChild.name` already populated by parser), uses existing `OMMLParser.parse(xml: rawXML).visibleText`. No parser change. No writer change. No round-trip fidelity test impact. Matrix-pin assertions in `testDocumentContentEqualityInvariant` unaffected.

**Alternatives considered**:
- *Promote to typed field (`Paragraph.directOMath: [DirectOMath]`)*: rejected. Cleaner spec semantically ("we know this is OMML"), but requires `parseParagraph` default-case change + emit-path change + round-trip test update. Higher risk for marginal spec cleanliness gain.

### Decision 5: Library design principles as foundational normative invariants

**Rationale**: This change discovers two principles that should govern all `ooxml-swift` mutator design, not just this fix:

#### Principle 1: Correctness primacy
> When the library cannot perform an operation correctly, it MUST refuse rather than perform an incorrect approximation. The bar for "correct" is human-like correctness — what a human Word user would consider the same intent — not just structurally valid OOXML.

#### Principle 2: Human-like operations
> Library operations MUST correspond to actions a human Word user would consciously perform. Operations that produce intermediate state no human would create, or that quietly perform destructive changes the user did not request, MUST be rejected at design time.

Captured as a separate capability spec (`ooxml-library-design-principles`) so future mutator changes (insertion, deletion, formatting, etc.) can be measured against them. This change is the first to apply them.

**Alternatives considered**:
- *Principles inline in `ooxml-paragraph-text-mirror` spec*: rejected. Principles are mutator-wide; coupling them to one capability prevents reuse. Separate spec is less convenient now but right structurally.
- *No formal principles, just `Decision 2` rationale*: rejected. The same trade-off (correctness > convenience, refuse > destructive) will recur for every future mutator. Documenting once prevents re-litigation.

### Decision 6: Position ordering = source XML order

**Rationale**: Direct-child OMML can appear *between* `<w:r>` runs in source XML. `flattenedDisplayText()` must reflect actual reading order: `<w:r>see eq </w:r><m:oMath>δ</m:oMath><w:r> here</w:r>` → `"see eq δ here"`, not `"see eq  here" + δ` (which would be the result of the current hardcoded wrapper-class iteration order: runs → hyperlinks → fieldSimples → AC → contentControls).

Implementation: walker uses the existing `position: Int?` field on `UnrecognizedChild` (`ParagraphChildMarkers.swift:198`) and the analogous position fields on typed wrappers. Sort merge step before joining text fragments.

**Alternatives considered**:
- *Append-only (OMML text appended after all runs)*: rejected. Anchor lookup for `"eq δ here"` fails because the substring crosses positions that are no longer adjacent in flatten output.

### Decision 7: ReplaceResult typed enum with structured occurrence info

**Rationale**: Silent `0` return from REPLACE provides no signal to caller about *why* replacement didn't happen. Three failure modes need disambiguation:
- Anchor not found in any walked surface (`replaced(count: 0)`)
- Anchor found but match span crosses OMML boundary (`refusedDueToOMMLBoundary(occurrences:)`)
- Successful replacement (`replaced(count: N > 0)`)

Structured occurrences — `(matchSpan: Range<Int>, ommlSpans: [Range<Int>])` — let MCP tool / agent caller produce actionable error: "Cannot replace 'eq δ here'; equation appears at character 7-8. Rephrase find to avoid equation, or use future omml_handling parameter."

**Alternatives considered**:
- *Throw exception on refuse*: rejected. Caller already handles `Int` return; throws change error semantics for non-error refusal. Refusal is a normal outcome, not exceptional.
- *Single bool `refused: Bool` flag alongside count*: rejected. Loses occurrence info caller needs to format error message.

### Decision 8: Documentation refresh — embrace asymmetry explicitly

**Rationale**: Existing `flattenedDisplayText` docstring at `InsertLocation.swift:264-266` says "Mirrors surface coverage of `replaceInParagraphSurfaces` so reading and writing operate on the same text universe." Post-change this is *more* true (both walk same 4 wrapper positions for OMML) but with a documented asymmetry on what each *does* with detected OMML. New docstring explains the asymmetry as principle-driven feature, not implementation gap.

#103 closes by reference to this change — no separate docs commit needed.

## Risks / Trade-offs

- **["Found but can't replace" UX confusion]** → Mitigation: principle reframe — refusal is the correct behavior under Human-like principle (replacement crossing OMML boundary IS a non-trivial decision a human would consciously make). Informative `ReplaceResult.refusedDueToOMMLBoundary(occurrences:)` makes refusal actionable, not silent. MCP tool docstring explicitly says `replace_text` may refuse with structured error.
- **[Most common Pandoc edit case is exactly the failing case (text around display math)]** → Mitigation: Decision 7 ReplaceResult lets caller inspect occurrence info and either (a) rephrase find to fall within `<w:t>`, (b) issue separate replace calls for prose before/after equation, (c) wait for future escape hatch. Acceptable trade-off because correctness > convenience under Principle 1.
- **[Decision 4 keeps OMML in raw storage — future parser refactor risks regression]** → Mitigation: walker filter logic (`child.name == "oMath" || child.name == "oMathPara"`) is single source of truth in helper. Future parser change to typed field can swap walker without breaking other callers. Tests pin walker output for reproducer XML, not storage shape.
- **[`UnrecognizedChild.name` parsed from QName but namespace-prefix-free comparison]** → Mitigation: walker accepts both `oMath` and `m:oMath` forms (assert: parser strips namespace prefix to local name). Test pins both shapes.
- **[Position ordering interaction with existing wrapper-class hardcoded order]** → Mitigation: walker sorts by `position` only when direct-child OMML present in paragraph; pure-runs paragraphs (the common case) bypass sorting. Performance neutral for non-OMML paragraphs.
- **[BREAKING for `replace_text` MCP tool consumers]** → Mitigation: signal in proposal What Changes. che-word-mcp `replace_text` adapter follows in separate change — handles new `ReplaceResult.refusedDueToOMMLBoundary` and translates to user error. ooxml-swift internal callers updated in same change.

## Migration Plan

1. Land ReplaceResult enum (NEW file, additive)
2. Land walker helper + tests (additive, no behavior change to callers)
3. Switch `flattenedDisplayText` to use walker (read-side change, behavior visibly extends to direct-child OMML)
4. Switch `replaceInParagraphSurfaces` return type to `ReplaceResult` (BREAKING for ooxml-swift internal callers — update in same commit)
5. Refresh docstring
6. Bump ooxml-swift version (minor — additive new public API + behavior extension)
7. Downstream che-word-mcp MCP tool adapter (separate change, separate version bump)

Rollback: revert single commit; raw storage untouched means no data migration risk.

## Open Questions

(none — all opens resolved in spectra-discuss session)

## Worked Example

Input paragraph XML (issue #99 reproducer):

```xml
<w:p>
  <w:r position="1"><w:t>see eq </w:t></w:r>
  <m:oMath position="2"><m:r><m:t>δ</m:t></m:r></m:oMath>
  <w:r position="3"><w:t> here</w:t></w:r>
</w:p>
```

| Operation | Pre-change behavior | Post-change behavior |
|-----------|---------------------|---------------------|
| `flattenedDisplayText()` | `"see eq  here"` (δ silently dropped) | `"see eq δ here"` (δ included via walker) |
| `findBodyChildContainingText("eq δ here")` | `nil` (anchor not found) | paragraph index (anchor found via flatten) |
| `replaceInParagraphSurfaces(find: "here", with: "there")` | `1` (mutates run 3's `<w:t>`) | `.replaced(count: 1)` (same mutation) |
| `replaceInParagraphSurfaces(find: "eq δ here", with: "ref X")` | `0` (silent — anchor not even found pre-change) | `.refusedDueToOMMLBoundary(occurrences: [(matchSpan: 4..14, ommlSpans: [7..8])])` |
| `replaceInParagraphSurfaces(find: "see ", with: "view ")` | `1` | `.replaced(count: 1)` |

The transition from `Int` return type to `ReplaceResult` is BREAKING for ooxml-swift internal callers (none external currently); che-word-mcp adapter follows in separate change.
