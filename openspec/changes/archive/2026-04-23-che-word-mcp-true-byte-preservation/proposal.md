## Problem

Round 2 of `che-word-mcp#23`: the v0.12.0 + v3.3.0/v3.4.0 "preserve-by-default" architecture preserved part EXISTENCE in the unzip tempDir but did NOT preserve part CONTENT. `DocxWriter.writeAllParts()` unconditionally overwrites every typed-managed part on every save, regardless of whether the caller modified it. Real-world impact (NTPU thesis no-op round-trip):

- `header1.xml` 3923 bytes (with `<v:shape id="PowerPlusWaterMarkObject1">` watermark VML) → 318 bytes empty stub. Watermark gone.
- `fontTable.xml` 13 fonts (DFKai-SB / 華康中楷體 / PMingLiU / Microsoft JhengHei / Cambria Math / etc.) → 3 hardcoded fonts (Calibri / Calibri Light / Times New Roman). Chinese font fallback to Times New Roman — NTPU thesis format fatal violation.
- `[Content_Types].xml` 27 Override entries → 16. 11 declarations missing for `header2-6.xml` / `footer2-4.xml` / `endnotes.xml` / `footnotes.xml` / `commentsExtended.xml` (files exist in ZIP but unreferenced).

Three downstream sibling bugs surfaced from the same root architecture gap:

- **`che-word-mcp#32`** — `list_watermarks(NTPU)` returns `[]` despite 6 headers each containing `PowerPlusWaterMarkObject` VML shape.
- **`che-word-mcp#33`** — `list_footers[*].has_page_number` returns `false` for footer3.xml that contains `<w:fldSimple w:instr=" PAGE">`.
- **`che-word-mcp#34`** — `list_people` returns `email/color/provider_id` all `null`; `person_id` uses display name string instead of stable GUID. `<w15:presenceInfo>` child element completely ignored.

## Root Cause

**Three layered architectural gaps** in `ooxml-swift` v0.12.x:

1. **DocxWriter has no dirty tracking**. `writeAllParts()` at `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxWriter.swift:30-75` calls every typed-part writer (`writeFontTable`, `writeStyles`, `writeHeader`, `writeFooter`, `writeNumbering`, `writeSettings`, `writeAppProperties`, `writeCoreProperties`) on every save, even in overlay mode. Each typed writer regenerates from the lossy typed model, destroying preserved content in `archiveTempDir`.

2. **`writeFontTable(to baseURL:)` accepts no document parameter**. It hardcodes 3 fonts (Calibri, Times New Roman, Calibri Light). The original `fontTable.xml`'s 13-font declarations are unreachable from the typed model — DocxReader doesn't parse non-default font entries into a typed field.

3. **`Header.fileName` and `Footer.fileName` collapse to type-based fixed strings**. `Header.swift:94-100` returns `"header1.xml"` for ALL `.default` type headers; `Footer.swift:143-147` returns `"footer1.xml"` for ALL `.default` type footers. NTPU thesis has 6 default headers (rId8/rId13/rId10/rId12/rId7/rId6) and 4 default footers — the typed model collapses all 6 headers to a single `header1.xml` reference. Consequences: (a) `list_watermarks` reads the same file 6 times instead of touching `header2-6.xml`; (b) `delete_header` can't distinguish them; (c) `writeAllParts` overwrites `header1.xml` with the last default header's stub, leaving `header2-6.xml` orphaned in the tempDir but unreferenced in `[Content_Types].xml`.

Plus an independent bug in `che-word-mcp`:

4. **`extractPeople` regex ignores `<w15:presenceInfo>` child element**. `mcp/che-word-mcp/Sources/CheWordMCP/Server.swift` extractPeople uses `<w15:person\s+[^>]*\bw15:author="([^"]+)"` which only captures the outer attribute. The `userId="S::EMAIL::GUID"` triple-segment value, `providerId` attribute, and optional `w15:color` are all dropped. The decision to use `display_name` as `person_id` (instead of the durable GUID parsed from `userId`) breaks cross-session author identity stability.

## Proposed Solution

Adopt the industry-standard **dirty-tracking + selective-overwrite** pattern (python-docx, Apache POI, docx4j) in three layers:

### Layer 1: ooxml-swift v0.13.0 — dirty tracking foundation

