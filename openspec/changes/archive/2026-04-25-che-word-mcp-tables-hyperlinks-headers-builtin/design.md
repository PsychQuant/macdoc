## Context

che-word-mcp v3.10.0 closes 3 of 7 P0 issues from the Office.js OOXML Roadmap ([che-word-mcp#43](https://github.com/PsychQuant/che-word-mcp/issues/43)). The next dependent triplet — **Tables (#49) / Hyperlinks (#50) / Headers (#51)** — was deliberately deferred until styles + sections were complete:

- #49 Tables: `set_table_conditional_style` + `set_table_style` reference paragraph/character styles created via the v3.10.0 `create_style` extensions
- #50 Hyperlinks: auto-create the `Hyperlink` character style on-demand, leveraging v3.10.0 `link_styles`
- #51 Headers: per-section header part assignment uses v3.10.0 `set_section_header_footer_references`

Bundling these three again — like the previous `che-word-mcp-styles-sections-numbering-foundations` SDD — exploits shared infrastructure. All three mutate document-level XML parts (`document.xml`, `header[N].xml`, `settings.xml`) and inherit the dirty-tracking discipline from `ooxml-document-part-mutations` (extended in this SDD).

After this SDD lands, only #45 (Track Changes — fully independent) remains in the P0 set. Office.js Roadmap moves to P1 territory.

Stakeholders: che-word-mcp users authoring corporate templates with conditional table styling (financial reports), academic documents with cross-reference hyperlinks (papers / theses), enterprise documents with multi-type headers and watermarks (NDAs / proposals).

## Goals / Non-Goals

**Goals:**

- 19 new MCP tools + 4 extended tools cover every checkbox in #49 / #50 / #51 acceptance criteria.
- ooxml-swift v0.17.0 delivers Table conditional formatting + nested tables (parser + writer + WordDocument), Hyperlink type discrimination + tooltip + history, Header reference type per part + even-odd flag + clone semantics.
- Round-trip fidelity verified by 3 new test fixtures: financial report (table conditional formatting), academic paper (3 hyperlink types), corporate proposal (3-section header configuration).
- All 4 capability specs include scenarios mapping 1:1 to tools.

**Non-Goals:**

- Theme integration (#43 §15 own SDD).
- Bookmark mutation (`insert_bookmark_hyperlink` consumes; doesn't create).
- Multi-section split (single-section limitation inherited from v3.10.0).
- Track Changes for these surfaces (covered by #45).
- Cross-document hyperlink validation.
- Watermark image transformations.

## Decisions

### Nested table parsing strategy: recursive parseTable with depth limit 5

**Decision:** `DocxReader.parseTable` becomes recursive — when scanning `<w:tc>` children, if a `<w:tbl>` element is encountered, parse it via `parseTable` (recursive call) and append to a new `Cell.nestedTables` field (distinct from `Cell.paragraphs`). A static `MAX_NEST_DEPTH = 5` constant in DocxReader prevents runaway recursion on malformed input. Exceeding the limit throws `WordError.invalidDocx("nested table depth exceeds 5 levels at cell <ref>")`.

**Rationale:** Word's UI allows arbitrary nesting in theory, but real-world documents almost never exceed 2-3 levels (financial reports with sub-totals, comparison matrices). 5 levels matches Word's own internal warning threshold. Without a limit, a malformed file with circular `<w:tbl>` references could OOM the parser. Recursive call keeps the parse path symmetric — the same code that parses top-level tables handles nested ones.

**Alternatives considered:**

- *Iterative with explicit stack:* avoids recursion but doubles the code path. Rejected — cells already trigger recursion via paragraph parsing; tables are no different.
- *No depth limit:* trusts input. Rejected — production fuzzing tests showed 1 sample file with circular references could spin.

### Hyperlink character style is auto-created on first hyperlink insert, idempotent

**Decision:** When any `insert_*_hyperlink` tool is invoked, the helper checks `doc.styles` for a style with id `Hyperlink`. If absent, it creates one via `doc.addStyle(...)` using the standard Word defaults (color: `#0563C1`, underline: single, type: character). Subsequent inserts skip creation when the style already exists.

The style creation call uses the v3.10.0 mutation API and marks `word/styles.xml` dirty automatically.

**Rationale:** Word documents created from scratch (`create_document`) don't include the `Hyperlink` style — it's auto-added when Word UI inserts a hyperlink. Without this, MCP-inserted hyperlinks render as plain text, breaking visual consistency with Word-authored hyperlinks. Idempotency prevents duplicate-style errors on repeat inserts.

**Alternatives considered:**

- *Require caller to pre-create the style:* surprising failure mode; users won't know to do this. Rejected.
- *Embed inline `<w:rStyle>` reference without ensuring the style exists:* invalid OOXML — `<w:rStyle w:val="Hyperlink"/>` referencing a missing style is technically allowed but Word silently ignores it (broken visuals).

### Header link-to-previous clones the source XML part, not just the rId

**Decision:** `link_section_header_to_previous(section_index, type)` finds the immediately-prior section's header XML part of the matching type, and assigns that part's rId to the target section's header reference (sharing the part). Conversely, `unlink_section_header_from_previous(section_index, type)` reads the currently-shared part, creates a new header XML part with a copy of its content (`Document.cloneHeaderForSection`), assigns a new rId, and updates the target section's reference to point at the new part.

**Rationale:** Word's "Same as Previous" semantics actually share the XML part (saving disk space), and "Different from Previous" creates a new copy at unlink time. Sharing rId only would corrupt downstream behavior — modifying the linked header in section 2 would silently change section 1's header. Cloning at unlink time is the right symmetry.

**Alternatives considered:**

- *Copy-on-write via reference counting:* Word's spec doesn't define this; would diverge from Word's behavior. Rejected.
- *Always clone (never share parts):* defeats the disk-space optimization; produces files larger than Word itself would write. Rejected.

### Watermark text-vs-image is an extension to existing `insert_watermark`, not a new tool

**Decision:** Existing `insert_watermark` tool (v3.4.0) gains a discriminator parameter to choose between text watermark (default, current behavior, uses `<v:textpath>`) and image watermark (uses anchored shape with `wrapNone behindDoc='1'`). Existing `insert_image_watermark` tool retained as a soft alias delegating to `insert_watermark(image_path: ...)`.

**Rationale:** Word treats both as "watermark" — same toolbar entry, same removal flow. Splitting into two tools means callers have to know which to use; combining lets the MCP client just call `insert_watermark` and pass whichever args they have. The existing tool's surface is preserved (text-only callers see no behavior change).

**Alternatives considered:**

- *Separate tools `insert_text_watermark` and `insert_image_watermark`:* duplicates effort; the existing tools already cover both cases (text via `insert_watermark`, image via `insert_image_watermark`). Just need clarification + cross-link in tool descriptions. Rejected — wouldn't be a meaningful schema change.

### Table conditional formatting uses tblStylePr with type discriminator, not separate API per type

**Decision:** `setTableConditionalStyle(tableIndex:, type:, properties:)` accepts the type as a string enum (`firstRow` / `lastRow` / `firstCol` / `lastCol` / `bandedRows` / `bandedCols` / `neCell` / `nwCell` / `seCell` / `swCell`) and emits one `<w:tblStylePr w:type="$type">` block per call. Multiple calls with different types accumulate (firstRow + bandedRows + lastRow all set).

**Rationale:** OOXML's `<w:tblStylePr>` element has 10 possible `w:type` values. A separate Swift method per type would mean 10 nearly-identical methods. Single method with enum dispatch matches the OOXML schema 1:1 and keeps the API surface small.

**Alternatives considered:**

- *10 separate methods:* lines of code grow without expressiveness gain. Rejected.
- *Bulk method accepting `[(type, properties)]`:* loses partial-update semantics (caller can't toggle one type without restating others). Rejected.

## Risks / Trade-offs

[Risk] Nested table depth limit of 5 is a heuristic. If a real-world document hits the limit (highly unlikely), parse fails with a clear error. Mitigation: depth limit is a static constant; bumping requires a code change, allowing controlled response if a user reports the edge case.

[Risk] Hyperlink character style auto-creation could collide with an existing user-defined `Hyperlink` style with different properties. Mitigation: check is idempotent — only creates when absent. If the user's `Hyperlink` style has different properties, the inserted hyperlink uses the user's style (correct behavior).

[Risk] Header clone semantics double the disk space when many sections "unlink from previous". Real documents rarely have more than 3-4 sections with distinct headers, so the bloat is negligible. Mitigation: documented in `unlink_section_header_from_previous` tool description.

[Trade-off] Bundling 3 issues into one SDD breaches "1 issue 1 SDD" idiom. Same defense as v3.10.0 SDD: shared architectural pattern, shared release ceremony, atomically closeable issues.

[Trade-off] 19 new tools push tool count from ~199 → ~218. MCP clients with tool-list size limits may notice. Acceptable — trend continues from v3.9.0 (8 new) and v3.10.0 (19 new).

## Migration Plan

- ooxml-swift v0.16.x → v0.17.0 — minor version (additive API; existing methods unchanged).
- che-word-mcp v3.10.x → v3.11.0 — minor version (additive tools + extended args on `add_header` / `add_footer` / `merge_cells` / `set_table_style` / `set_cell_width` / `set_row_height` / `insert_watermark`; default args preserve v3.10.x behavior).
- Existing `insert_hyperlink` tool kept as deprecated soft-alias for `insert_url_hyperlink` (description annotated, removed in v4.0.0).
- Binary release triggers marketplace sync per common-release-flow rule.
- Rollback: revert che-word-mcp Package.swift's ooxml-swift dep to ^0.16.0. Re-build. No data migration concerns.

## Open Questions

- Should `insert_watermark` accept both text and image args in a single call (text overlay on image)? Word doesn't render this combination correctly, so leaning toward mutual-exclusion validation in the tool. Tracking — confirm during implementation if any user has hit this combination.
- For `insert_nested_table`, should the parent-cell selector be `(row_index, col_index)` or a "cell ref" string like `"A1"`? Lean toward zero-based indices for consistency with existing table tools (`add_row_to_table` uses index).
