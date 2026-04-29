## Context

`PsychQuant/che-word-mcp#62` (P2 enhancement) — real-world `.docx` files pasted into a template carry caption text as plain runs (e.g., `圖 4-1：<title>`) rather than properly-structured `SEQ`-field captions. This breaks `update_all_fields` (reports "no SEQ fields found") and `insert_table_of_figures` / `insert_table_of_tables` (produce empty TOFs). The only existing paths are manual Word UI clicks per caption or hand-editing `word/document.xml`. A new bulk-conversion tool `wrap_caption_seq` closes this upstream gap.

The discussion captured in `PsychQuant/che-word-mcp#62` (and its `idd-discuss` follow-up) settled six API design questions; this design records the chosen path with rationale so the implementer doesn't have to re-derive trade-offs.

### Existing infrastructure (informs decisions)

- `mcp/che-word-mcp/Sources/CheWordMCP/Server.swift` lines 12140-12256 — `insertCaption` already produces real SEQ fields via `SequenceField(...).toFieldXML()`. The emission machinery is fully reusable.
- `packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift` lines 443+ — `replaceText(find:with:options:)` is the precedent for body + table cells + nestedTables walking.
- `packages/ooxml-swift/Sources/OOXMLSwift/Models/WordDocument+UpdateAllFields.swift` line 44 — `updateAllFields(isolatePerContainer:)` already standardized body + headers + footers + footnotes + endnotes traversal.
- `packages/ooxml-swift/Sources/OOXMLSwift/Models/FieldSimple.swift` — `FieldSimple` struct with `instr` + `runs` + attribute round-trip.
- `packages/ooxml-swift/Sources/OOXMLSwift/Models/Field.swift` — `SequenceField` struct with `format` enum and `cachedResult`, including `toFieldXML()` emission.

## Goals

- Provide one composable bulk-wrap tool that converts plain-text caption number portions to SEQ-field-bearing runs.
- Reuse the existing SEQ-field emission machinery (`SequenceField.toFieldXML()`) so no new XML construction code paths.
- Reuse the existing scope traversal vocabulary (`body` / `all`) introduced by `updateAllFields(isolatePerContainer:)`.
- Idempotent — re-running on already-wrapped paragraphs reports them under `skipped` and never double-wraps.
- Cross-repo placement: lib method in ooxml-swift so non-MCP Swift consumers benefit; MCP layer is a thin pass-through.

## Non-Goals

(Inherited verbatim from proposal `Non-Goals`.)

- STYLEREF chapter-number prefix (compose with `insert_caption` for new captions).
- Caption description text rewriting (this tool only wraps the NUMBER portion).
- TOF/TOT bookmark cross-ref population (separate `insert_cross_reference` invocation).
- Auto-detection of caption labels (user supplies regex; auto-detection fights with i18n).

## Decisions

### Decision 1 — Match interface: regex with one numeric capture group (A1)

Single regex string parameter `pattern`. The regex MUST contain exactly ONE capture group, and that group MUST match digits (e.g., `\d+`). The captured substring becomes the SEQ field's cachedResult.

Rationale:

- A literal-prefix mode (e.g., `prefix: "圖 4-"`) is a strict subset of regex via `NSRegularExpression.escapedPattern(for:)`. Adding a separate parameter doubles the API surface for the same functionality.
- Real fixtures (`圖 4-1：`, `Figure (\d+)\.\d+`, `表 第(\d+)節`) need regex anyway.
- Validation rejects patterns with zero or 2+ capture groups (ambiguous which one is the number).

Pattern is compiled with `NSRegularExpression` options `[]` (no special flags — caller can use inline `(?i)` etc.). Empty pattern rejected before compile.

### Decision 2 — Bookmark wrapping defaults OFF; opt-in via insert_bookmark + bookmark_template (A2)

Default behavior: rewrite numeric portion to SEQ-field run only.

Opt-in: `insert_bookmark: true` wraps the rewritten paragraph in `<w:bookmarkStart>` (immediately before the SEQ-field run) and `<w:bookmarkEnd>` (after it). Bookmark name comes from `bookmark_template`, which MUST contain the literal placeholder `${number}` substituted with the captured numeric (e.g., template `"fig${number}"` produces bookmarks `fig1`, `fig2`, `fig3`, ...).

If `insert_bookmark: true` but `bookmark_template` is nil or missing `${number}`, the tool returns an error before mutating the document.

Rationale:

- 23 caption auto-bookmarks pollute `list_bookmarks` for the 90% of users who do not need cross-refs.
- Users who DO want cross-refs (subsequent `insert_cross_reference` calls) opt in explicitly with one extra parameter.

### Decision 3 — Scope vocabulary: "body" | "all" mirroring updateAllFields (A3)

`scope: String?` defaults to `"body"`. Only two values accepted: `"body"` (walks `body.children` only) and `"all"` (body + headers + footers + footnotes + endnotes — exactly the same parts traversed by `updateAllFields(isolatePerContainer: false)`).

Rationale:

- Consistency: SEQ fields already share counter state across these parts via `updateAllFields`; making `wrap_caption_seq` use a different scope vocabulary would introduce confusion.
- `"all"` is rare for captions (figures rarely live in headers/footers) but covers page-recurring stamps.
- Refusing to invent a third scope keyword like `"headers_only"` until a real use case appears.

Scope is implemented at the lib layer via a `TextScope` enum. If `TextScope` does not yet exist as a shared type, this change introduces it in `Models/TextScope.swift` (single file, two cases: `.body`, `.all`); `updateAllFields` is NOT refactored to use it (that would be scope creep).

### Decision 4 — Format flag, replacement (not preservation), of user-typed numerals (A4)

