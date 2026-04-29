## Context

`che-word-mcp#23` round 1 was diagnosed and fixed in `che-word-mcp-ooxml-roundtrip-fidelity` (archived 2026-04-23-09:30). Released as `ooxml-swift v0.12.0` (preserve-by-default architecture: `WordDocument.archiveTempDir`, `WordDocument.close()`, `DocxWriter` overlay mode that "overwrites typed parts in archiveTempDir, leaves unknown parts byte-for-byte"). Released as `che-word-mcp v3.3.0/v3.4.0` (25 new MCP tools using the preserved archive).

NTPU thesis no-op round-trip testing exposed the round-1 fix as **incomplete**:

- ZIP entry count preserved (26 = 26) ✓
- But typed-managed parts byte content destroyed:
  - `header1.xml` 3923 bytes (with watermark VML) → 318 bytes empty stub
  - `fontTable.xml` 13 fonts → 3 hardcoded fonts (Calibri / TNR / Calibri Light)
  - `[Content_Types].xml` 27 Overrides → 16 (header2-6 / footer2-4 / endnotes / footnotes / commentsExtended PartNames missing)

Three downstream sibling bugs filed (`#32`, `#33`, `#34`) all stem from the same architectural gap. Round 2 RCA in [`#23 issuecomment-4301356366`](https://github.com/PsychQuant/che-word-mcp/issues/23#issuecomment-4301356366) identifies three layered root causes: (1) DocxWriter has no dirty tracking; (2) `writeFontTable` hardcodes 3 fonts with no document parameter; (3) `Header.fileName` / `Footer.fileName` collapse multi-instance same-type to single fixed string.

Stakeholders:
- NTPU thesis writer (immediate P0 — current state silently destroys watermark + Chinese fonts on every save)
- Future enterprise template users (latent — same patterns in any docx with multi-section headers/footers + custom font tables)
- `che-word-mcp` v3.4.0 callers using `person_id` field (need backward-compat migration path before v4.0.0)

Repository constraints:
- `ooxml-swift` is at v0.12.2 (just shipped). Bump to v0.13.0 (architecturally additive — `Set<String>` field + opt-in skip behavior).
- `che-word-mcp` is at v3.4.0. Bump to v3.5.0 with dep bump + 4-issue fix bundle.
- Existing `RoundTripFidelityTests` (15 tests, all green) validates round-1 architecture but not round-2 — those tests would still pass on the broken impl. Need stronger fixture-driven tests.

## Goals / Non-Goals

**Goals:**

- Make NTPU thesis no-op round-trip produce file-content-equal output for every ZIP entry (typed parts whose paths are NOT in `modifiedParts` are byte-equal to source; ZIP-level CRC + timestamps may differ).
- Make `update_theme_fonts(minor: { ea: "DFKai-SB" })` modify only `theme1.xml` byte content; all other 25 NTPU parts byte-equal to source after save.
- Establish dirty tracking as the canonical pattern for any future typed-model-incomplete OOXML parts.
- Fix `Header.fileName` / `Footer.fileName` multi-instance collapse so each typed header/footer references its actual archive file path.
- Fix `extractPeople` to parse `<w15:presenceInfo>` child element fully + provide GUID-based `person_id` with backward-compat to v3.4.0 callers.

**Non-Goals:**

- True byte-equal round-trip including ZIP CRC, entry order, compression dictionary timestamps. Achievable bar is file-content equality, not ZIP-level binary equality.
- Compile-time enforcement of mark-dirty discipline via protocol (e.g., `MutatesDocument`). Manual audit + grep-based test (`MarkDirtyCoverageTests`) is sufficient for v0.13.0; protocol-based enforcement is a future hardening change.
- Full typed-model parsing of `fontTable.xml` font entries. Skip-when-not-dirty preserves originals byte-for-byte; typed parsing is deferred until a font CRUD tool needs it.
- Full four-part comment metadata triplet auto-sync inside existing `insert_comment` / `reply_to_comment` / `resolve_comment` / `delete_comment` writers. Still deferred to v4.0 per `che-word-mcp v3.4.0` CHANGELOG.
- `che-pptx-mcp` adoption of dirty tracking. Separate change opened when PPTX equation tooling needs equivalent fidelity.
- Auto-rebuilding `[Content_Types].xml` Overrides for typed parts the typed model doesn't reference (e.g., orphan `header2-6.xml` files in NTPU v3.4.0 output). With `originalFileName` fix, typed model now correctly references each header — orphans become impossible.
- Migration of v3.4.0 callers using `person_id == display_name`. Dual-identity field strategy is the migration path; callers must switch to GUID-based `person_id` before v4.0.0 ships.

## Decisions

### Decision: Dirty tracking is `Set<String>` of OOXML part paths, not typed enum

**Choice**: `WordDocument` gains `internal var modifiedParts: Set<String>` where elements are full paths like `"word/document.xml"`, `"word/header1.xml"`, `"word/theme/theme1.xml"`. Public read-only access via computed property `public var modifiedPartsView: Set<String> { modifiedParts }` for testing. Every mutating method on `WordDocument` and its substructs calls `self.modifiedParts.insert(<path>)`. `DocxReader.read()` clears `modifiedParts` to empty as the final step before returning, so freshly loaded documents start clean.

**Rationale**: (1) `WordDocument` already has many distinct parts as separate fields with no uniform identifier — a `Set<String>` of paths gives a uniform mark/check API across all part types. (2) Adding a new typed part type doesn't require a new enum case + writer wiring + check-site update — caller just inserts the path. (3) Cross-module callers (e.g., `che-word-mcp` writing directly to `archiveTempDir/word/theme/theme1.xml`) can mark the path without touching `ooxml-swift` source. (4) python-docx, Apache POI, docx4j all use path-based dirty tracking — proven pattern.

**Alternatives considered**:

- **Typed enum** `enum DirtyPart { case document, styles, header(Int), footer(Int), comment, footnote, endnote, theme, people, webSettings, fontTable }`. Rejected: more type-safe but inflexible. Each new part type needs an enum case + writer wiring + check-site update across both packages. Cross-module callers (che-word-mcp writing theme1.xml) would need to import the enum from ooxml-swift.
- **Per-typed-field bool flags** `WordDocument.documentDirty: Bool, stylesDirty: Bool, fontTableDirty: Bool, ...`. Rejected: doesn't scale to multi-instance parts (would need `headersDirty: [String: Bool]`); 10+ fields on WordDocument is noise.
- **Snapshot-and-diff** at save time (compare typed model against original parsed-from-archive snapshot). Rejected: requires deep equality on every typed field, expensive; doesn't help when typed model can't represent all detail (e.g., font table 13 entries vs typed 3).

### Decision: `Header` and `Footer` gain `originalFileName: String?`; `fileName` becomes `originalFileName ?? type-based-default`

**Choice**: Add `public var originalFileName: String?` to both `Header` and `Footer` structs. `DocxReader.read()` populates it from each header/footer relationship's actual `Target` attribute in `_rels/document.xml.rels` (e.g., `header4.xml`). Existing `Header.fileName` / `Footer.fileName` computed properties become:

```swift
public var fileName: String {
    if let original = originalFileName { return original }
    switch type {
    case .default: return "header1.xml"
    case .first: return "headerFirst.xml"
    case .even: return "headerEven.xml"
    }
}
```

Newly-added headers/footers via `addHeader(text:type:)` / `addFooter(text:type:)` leave `originalFileName == nil` and use the existing type-based naming logic. **For overlay mode with multiple `.default` headers, each correctly references its own file** — so `headers.map { $0.fileName }` for an NTPU thesis returns `["header1.xml", "header2.xml", ..., "header6.xml"]` (6 distinct paths), not `["header1.xml"] × 6`.

**Rationale**: Minimum-invasive fix. Public API additive (nil default), existing callers work unchanged. Naming-from-archive is the only correct behavior — typed model can't invent unique names for parsed headers without breaking the existing `addHeader(type: .default)` API contract that promises `header1.xml`.

**Alternatives considered**:

- **Mutate `id` to encode position** (e.g., `rId8/header1` instead of `rId8`). Rejected: breaks rels semantics; consumers parsing rId expect plain rId strings.
- **Number-suffix the type-based default** (e.g., `header1.xml`, `header1_2.xml`, `header1_3.xml` for 3 default headers). Rejected: doesn't preserve original archive names; round-trip would rename files.
- **Make `addHeader` accept explicit `fileName` parameter**. Rejected: API breaking; doesn't help with preserving names of already-loaded headers.

### Decision: Overlay-mode writers SKIP for parts not in `modifiedParts`; scratch mode unchanged

**Choice**: `DocxWriter.writeAllParts(_, to:, overlayMode:)` becomes:

```swift
private static func writeAllParts(_ document: WordDocument, to tempDir: URL, overlayMode: Bool) throws {
    if overlayMode {
        // Per-part dirty checks
        if document.modifiedParts.contains("[Content_Types].xml") || hasNewTypedParts(document) {
            try writeContentTypes(to: tempDir, document: document, overlayMode: true)
        }
        if document.modifiedParts.contains("word/_rels/document.xml.rels") || hasNewTypedRels(document) {
            try writeDocumentRelationships(to: tempDir, document: document)
        }
        if document.modifiedParts.contains("word/document.xml") {
            try writeDocument(document, to: tempDir)
        }
        if document.modifiedParts.contains("word/styles.xml") {
            try writeStyles(document.styles, to: tempDir)
        }
        if document.modifiedParts.contains("word/fontTable.xml") {
            try writeFontTable(to: tempDir)
        }
        // Headers / footers iterate but skip when not in modifiedParts
        for header in document.headers where document.modifiedParts.contains("word/\(header.fileName)") {
            try writeHeader(header, to: tempDir)
        }
        for footer in document.footers where document.modifiedParts.contains("word/\(footer.fileName)") {
            try writeFooter(footer, to: tempDir)
        }
        // ... same pattern for footnotes, endnotes, comments, numbering, settings, app/core props
        // _rels/.rels is read-only; never re-emitted in overlay mode
    } else {
        // Scratch mode: existing behavior unchanged — every writer runs.
        try writeContentTypes(to: tempDir, document: document, overlayMode: false)
        try writeRelationships(to: tempDir)
        try writeDocumentRelationships(to: tempDir, document: document)
        try writeDocument(document, to: tempDir)
        try writeStyles(document.styles, to: tempDir)
        try writeSettings(to: tempDir)
        try writeFontTable(to: tempDir)
        // ... etc, all conditional on hasNumbering/hasHeaders/hasFooters/etc.
    }
}
```

**Rationale**: This is the only correct behavior — typed model regenerates lossy XML; for unmodified parts, the original tempDir copy is the only source of truth. Skipping in overlay mode preserves the original byte-for-byte. Scratch mode keeps existing behavior because there's no "original" to fall back to.

`hasNewTypedParts(document)` returns `true` when typed model contains parts NOT present in the original `[Content_Types].xml` (e.g., `insert_image_from_path` added a new media file). Triggers Content_Types overlay merge to include the new Override. Otherwise skip — original Content_Types remains intact.

**Alternatives considered**:

- **Always re-emit Content_Types via overlay merge (no dirty check)**. Rejected: harmless for correctness but wasteful — most no-edit save calls don't need to touch Content_Types.
- **Mark Content_Types as auto-dirty when any typed part changes**. Rejected: more bookkeeping; the `hasNewTypedParts` predicate is simpler and explicit.
- **Skip writeAllParts entirely in overlay mode if modifiedParts is empty**. Considered: optimization for pure no-op round-trip. Reject for now: zip-pack cost is the dominant cost, not the per-writer skip overhead. Add as future micro-optimization if profiling shows it matters.

### Decision: `#34` person_id GUID is BREAKING with backward-compat in v3.5.0

**Choice**: `list_people` returns BOTH:
- `person_id: String` — GUID parsed from `<w15:presenceInfo userId="S::EMAIL::GUID">` third segment after splitting on `::`. Falls back to author attribute when no GUID found (e.g., `<w15:presenceInfo>` absent or `userId` doesn't follow `S::email::guid` pattern).
- `display_name_id: String` — author attribute value (equals what v3.4.0 returned as `person_id`).

Plus newly populated fields: `display_name`, `email`, `color`, `provider_id`.

`update_person` and `delete_person` accept either `person_id` (GUID) or `display_name_id` (legacy author string) — handler tries to find the matching `<w15:person>` by checking both identifier types. v3.5.0 release notes flag dual-identity behavior. v4.0.0 will remove `display_name_id` entirely; callers must switch to GUID `person_id` by then.

**Rationale**: v3.4.0 already shipped `person_id == display_name`; some callers may have stored these. Ripping it out without migration breaks production users. Two-field strategy is the same migration pattern `che-word-mcp` uses for other identifier transitions (e.g., comment `id` vs `paraId`). Cost: one extra field in JSON output, one if-branch in update/delete handlers.

**Alternatives considered**:

- **Straight v4.0.0 BREAKING**. Rejected as gratuitous given v3.5.0 ships days after v3.4.0; users haven't had time to migrate; pre-emptive break burns trust.
- **New tool `list_people_v2` returning GUID-based, deprecate `list_people`**. Rejected: tool surface bloat; subsequent migration removes both anyway.
- **Always return GUID; document migration in CHANGELOG**. Rejected: silent BREAKING; v3.4.0 callers using person_id as dictionary key would silently key-collide or fail to look up authors.

### Decision: Single SDD change covers all 4 issues; no split

**Choice**: One Spectra change `che-word-mcp-true-byte-preservation` covers `#23 round-2` + `#32` + `#33` + `#34`. Not split into per-issue smaller changes.

**Rationale**: `#32` and `#33` are downstream consequences of the `Header.fileName` / `Footer.fileName` collapse (root cause shared with `#23` round-2). Fixing them requires the same `originalFileName` field addition. `#34` is technically independent (only touches `Server.swift` person handlers) but its fix lives in the same `Server.swift` regions affected by `#32`/`#33` watermark/page-number detection improvements — bundling reduces merge friction. Single SDD change ships together as one ooxml-swift v0.13.0 release + one che-word-mcp v3.5.0 release; users get all four fixes simultaneously.

**Alternatives considered**:

- **Three changes**: `che-word-mcp-dirty-tracking` (architecture), `che-word-mcp-header-footer-fileName-fix` (multi-instance), `che-word-mcp-people-presenceinfo` (#34 only). Rejected: coordination burden; `#32`/`#33` need both architecture + fileName fix; spec writes triplicate.
- **Split #34 into separate parallel change** since it's independent. Considered: viable if user wants `#34` shipped earlier. But Server.swift Phase2BCSmokeTests would need rebase coordination. Bundle is simpler.

### Decision: Test fixture is committed multi-header docx, not NTPU thesis

**Choice**: Create `packages/ooxml-swift/Tests/OOXMLSwiftTests/Fixtures/multi-header-footer.docx` (~30KB) — hand-crafted minimal docx containing 6 headers (4 default + 1 first + 1 even) with each header containing a unique recognizable string + 1 watermark VML shape; 4 footers with 1 containing `<w:fldSimple w:instr=" PAGE \\* MERGEFORMAT ">`; 1 `<w15:person>` with full `<w15:presenceInfo>` triple-segment userId. Plus `Tests/OOXMLSwiftTests/Fixtures/README.md` documenting how to rebuild the fixture if format conventions change.

**Rationale**: NTPU thesis is private (privacy + copyright + 5MB+ size). A 30KB fixture covers every code path in this change (multi-header collapse, watermark VML, page-number field, presenceInfo parsing) and runs in CI deterministically. Hand-crafting once is a 1-2 hour task; the fixture lives forever as regression guard.

**Alternatives considered**:

- **Use NTPU thesis as fixture**. Rejected: privacy / copyright / size.
- **Generate fixture programmatically at test setup**. Rejected: the thing being tested IS the writer, so generating with the writer is circular (output becomes byte-equal to input by construction, masking real bugs).
- **Reuse `minimal-multipart.docx` from round 1 (which doesn't exist — was deferred)**. Rejected: round 1 fixture was deferred; this change is the right time to commit a real binary fixture covering all needed cases.

## Risks / Trade-offs

- **Mark-dirty coverage gap** → if a typed-model mutator forgets to insert into `modifiedParts`, the corresponding part will silently NOT be re-emitted on save → caller's edits disappear. **Mitigation**: `MarkDirtyCoverageTests` enumerates all `WordDocument` mutating methods and asserts each one inserts the expected path; CI runs this on every PR. Plus grep-based audit of all `func` declarations matching `mutating func` or `func update*` / `func add*` / `func delete*` in WordDocument and substructs.

- **`hasNewTypedParts` correctness for image insertion** → `insert_image_from_path` adds a new entry to `document.images`; the new image needs both a `media/imageN.png` write AND a Content_Types Override Default extension. `hasNewTypedParts` must detect this and trigger Content_Types re-emit. **Mitigation**: dedicated test inserting a new image into a preserved-archive document and verifying Content_Types now contains the new media Override.

- **`Header.originalFileName` populated from rels Target — what if rels lacks Target?** Older Word versions or malformed docx may have rels without Target. **Mitigation**: gracefully fall back to `nil` (which falls through to type-based default). Test edge case.

- **`writeFontTable` skip in overlay mode means you can never UPDATE fontTable** → if a future tool wants to edit fontTable.xml, it must mark `"word/fontTable.xml"` dirty AND we'd need a document-aware writeFontTable. **Mitigation**: out of scope for this change; flag in CHANGELOG that fontTable editing requires a future change introducing document-aware writeFontTable.

- **`person_id` semantic switch confuses callers** → v3.4.0 caller scripts reading `list_people` results may use `person_id` as a primary key. v3.5.0 returning GUID instead silently changes the key space. **Mitigation**: dual `person_id` + `display_name_id` field strategy + CHANGELOG flagging; v4.0.0 deprecation timeline.

- **Test fixture binary in git** → `multi-header-footer.docx` ~30KB committed to git; over time may need updates as test scope grows. **Mitigation**: well under git LFS thresholds; rebuild procedure documented in `Tests/OOXMLSwiftTests/Fixtures/README.md`.

- **Round-trip byte-equality test sensitivity to ZIP packaging differences** → ZIPFoundation may produce different ZIP structure (entry order, compression dictionary) than the Word original. **Mitigation**: test asserts file-content equality at the per-entry level (extract both ZIPs, compare entry-by-entry), not raw ZIP byte equality. Documented as the achievable bar.

- **Phase 1 + Phase 2 ship as one release each** → `ooxml-swift v0.13.0` must ship before `che-word-mcp v3.5.0` can dep-bump. ~1 day bake time between. **Mitigation**: standard sequential release; no atomic coupling required.

- **Large diff in `DocxWriter.swift`** → adding overlay-mode dirty checks to ~10 writer call sites grows the diff substantially. **Mitigation**: refactor in a single PR with focused commits per writer; reviewer reads from top to bottom.

- **Existing 327 ooxml-swift tests / 68 che-word-mcp tests don't currently catch this bug** → because they use programmatic fixtures (synthesizes docx with the writer) which by construction produces the same output the writer emits. Round-trip byte equality on these IS true today even though the architecture is broken. **Mitigation**: NEW fixture-driven tests committed in this change explicitly test the broken paths; existing tests are kept as-is (still valuable for typed-model unit coverage).
