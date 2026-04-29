## Why

`che-word-mcp`'s `save_document` violates OOXML round-trip fidelity in a way that silently destroys document structure. The `ooxml-swift` `DocxReader.read()` extracts the source `.docx` ZIP into a tempDir, parses only the parts it knows about into the typed `WordDocument` model, then `defer cleanup` deletes the tempDir before any write happens. `DocxWriter.write()` re-emits a fresh ZIP from typed fields only — so any part outside the typed surface is byte-for-byte lost on save. Quantified impact from issue #23 evidence (NTPU thesis fixture): `word/` parts 23 → 6, `[Content_Types].xml` overrides 27 → 8, all 6 headers + 4 footers + entire `theme/` folder + `endnotes.xml` + `footnotes.xml` + `commentsExtended/Extensible/Ids.xml` + `people.xml` + `webSettings.xml` deleted; `fontTable.xml` 13 fonts → 3 (DFKai-SB / 華康中楷體 / PMingLiU / Microsoft JhengHei / Cambria Math all stripped); `<w:tblStyle>` references inside tables broken. Visible consequences: watermark gone, Chinese fonts fall back to Times New Roman (NTPU thesis format fatal violation), table styles revert to default, page numbers disappear.

The same lossy architecture blocks the entire `OOXML parts CRUD completeness` milestone (#24-#31, 8 enhancement issues): adding CRUD APIs for theme / headers / footers / footnotes / endnotes / commentsExtended / people / webSettings is meaningless until the writer preserves those parts on save. Per-issue diagnoses cross-referenced this single root cause, so all 9 issues are unified under one spec change.

## What Changes

- **BREAKING (semantic, non-API)**: `ooxml-swift` `DocxReader.read()` SHALL stop deleting the unzip tempDir at end-of-call. The tempDir SHALL be retained on the returned `WordDocument` instance and freed only by an explicit `WordDocument.close()` call (or via `deinit`). Callers that hold a `WordDocument` longer than expected will incur tempDir disk usage; callers that forgot to call `close()` will leak tempDirs until process exit.
- **NEW**: `WordDocument` gains a private `archiveTempDir: URL?` property and a public `close()` method. Documents created from `DocxReader.read()` carry the tempDir; documents created via `WordDocument(...)` initializer (the `create_document` MCP tool path) have `archiveTempDir == nil` and `DocxWriter.write()` falls back to today's scratch-tempDir behavior.
- **MODIFIED**: `DocxWriter.write()` SHALL detect `archiveTempDir != nil` and switch to **overlay mode** — overwrite typed-model parts (document.xml, styles.xml, headers, footers, footnotes, endnotes, comments, images, fontTable) directly into the preserved tempDir, then `ZipHelper.zip(tempDir, dest)`. This preserves all unknown parts (theme, webSettings, people, commentsExtended/Extensible/Ids, tableStyles) byte-for-byte.
- **NEW**: `Content_Types.xml` overlay merge — preserve original `<Override>` entries for unknown PartNames; remove duplicates for typed parts; add Overrides for newly-added typed parts (e.g., a new image inserted via `insert_image`).
- **NEW**: `RelationshipIdAllocator` — a stateful allocator that scans the original `_rels/document.xml.rels` for already-used `rId` values and returns `max + 1` for newly added relationships, replacing the naive `headers.count + footers.count + ...` counter at `DocxWriter.swift:238` that collides with preserved original rels.
- **NEW MCP tools** (Phase 2A — v3.3.0): `get_theme`, `update_theme_fonts`, `update_theme_color`, `set_theme`, `list_headers`, `get_header`, `delete_header`, `list_watermarks`, `get_watermark`, `list_footers`, `get_footer`, `delete_footer`. Closes #28 #26 #27.
- **NEW MCP tools** (Phase 2B — v3.4.0): `list_comment_threads`, `get_comment_thread`, `sync_extended_comments`, `list_people`, `add_person`, `update_person`, `delete_person`. Closes #29 #30.
- **NEW MCP tools** (Phase 2C — v3.5.0): `get_endnote`, `update_endnote`, `get_footnote`, `update_footnote`, `get_web_settings`, `update_web_settings`. Closes #24 #25 #31.
- **NEW regression test fixture**: `Tests/OOXMLSwiftTests/Fixtures/minimal-multipart.docx` — minimal docx containing 1 header + 1 footer + theme1.xml + people.xml + webSettings.xml + 1 image; CI test reads, writes without modification, and asserts entry list equality.

## Non-Goals (optional)

- Typed-model parsing for `commentsExtensible.xml`, `commentsIds.xml`, `tableStyles.xml`, `fontTable.xml` non-East-Asian entries. These parts are preserved opaquely via the tempDir overlay; full typed parsing is deferred until a future change brings a CRUD API that needs them.
- In-memory `[String: Data]` archive map. Rejected in `/spectra-discuss` because tempDir is already on disk for free, in-memory adds 5-50MB RAM per open document, and ZipHelper already walks tempDirs.
- Synchronous lazy-clean strategy for tempDirs (e.g., LRU cache evicting tempDirs after N opens). Out of scope; explicit `close()` covers all current callers.
- Single monolithic v3.3.0 release shipping all 8 CRUD tools. Phased ship (2A → 2B → 2C) lets users get the high-value thesis-fixing tools (theme/header/footer) within ~1 week of Phase 1.
- `che-pptx-mcp` adoption of the same overlay pattern. Separate change opened when PPTX equation tooling needs equivalent fidelity.
- Repackaging existing `WordDocument` consumers (e.g., `word-to-md-swift` `WordConverter`) to call `close()`. Read-only converters can leak tempDirs in a one-shot CLI (`macdoc convert`) since the process exits anyway; this is acceptable until a long-running consumer needs cleanup.

## Capabilities

### New Capabilities

- `ooxml-roundtrip-fidelity`: The OOXML container `read → modify → write` cycle SHALL preserve every part (`<Override>` entry in `[Content_Types].xml`) that was present in the input, byte-for-byte equal for parts the typed model did not modify. Defines the tempDir-overlay architecture, `WordDocument.close()` lifecycle, `RelationshipIdAllocator`, and `Content_Types.xml` overlay merge rules.
- `che-word-mcp-theme-tools`: MCP tools for reading and writing OOXML theme (`word/theme/theme1.xml`): `get_theme`, `update_theme_fonts`, `update_theme_color`, `set_theme` — covering major/minor font slots (latin/ea/cs + script variants), color scheme (accent1-6 + hyperlink + followedHyperlink), and a full-XML escape hatch.
- `che-word-mcp-headers-footers-tools`: MCP tools enumerating, inspecting, and removing existing headers/footers and watermarks from a document: `list_headers`, `get_header`, `delete_header`, `list_watermarks`, `get_watermark`, `list_footers`, `get_footer`, `delete_footer`. Builds on existing `add_header` / `update_header` / `add_footer` / `update_footer` insertion tools.
- `che-word-mcp-comment-thread-tools`: MCP tools for the modern Word comment thread metadata triplet: `list_comment_threads`, `get_comment_thread`, `sync_extended_comments`. Plus mandatory rewrite of existing `insert_comment` / `reply_to_comment` / `resolve_comment` / `delete_comment` to update `commentsExtended.xml`, `commentsExtensible.xml`, `commentsIds.xml` consistently with `comments.xml`.
- `che-word-mcp-people-tools`: MCP tools managing `word/people.xml` comment author records: `list_people`, `add_person`, `update_person`, `delete_person`. Plus mandatory rewrite of `insert_comment` / `reply_to_comment` to auto-create a `<w15:person>` record when an author name is not yet registered.
- `che-word-mcp-notes-update-tools`: MCP tools for in-place editing of existing endnotes and footnotes: `get_endnote`, `update_endnote`, `get_footnote`, `update_footnote`. Replaces the current delete-then-insert workaround that breaks endnote/footnote ID stability.
- `che-word-mcp-web-settings-tools`: MCP tools managing `word/webSettings.xml` Web View settings (`<w:optimizeForBrowser>`, `<w:relyOnVML>`, `<w:allowPNG>`, `<w:doNotSaveAsSingleFile>`, encoding fallback): `get_web_settings`, `update_web_settings` (partial update by key).

### Modified Capabilities

- `docx-container-parsing`: `DocxReader.read()` SHALL retain the unzip tempDir on the returned `WordDocument` rather than deleting it via `defer cleanup`; `WordDocument` SHALL expose `close()` to release the tempDir; container-level coverage SHALL include preservation (round-trip without typed parsing) of all parts not currently in scope of explicit Reader requirements.
- `ooxml-content-insertion-primitives`: `DocxWriter.write()` SHALL switch to overlay mode when `WordDocument.archiveTempDir != nil`, overwriting typed-model parts in the preserved tempDir and zipping the result; the `Content_Types.xml` and `_rels/document.xml.rels` builders SHALL merge typed-model state with preserved original entries via `RelationshipIdAllocator` and the overlay merge algorithm.
- `che-word-mcp-insertion-tools`: existing `insert_comment` / `reply_to_comment` / `resolve_comment` / `delete_comment` SHALL update the comment metadata triplet (`commentsExtended.xml`, `commentsExtensible.xml`, `commentsIds.xml`) and create / update corresponding `<w15:person>` records in `people.xml` whenever they touch comment metadata; existing `add_header` / `update_header` / `add_footer` / `update_footer` SHALL allocate `rId` values via `RelationshipIdAllocator` rather than naive count-based generation.

## Impact

- Affected specs: 1 new (`ooxml-roundtrip-fidelity`) + 6 new MCP-tool capability specs (theme / headers-footers / comment-threads / people / notes-update / web-settings) + 3 modified (`docx-container-parsing`, `ooxml-content-insertion-primitives`, `che-word-mcp-insertion-tools`)
- Affected code:
  - Modified:
    - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxWriter.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/IO/ZipHelper.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift
    - packages/ooxml-swift/CHANGELOG.md
    - packages/ooxml-swift/Package.swift
    - mcp/che-word-mcp/Package.swift
    - mcp/che-word-mcp/Sources/CheWordMCP/Server.swift
    - mcp/che-word-mcp/CHANGELOG.md
    - mcp/che-word-mcp/mcpb/manifest.json
  - New:
    - packages/ooxml-swift/Sources/OOXMLSwift/IO/PreservedArchive.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/IO/RelationshipIdAllocator.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/IO/ContentTypesOverlay.swift
    - packages/ooxml-swift/Tests/OOXMLSwiftTests/RoundTripFidelityTests.swift
    - packages/ooxml-swift/Tests/OOXMLSwiftTests/Fixtures/minimal-multipart.docx
    - mcp/che-word-mcp/Tests/CheWordMCPTests/ThemeToolsTests.swift
    - mcp/che-word-mcp/Tests/CheWordMCPTests/HeadersFootersToolsTests.swift
    - mcp/che-word-mcp/Tests/CheWordMCPTests/CommentThreadsToolsTests.swift
    - mcp/che-word-mcp/Tests/CheWordMCPTests/PeopleToolsTests.swift
    - mcp/che-word-mcp/Tests/CheWordMCPTests/NotesUpdateToolsTests.swift
    - mcp/che-word-mcp/Tests/CheWordMCPTests/WebSettingsToolsTests.swift
  - Removed: (none)
- Affected MCP tool surface: 21 new MCP tools (4 theme + 8 headers/footers + 3 comment threads + 4 people + 4 notes update + 2 web settings); 8 existing tools modified (`insert_comment`, `reply_to_comment`, `resolve_comment`, `delete_comment`, `add_header`, `update_header`, `add_footer`, `update_footer`)
- Build sequence (mandatory): (1) `ooxml-swift` v0.12.0 release with Phase 1 round-trip foundation → (2) `che-word-mcp` v3.3.0 (Batch 2A theme + headers/footers) → (3) `che-word-mcp` v3.4.0 (Batch 2B comment threads + people) → (4) `che-word-mcp` v3.5.0 (Batch 2C notes update + web settings). Each step requires the prior tag on GitHub.
- Closes: `PsychQuant/che-word-mcp#23`, `PsychQuant/che-word-mcp#24`, `PsychQuant/che-word-mcp#25`, `PsychQuant/che-word-mcp#26`, `PsychQuant/che-word-mcp#27`, `PsychQuant/che-word-mcp#28`, `PsychQuant/che-word-mcp#29`, `PsychQuant/che-word-mcp#30`, `PsychQuant/che-word-mcp#31` (entire `OOXML parts CRUD completeness` milestone + foundational P0 bug).
