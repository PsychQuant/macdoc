## Why

`Header.toXML()` / `Footer.toXML()` re-emission strips VML watermarks, OLE objects, and any non-`w:drawing`/non-OMML run children. Triggered whenever overlay-mode `DocxWriter` writes a header/footer marked dirty (e.g., after [`update_all_fields`](https://github.com/PsychQuant/che-word-mcp/issues/42) on a doc with header SEQ fields, or any `update_header` call on a watermarked template).

Source audit during [#42](https://github.com/PsychQuant/che-word-mcp/issues/42) verification + [#52](https://github.com/PsychQuant/che-word-mcp/issues/52) `/spectra-discuss` traced the drop to `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift::parseRun` lines 850-878. `parseRun` only recognizes `w:t`, `w:drawing`, and `oMath`/`oMathPara` children; everything else (`w:pict`, `w:object`, `w:ruby`) is silently dropped. NTPU thesis VML watermarks live at `w:hdr` → `w:p` → `w:r` → `w:pict` → `v:shape` — the silent drop hits at the Run layer.

This change ships the Run-layer fix. Container-layer (`<w:tbl>` siblings of `<w:p>` in `w:hdr`) and Paragraph-layer (unknown children of `<w:p>`) drops are deferred as separate follow-ups — both rare in practice; will surface via `parseParagraph:630` debug-log telemetry when they fire.

Bundles `update_all_fields(isolatePerContainer: Bool = false)` opt-in flag (deferred from [#54](https://github.com/PsychQuant/che-word-mcp/issues/54) sub-finding #8). Once headers preserve VML+SEQ correctly, the global-vs-per-container counter sharing semantic becomes user-visible — the chapter-caption running header use case is the primary consumer.

## What Changes

- **NEW**: `Run.rawElements: [(name: String, xml: String)]?` carrier preserves unknown OOXML elements within a run by their original sibling-position index
- **MODIFIED**: `parseRun` now collects unknown child elements (anything except recognized typed kinds) into `rawElements`
- **MODIFIED**: `Run.toXML()` emits typed children + interleaves `rawElements` by position, byte-preserving the unknown portion
- **NEW**: `updateAllFields(isolatePerContainer: Bool = false)` opt-in flag — when `true`, SEQ counters reset at each container boundary (header/footer/footnote/endnote independent of body)
- **MODIFIED**: `che-word-mcp-field-equation-crud` spec — remove the v3.7.1 "header WITH SEQ + co-located VML/drawings still strips" known-limitation paragraph; add scenario covering preserved-watermark round-trip
- **BREAKING (effective)**: `update_all_fields` callers who relied on global counter sharing across body+header now get isolation when they explicitly pass `isolatePerContainer: true`. Default `false` preserves current behavior.

## Non-Goals

- **Container-layer raw-fragment preservation** (`<w:tbl>` / `<w:sdt>` siblings of `<w:p>` in `w:hdr`/`w:ftr`) — rare; defer until `parseContainerChildParagraphs:765` telemetry confirms real-world impact
- **Paragraph-layer raw-element preservation** (unknown children of `<w:p>`) — deferred; `parseParagraph:630` already has debug-only stderr logging that would surface live cases
- **Typed VML model** (e.g., `Run.pict: VMLPicture?` with parsed `v:shape` attributes) — out of scope; the generic carrier is sufficient for byte-preserving round-trip. Typed VML can be a follow-up if MCP tools need to query/manipulate watermarks programmatically
- **OLE object lifecycle** (extracting embedded `.xlsx`, `.bin`, etc.) — out of scope; round-trip preservation only
- **`isolatePerContainer` cross-section semantics** — flag isolates by container family (body/header/footer/footnote/endnote), NOT by Word section breaks within a container. Section-aware isolation deferred

## Capabilities

### New Capabilities

- `ooxml-header-footer-raw-element-preservation`: Run-layer raw-element carrier ensuring header/footer round-trip preserves VML watermarks, OLE objects, and other unknown OOXML constructs

### Modified Capabilities

- `che-word-mcp-field-equation-crud`: remove v3.7.1 known-limitation paragraph; add `update_all_fields(isolatePerContainer:)` parameter scenarios; add header-WITH-SEQ-and-VML preservation scenario

## Impact

- Affected specs: `ooxml-header-footer-raw-element-preservation` (new), `che-word-mcp-field-equation-crud` (modified)
- Affected code:
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/RunRawElementPreservationTests.swift`
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/HeaderFooterByteEqualityWithVMLTests.swift`
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/UpdateAllFieldsCounterIsolationTests.swift`
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Run.swift` (add `rawElements` field + interleaved `toXML()`)
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift` (`parseRun` collects unknown children)
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/WordDocument+UpdateAllFields.swift` (add `isolatePerContainer` parameter + per-container counter map)
  - Modified: `packages/ooxml-swift/CHANGELOG.md` (v0.14.0 entry)
  - Modified: `mcp/che-word-mcp/Package.swift` (bump dep `0.13.5` → `0.14.0`)
  - Modified: `mcp/che-word-mcp/CHANGELOG.md` (v3.8.0 entry)
  - Modified: `mcp/che-word-mcp/mcpb/manifest.json` (3.7.2 → 3.8.0)
  - Modified: `mcp/che-word-mcp/Sources/CheWordMCP/Server.swift` (`update_all_fields` MCP tool surface — add `isolate_per_container` parameter)