- `WordDocument.modifiedParts: Set<String>` tracks OOXML part paths the typed model has mutated (e.g., `"word/document.xml"`, `"word/header1.xml"`, `"word/theme/theme1.xml"`).
- Every mutating method on `WordDocument` (and its substructs) inserts the corresponding part path: `appendParagraph` / `replaceText` / `insertParagraph` / `updateParagraph` / `deleteParagraph` → `"word/document.xml"`; `addStyle` / `updateStyle` / `deleteStyle` → `"word/styles.xml"`; `addHeader` / `updateHeader` → `"word/<header.fileName>"`; etc.
- `DocxReader.read()` clears `modifiedParts` to empty after parsing, guaranteeing freshly-loaded documents start clean.
- `DocxWriter.write()` in overlay mode (`document.archiveTempDir != nil`) wraps every typed-part writer in a dirty check: `if document.modifiedParts.contains("<part path>") { try writeXxx(...) }`. Skipped writers leave the original tempDir file untouched. Scratch mode (`archiveTempDir == nil`) behavior is unchanged — every writer still runs.

### Layer 2: ooxml-swift v0.13.0 — Header / Footer fileName preservation

- Add `public var originalFileName: String?` to both `Header` and `Footer` structs.
- `DocxReader.read()` populates `originalFileName` from each header/footer relationship's actual `Target` attribute (e.g., `"header4.xml"` instead of always returning the type-based default).
- `Header.fileName` / `Footer.fileName` become `originalFileName ?? type-based-default`. Newly-added headers/footers via `addHeader` / `addFooter` leave `originalFileName == nil` and use the existing type-based naming logic.
- `Content_Types.xml` overlay merge now correctly preserves Override entries for `header2-6.xml` / `footer2-4.xml` (because `typedPartDescriptors` enumerates each header/footer with its actual fileName).

### Layer 3: che-word-mcp v3.5.0 — fixes for #32 #33 #34 + mark-dirty wiring

- `Server.swift` archive-write helpers (`writeThemeXML`, `writeArchivePart` for people/webSettings) call BOTH `documentDirtyState[docId] = true` AND `doc.modifiedParts.insert(<path>)` to keep both tracking surfaces aligned.
- `extractPeople` rewritten to parse `<w15:person>` outer block + `<w15:presenceInfo>` child element; splits `userId="S::EMAIL::GUID"` on `::` to extract email + GUID; extracts `providerId` attribute and optional `w15:color` attribute.
- `list_people` returns dual identity: `person_id` (now GUID, fallback to author when no GUID found) + `display_name_id` (= author attribute, equals what v3.4.0 returned as `person_id`). Both `update_person` and `delete_person` accept either identifier. v4.0.0 will remove `display_name_id`.
- `headerHasWatermark` and `footerHasPageNumber` regex strengthening — verified against NTPU-style fixture XMLs (multi-line, three-segment field, namespace prefixes).

### Acceptance test

NTPU thesis no-op round-trip:

1. `open_document(path: NTPU.docx)` → 26 ZIP entries in archiveTempDir, `modifiedParts` empty.
2. (no edits)
3. `save_document(path: out.docx)` → overlay mode iterates typed-part writers; all skip because `modifiedParts` empty; ZIP repackaged from untouched tempDir.
4. `out.docx` ZIP entry list equals input; for every entry, byte content equals input (exception: ZIP CRC + timestamps may differ — semantic-equal at file-content level).

After `update_theme_fonts(minor: { ea: "DFKai-SB" })`:

1. `modifiedParts == {"word/theme/theme1.xml"}`.
2. `save_document` re-emits only theme1.xml; other 25 parts byte-equal to input.

## Non-Goals (optional)

- Full byte-equality including ZIP CRC + entry order + timestamps. Out of scope — file-content equality is the achievable + verifiable bar.
- Repackaging existing `WordDocument` mutator coverage as a protocol (`MutatesDocument`) for compile-time enforcement of mark-dirty calls. Audit by grep-then-fix is sufficient for v0.13.0; protocol enforcement deferred to a future hardening change.
- Parsing every existing Word version's `<w:font>` schema variants in `fontTable.xml` for typed model representation. Skip-when-not-dirty is the v0.13.0 fix; full typed parsing is deferred until a future tool needs `fontTable` CRUD.
- Auto-syncing the four-part comment metadata triplet (`commentsExtended.xml` / `commentsExtensible.xml` / `commentsIds.xml` / `comments.xml`) inside existing `insert_comment` etc. writers. Still deferred to v4.0 per `che-word-mcp v3.4.0` CHANGELOG.
- `che-pptx-mcp` adoption of the same dirty tracking. Separate change opened when PPTX equation tooling lands.
- Automatic migration of v3.4.0 callers using `person_id == display_name`. Backward compat via dual identity field is the migration strategy; callers SHALL switch to GUID-based `person_id` before v4.0.0.