`format: String?` defaults to `"ARABIC"`. Accepted values: `"ARABIC"`, `"ROMAN"`, `"ALPHABETIC"` — mapped 1:1 to the three cases of `SequenceField.format` enum.

The user-typed numeric portion (the regex capture) is REPLACED by the SEQ-field run. The captured digits are preserved as the `cachedResult` so Word does not visually re-shuffle on first open before F9 recalculation, but the source of truth for subsequent renders is the SEQ field.

Rationale:

- Silent preservation diverges on the next F9 (Word recomputes SEQ counter from scratch). Replacement is the only consistent option.
- `cachedResult = capturedNumber` is the bridge: pre-F9 the displayed text matches the user's original numbering; post-F9 Word recomputes and the display matches the field-based truth.

If user-typed numerals are non-numeric (e.g., regex captured Roman numerals into a non-Arabic scheme), the tool still uses the captured string as `cachedResult` verbatim — Word handles non-numeric cachedResult per spec.

### Decision 5 — Return shape: structured per-paragraph result (A5)

Lib returns:

```swift
public struct WrapCaptionResult: Equatable {
    public let matchedParagraphs: Int     // count of paragraphs whose flattenedDisplayText matched the regex
    public let fieldsInserted: Int        // count of SEQ fields actually written (matched - skipped)
    public let paragraphsModified: [Int]  // body.children indices in document order
    public let skipped: [SkippedParagraph]
}

public struct SkippedParagraph: Equatable {
    public let paragraphIndex: Int
    public let reason: String
}
```

MCP layer marshals to JSON with snake_case keys.

Rationale:

- Per-paragraph indices let the LLM caller verify "did all 23 captions get fields?" via diffing against `list_captions` output.
- `skipped` surfaces idempotency no-ops (e.g., paragraph already has SEQ Figure field) so the caller doesn't think the call silently failed.

Skip reasons enumerated:

- `"already wraps SEQ {sequenceName}"` — paragraph runs/fieldSimples already contain the target SEQ field.
- (Future reasons may be added — the field is open string by design; callers SHALL NOT pattern-match exact wording, only treat it as opaque telemetry.)

### Decision 6 — Lib placement: Document.wrapCaptionSequenceFields, MCP layer is thin (A6)

Method lives on `WordDocument` extension in `packages/ooxml-swift/Sources/OOXMLSwift/Models/WordDocument+WrapCaptionSequenceFields.swift`. MCP wrapper in `Server.swift` does only:

1. Decode args → typed values
2. Compile regex; reject malformed
3. Map format string → `SequenceField.Format`
4. Map scope string → `TextScope`
5. Call `doc.wrapCaptionSequenceFields(...)`
6. Marshal `WrapCaptionResult` → JSON string
7. Persist via `storeDocument`

Rationale:

- Three precedents (`replaceText`, `updateAllFields`, `insertParagraph`) are all `Document` methods; SEQ emission already lives in lib (`SequenceField.toFieldXML()`); regex+mutation+scope walking belongs with the surface walker.
- Swift consumers of ooxml-swift get the same surface without reaching into MCP.
- Lib placement also makes lib-side unit testing direct (no MCP fixture overhead for the core mutation logic).

## Algorithm sketch

For each paragraph in scope:

1. Call `paragraph.flattenedDisplayText()` (already exists, post-#63 — covers inline SDT).
2. Apply `NSRegularExpression.firstMatch(in:options:range:)` against the displayed text.
3. If no match: continue.
4. If match but paragraph runs/fieldSimples already contain `SEQ {sequenceName}`: append to `skipped` with reason; continue.
5. Otherwise: locate the captured numeric range within the run sequence (run-by-run text-offset accumulation); split the containing run into [pre-text run, SEQ-field run, post-text run]; rebuild paragraph runs.
6. If `insertBookmark`: insert `<w:bookmarkStart name="{bookmark_template-substituted}" id="{generated-id}">` before the SEQ-field run, `<w:bookmarkEnd id="{same-id}">` after it.
7. Append paragraph index (top-level body index — when paragraph is in a table cell, this is the table's body index, mirroring `findBodyChildContainingText` semantic) to `paragraphsModified`.

The split-the-run step reuses the offset-mapping pattern from `Document.replaceInParagraphSurfaces` (Document.swift:326+).

For `scope: "all"`, the same per-paragraph procedure applies inside each header / footer / footnote / endnote part. The returned `paragraphsModified` indices are top-level within their respective container; the MCP wrapper labels each entry's container in the JSON return (extension to the lib `SkippedParagraph` shape: an optional `container: String?` field — `nil` for body, `"header:default"` etc. for cross-container). Phase 1 lib lands `container: nil` only (body-only path); Phase 2 MCP wrapper plus the cross-container path land together.

## Risks

- **Regex DoS**: pathological patterns (e.g., `(a+)+`) on huge documents. Mitigation: `NSRegularExpression` is non-backtracking by default; document the risk in tool description text.
- **Cross-paragraph captions** (e.g., paragraph break inside `圖 4-1：`): `flattenedDisplayText` joins only within ONE paragraph. Cross-paragraph captions silently miss. Acceptable — real-world captions are single-paragraph by convention; edge case can be addressed in a follow-up if surfaced.
- **Idempotency check correctness**: detecting "already wraps SEQ Figure" requires walking `paragraph.fieldSimples` AND scanning `paragraph.runs[].rawXML` for fldChar-style SEQ fields (since `insertCaption` emits via `Run.rawXML = SequenceField.toFieldXML()`). Tests must cover both emission styles.
- **Phase split correctness**: `WrapCaptionResult.SkippedParagraph.container` is `nil`-only in Phase 1 (body scope). Phase 2 MCP wrapper accepts `scope: "all"` only after the lib gains container labeling — the MCP layer rejects `scope: "all"` until Phase 2's lib bump lands.
