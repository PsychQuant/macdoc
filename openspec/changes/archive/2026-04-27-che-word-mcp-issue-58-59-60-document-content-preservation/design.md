## Context

ooxml-swift v0.19.5 closed PsychQuant/che-word-mcp#56 via a 5-sub-stack convergence cycle (R5 → R5-CONT-4) with `testRevisionTypeMatrixAcceptRejectCompleteness` matrix-pin enforcing structural-symmetry invariants. The pin's value was catching asymmetries at the test framework level (asserting both accept and reject directions of every typed Revision) rather than relying on per-task gates to find symmetric siblings.

After v3.13.5 shipped, three follow-up issues surfaced — #58 (1 TOC bookmark dropped), #59 (334 chars whitespace), #60 (~313KB attribute loss including 74% of `<w:rFonts>`). The byte-preservation invariant for **unmodified** parts holds (verified: 0-byte delta on no-op `DocxReader.read` → `DocxWriter.write`). The 467KB shrinkage manifests only when `document.xml` is in `modifiedParts` — i.e., on every body-mutating MCP save.

Anatomization showed all three issues share one architectural cause: **the typed model is the bottleneck for round-trip fidelity, and "drop if not typed" is the wrong fallback policy**. R5-CONT-4's matrix-pin closed structural-symmetry convergence but did not assert body-level content-equality, so this class of regression was never caught by the existing test framework.

Current relevant code:
- `BodyChild` enum at packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift:3520 — three cases (`.paragraph`, `.table`, `.contentControl`); `parseBodyChildren` switch at DocxReader.swift:582-631 silently drops any `<w:body>` child not matching one of three element kinds
- `Run.rawElements` (Run.swift:24-30, v0.14.0+) — established raw-passthrough pattern; survived 18 months and 6 verify rounds without regression; precedent for the unifying principle "if not typed, preserve as raw"
- `parseRun` at DocxReader.swift:1531-1580 — calls `t.stringValue` on each `<w:t>` element; Foundation `XMLDocument` strips whitespace-only text node `stringValue` to "" regardless of `xml:space="preserve"` AND regardless of `.nodePreserveWhitespace` option (verified via isolated micro-test)
- `parseRunProperties` at DocxReader.swift:1872 — typed extraction of known rPr children; no rawChildren collection for unknowns
- 10 `XMLDocument(data:)` call sites in DocxReader.swift cover document/styles/numbering/header*/footer*/footnotes/endnotes/core/comments/extendedComments — same Foundation parser limitation affects all

Stakeholders:
- LLM-driven editing workflows on real-world `.docx` files (the load-bearing user story for the structural-editing-paradigm narrative — see docs/structural-editing-paradigm.md §3 §6)
- Existing v0.19.5 R5 stack convergence (any change must not regress the 30 previously-closed findings)
- The MCP layer (zero source changes — entire fix lives in ooxml-swift)

## Goals / Non-Goals

### Goals
- Close PsychQuant/che-word-mcp#58 (body-level marker preservation), #59 (whitespace overlay), #60 (RunProperties field-loss audit) under one architectural decision
- Ship the architectural matrix-pin (`testDocumentContentEqualityInvariant`) so future regressions of the same class are caught at the test framework level — same value proposition as R5-CONT-4's structural-symmetry pin
- Maintain v0.19.5 byte-preservation invariant for unmodified parts (0-byte no-op delta)
- Each sub-stack ships independently with its own 6-AI verify gate (per the per-task verify discipline established by R3 stack), allowing partial deployment if scope shifts mid-implementation

### Non-Goals
- Switching XML parser away from Foundation `XMLDocument` (rejected: see Decision 2)
- Closing the remaining 154KB element-overhead delta after the 313KB attribute loss is fixed (the 154KB drops naturally when attributes are preserved — fewer attributes mean fewer enclosing-tag bytes)
- Adding new MCP tool surface (existing tools auto-benefit)
- Closing inter-element whitespace formatting delta (1376 bytes total — 0.1% of source; not user-visible)

## Decisions

### Decision 1: Bundle three issues under one Spectra change with three independently-shipping sub-stacks

**What**: One Spectra change covers #58, #59, #60. Three sub-stacks land as separate releases (v0.19.6 → v0.19.7 → v0.20.0) but track under one umbrella for cross-cutting matrix-pin coverage.