## Success Criteria

- **Round-trip byte-preservation**: NTPU thesis `read → write` (no edits) produces an output `.docx` whose ZIP entries equal the input set, and for every typed-managed part path NOT in `modifiedParts`, the output entry's file content is byte-equal to the input entry's. Verified by automated test using committed multi-header fixture.
- **Selective regeneration**: After exactly one `update_theme_fonts` call, `modifiedParts == {"word/theme/theme1.xml"}` and `save_document` re-emits only theme1.xml; all other typed parts (document.xml, styles.xml, fontTable.xml, headers, footers, comments, footnotes, endnotes) remain byte-equal to input.
- **`#32` watermark detection**: `list_watermarks` on NTPU thesis returns 6 entries (one per header containing `PowerPlusWaterMarkObject` VML shape); `list_headers[*].has_watermark == true` for those headers.
- **`#33` page number detection**: `list_footers` on NTPU thesis returns `has_page_number == true` for footer3.xml (which contains `<w:fldSimple w:instr=" PAGE \\* MERGEFORMAT ">` or three-segment `<w:fldChar>` + `<w:instrText>PAGE</w:instrText>` + `<w:fldChar>`).
- **`#34` people parsing**: `list_people` on NTPU thesis returns `email = "adam.kuo@yuanta.com.vn"`, `provider_id = "AD"`, `person_id = "99b8ea77-3e4d-4917-a8fa-259313a0e4b9"` (GUID), `display_name_id = "Kuo Chia Yuan (Senior Manager, Corporate Planning - HO)"` (legacy author attribute).
- **No regression**: existing 327 ooxml-swift tests + 68 che-word-mcp tests still pass after fix.
- **`Header.fileName` multi-instance correctness**: A document with 6 default headers (rId8/rId13/rId10/rId12/rId7/rId6) has `headers.map { $0.fileName }` returning 6 distinct filenames matching the original ZIP paths (e.g., `["header1.xml", "header2.xml", "header3.xml", "header4.xml", "header5.xml", "header6.xml"]`).

## Impact

- Affected code:
  - Modified:
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Header.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Footer.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxWriter.swift
    - packages/ooxml-swift/Tests/OOXMLSwiftTests/RoundTripFidelityTests.swift
    - packages/ooxml-swift/CHANGELOG.md
    - mcp/che-word-mcp/Package.swift
    - mcp/che-word-mcp/Sources/CheWordMCP/Server.swift
    - mcp/che-word-mcp/Tests/CheWordMCPTests/HeadersFootersToolsTests.swift
    - mcp/che-word-mcp/Tests/CheWordMCPTests/Phase2BCSmokeTests.swift
    - mcp/che-word-mcp/CHANGELOG.md
    - mcp/che-word-mcp/mcpb/manifest.json
  - New:
    - packages/ooxml-swift/Tests/OOXMLSwiftTests/MarkDirtyCoverageTests.swift
    - packages/ooxml-swift/Tests/OOXMLSwiftTests/MultiHeaderFooterFixtureTests.swift
    - mcp/che-word-mcp/Tests/CheWordMCPTests/PeoplePresenceInfoTests.swift
  - Removed: (none)
- Affected specs: modify `ooxml-roundtrip-fidelity` (add dirty tracking requirements), modify `docx-container-parsing` (add `originalFileName` preservation), modify `che-word-mcp-headers-footers-tools` (multi-instance watermark detection), modify `che-word-mcp-people-tools` (presenceInfo parsing + GUID person_id), modify `ooxml-content-insertion-primitives` (overlay-mode skip-when-not-dirty for global writers).
- Affected MCP tool surface: `list_watermarks` / `list_headers.has_watermark` / `list_footers.has_page_number` / `list_people` semantics changes (more accurate + new fields). `update_person` / `delete_person` accept dual identity.
- Build sequence: (1) `ooxml-swift` v0.13.0 release → (2) `che-word-mcp` v3.5.0 release with dep bump.
- Closes: `PsychQuant/che-word-mcp#23` (round 2), `#32`, `#33`, `#34`.