**Why**: All three share the same architectural cause (parser-drops-untyped). One consistent answer ("if not typed, preserve as raw") scales better than three ad-hoc fixes. Matrix-pin in the test framework prevents future regressions of the same class — directly addresses the R5-CONT-4 meta-gap.

**Why not three separate changes**: The matrix-pin would be redundantly defined (or worse, inconsistent) across three change directories. The unifying principle would be implicit rather than documented. Verify cycles couldn't share infrastructure.

**Why not one big-bang release**: R3 → R5-CONT-4 stack-completion taught that independent verify gates per sub-stack catch issues that bundled verifies miss. Sub-stack boundaries also let users deploy v0.19.6's #58 fix without waiting for #60's larger scope.

### Decision 2: Whitespace overlay scan (NOT parser swap)

**What**: New internal value type `WhitespaceOverlay` in packages/ooxml-swift/Sources/OOXMLSwift/IO/WhitespaceOverlay.swift performs a pre-parse scan over raw `word/document.xml` byte stream, capturing `<w:t xml:space="preserve">[whitespace]</w:t>` content keyed by element sequence index in DOM document order. Plumbed through to `parseRun` which consults the overlay when `t.stringValue.isEmpty`.

**Why**: Foundation `XMLDocument` strips whitespace text nodes at parse time (verified: even with `.nodePreserveWhitespace` option, `xmlString` becomes empty — the option appears broken on macOS). This is a structural parser limitation, not a config bug.

**Why not parser swap (libxml2 direct or third-party Swift XML library)**: 1-2 weeks of work + new dependency + affects all 10 XMLDocument call sites + risk of regressing the v0.19.5 R5 stack stability (which took 5 sub-stacks and 30 findings to converge). Whitespace overlay is contained to DocxReader.swift, doesn't change the parser, and follows the same architectural pattern as `WordDocument.modifiedParts` overlay (the v0.13.0 architecture that powers the entire byte-preservation claim).

**Trade-off accepted**: Element-position keying must be reliable across DOM walks. Mitigation: extensive roundtrip tests against the thesis fixture as the gate. If a future issue surfaces with broken keying, parser swap remains an option.

### Decision 3: Hybrid typed-plus-raw approach for #60 RunProperties

**What**: For #60, take a hybrid approach:
- **Typed fields** for well-defined, common, OOXML-spec elements that benefit from API access: `noProof: Bool`, `kern: Int?`, `lang: LanguageProperties?` (3-axis); audit `rFonts` to capture all 4 axes (`ascii`/`hAnsi`/`eastAsia`/`cs`)
- **Raw passthrough** (`RunProperties.rawChildren: [RawElement]?`) for unrecognized rPr children — primarily `w14:*` namespace effects (textOutline, glow, shadow, reflection, textFill, scene3d) but works as catch-all for any future vendor extensions

**Why both**: Typed fields are needed for cases where users want to mutate the field via MCP (e.g., a hypothetical `update_run_no_proof` tool would need a typed boolean). Raw passthrough is needed for the long tail of vendor extensions that no typed model can fully cover. The same hybrid is already proven in `Run.rawElements` (v0.14.0+).

**Why not all-raw**: Loses MCP API tractability for common cases (font, lang, etc.).

**Why not all-typed**: Impossible to enumerate all vendor extensions; new w16, w17, etc. namespace versions ship every Office release.

### Decision 4: BodyChild enum extension shape (typed + generic catch-all)

**What**: For #58, extend `BodyChild` enum with two new cases:
```swift
case bookmarkMarker(BookmarkRangeMarker)  // typed for known kinds
case rawBlockElement(RawElement)           // generic catch-all
```

`parseBodyChildren` switch:
- `case "bookmarkStart"` / `case "bookmarkEnd"` → produces typed `.bookmarkMarker`
- `default:` (current `continue`) → produces `.rawBlockElement(RawElement(name:..., xml:...))`

**Why both**: Typed for the common, well-modeled case (bookmarks). Generic catch-all for forward-compat with other EG_BlockLevelElts members (`<w:moveFromRangeStart>`, body-level `<w:commentRangeStart>`, vendor extensions) — preserves bytes byte-exact even for elements we don't typed-model.

**Why not generic-only**: Loses typed access for bookmarks (which `nextBookmarkId` calibration walker needs).

**Why not typed-per-element**: Every new element kind requires explicit parser+writer branches. Unsustainable across OOXML's full EG_BlockLevelElts coverage.

### Decision 5: Matrix-pin assertion strategy (content equality, not byte equality)

**What**: `testDocumentContentEqualityInvariant` asserts content equality (counts of `<w:rFonts>`, `<w:t>` total chars, `<w:bookmarkStart>` count) NOT byte equality (exact element-by-element diff).

**Why**: Word's own canonicalization on save sometimes legitimately consolidates equivalent runs / reorders attributes. Asserting byte equality would fail on legitimate non-regression changes. Asserting content equality fails only on actual loss.

**Why not full byte equality**: Would require canonicalization layer (sort attributes, normalize whitespace, etc.) — out of scope and not actually beneficial.

**Why not weaker per-class assertions only**: Then a single matrix-pin gives weaker guarantees than the per-sub-stack tests already do. The matrix-pin's value is precisely that it asserts the cross-cutting invariant simultaneously across all three classes — a future change that fixes one class but breaks another would still fail the pin.

## Risks / Trade-offs

### Risk 1: Element-position keying in WhitespaceOverlay
The overlay keys whitespace content by element sequence index in DOM document order. If `parseRun` and the overlay scanner disagree on element positions (e.g., due to comment handling, namespace declaration order, or different element-counting semantics), the overlay returns wrong content. **Mitigation**: roundtrip tests against the thesis fixture as the gate; sub-stack B verify cycle expected to catch edge cases.

### Risk 2: Sub-stack C scope creep
RunProperties audit may reveal more lost fields than the initial anatomization (e.g., `<w:tblPr>` table properties may have similar issues). **Mitigation**: matrix-pin acts as the inclusion gate — any field with measurable count-loss in the thesis fixture goes in scope; everything else defers to a follow-up SDD.

### Risk 3: Verify cycle length
R5-CONT-4 took 8 verify rounds for one issue. Three issues with 3 verify rounds each = 9-15 total rounds at ~30min wall-clock per round. Schedule expectation must accommodate this. **Mitigation**: each sub-stack's matrix-pin extension is incremental, so partial wins (e.g., #58 + #59 land before #60) still ship value.

### Risk 4: Foundation XMLDocument behavior change
If a future macOS XMLDocument fix actually honors `.nodePreserveWhitespace`, the WhitespaceOverlay becomes redundant overhead. **Mitigation**: low priority — Foundation has had this behavior for 10+ years; even if Apple fixes it tomorrow, the overlay continues to work and the cost is one extra byte-stream scan per parse (~ms on 1.4MB document.xml).

### Trade-off: Sub-stack independence vs. matrix-pin coupling
Sub-stack A and B can ship without C, but the matrix-pin's `<w:rFonts>` assertions don't make sense until C lands. **Resolved**: matrix-pin lands incrementally — sub-stack A ships with bookmark-count assertion, sub-stack B adds whitespace-char assertion, sub-stack C adds RunProperties assertions. Each sub-stack's matrix-pin coverage is the union of all preceding sub-stacks plus its own.

## Migration Plan

No breaking API changes. Each sub-stack is purely additive at the public API level:

- **Sub-stack A (v0.19.6)**: Adds two cases to public `BodyChild` enum. Pattern matches that don't include the new cases will get Swift compiler exhaustiveness warnings; existing code that switches with a `default:` clause continues to work without changes. **Migration**: optional — callers may add explicit handling for `bookmarkMarker` / `rawBlockElement` cases if they care about those elements.
- **Sub-stack B (v0.19.7)**: Internal whitespace overlay; no public API change. Migration: none.
- **Sub-stack C (v0.20.0)**: Adds typed fields to `RunProperties` (`noProof`, `kern`, `lang`, `rawChildren`). Existing field accesses unaffected; `RunProperties` initializer gains optional parameters with defaults. **Migration**: optional — callers may now read/write the new typed fields.

che-word-mcp dep bumps:
- v3.13.6 (sub-stack A) → ooxml-swift 0.19.5 → 0.19.6
- v3.13.7 (sub-stack B) → ooxml-swift 0.19.6 → 0.19.7
- v3.14.0 (sub-stack C) → ooxml-swift 0.19.7 → 0.20.0

Marketplace sync follows each release per the established workflow (release flow → /plugin-update).

## Open Questions

None — diagnosis pass + 5-min probe confirmed all three RCAs; bundle scope confirmed via discuss; sub-stack order accepted (smallest-to-largest); matrix-pin design accepted (content equality, not byte equality).

If sub-stack B element-position keying turns out unreliable mid-implementation, fall back to parser swap (Decision 2 alternative) becomes a new open question to resolve at that point — but premature to surface now.
