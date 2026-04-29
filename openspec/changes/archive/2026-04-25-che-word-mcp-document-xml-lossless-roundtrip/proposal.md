## Why

`save_document` silently corrupts `word/document.xml` on every body-mutating MCP call ([che-word-mcp#56](https://github.com/PsychQuant/che-word-mcp/issues/56), P0). A trivial `open → insert_paragraph → save` on a typical Word document strips 32 of 34 namespace declarations from `<w:document>` root (libxml2 reports unbound prefix), wipes 100% of `<w:bookmarkStart>` bookmarks, and drops 354 `<w:t>` text nodes (191 unique strings — TOC anchor text, cross-reference placeholders, table captions, math notation). All other 41 OOXML parts byte-equal — only `document.xml` itself becomes invalid.

The bug ships in v3.12.0 and blocks every real-world `open → edit → save` workflow (NTPU thesis rescue, contract redline). Three orthogonal root causes — the writer hardcodes minimal namespaces, the reader never parses bookmarks, and the reader never parses the structural wrappers (`<w:hyperlink>`, `<w:fldSimple>`, `<mc:AlternateContent>`) that hold the dropped text. Same shape as v3.8.0 (#52) Header/Footer raw-element preservation, applied at three layers higher.

## What Changes

- **Document root namespace preservation**: `WordDocument` SHALL expose `documentRootAttributes: [String: String]` capturing every `xmlns:*` declaration plus `mc:Ignorable` from the source `<w:document>` element. Writer SHALL emit these verbatim on save (fall back to `xmlns:w` + `xmlns:r` only when the map is empty for create-from-scratch documents).
- **Bookmark Reader parsing**: `DocxReader` SHALL parse `<w:bookmarkStart w:id w:name/>` and `<w:bookmarkEnd w:id/>` while walking `<w:p>` children and populate the existing `Paragraph.bookmarks: [Bookmark]` field (Writer side already emits correctly).
- **Wrapper hybrid model** (typed editable surface + raw passthrough escape hatch):
  - `Hyperlink`: gain `runs: [Run]`, `rawAttributes: [String: String]`, `rawChildren: [String]`. The existing `text: String` becomes a computed property `runs.map { $0.text }.joined()` for backward compatibility — zero breaking to 218 existing MCP tools.
  - `FieldSimple` (new model type): `instr: String`, `runs: [Run]`, `rawAttributes: [String: String]`. Typed runs ensure `replace_text` and other content tools work inside SEQ Table captions, REF cross-references, and TOC entries.
  - `AlternateContent` (new model type): `rawXML: String` (verbatim preservation) plus `fallbackRuns: [Run]` (content from `<mc:Fallback>` extracted for search/replace). Documented trade-off: edits to `fallbackRuns` may diverge from `<mc:Choice>` content (Word handles reconciliation).
- **`<w:p>` child schema completeness**: enumerate the ECMA-376 `<w:p>` child element table in full. Each child SHALL have either a typed model OR a raw-carrier model with a `position: Int` field. New raw-carrier types: `BookmarkRangeMarker`, `CommentRangeMarker`, `PermissionRangeMarker`, `ProofErrorMarker`, `SmartTagBlock`, `CustomXmlBlock`, `BidiOverrideBlock`. Lossless coverage SHALL be verified against an NTPU-thesis-class real-world fixture.
- **Order preservation via parallel arrays + position index**: every paragraph child type (Run, Bookmark, Hyperlink, FieldSimple, AlternateContent, range markers, etc.) SHALL gain a `position: Int` field. Reader SHALL assign positions in source order. Writer SHALL collect children from all parallel arrays, sort by `position`, and emit in order. No enum refactor of `Paragraph.children`; existing `paragraph.runs[i]` access patterns in 218 MCP tools SHALL continue to work unchanged.
- **Lossless guarantee scope**: the round-trip lossless requirement SHALL cover BOTH (a) byte-level `open → save` no-op AND (b) tool-mediated `open → edit → save` (so `replace_text`, `format_text`, `update_paragraph` etc. cannot silently fail to find content located inside structural wrappers). Raw-only carriers fail (b); the hybrid model satisfies both.
- **Test fixture dual-track**:
  - `LosslessRoundTripFixtureBuilder` extends the existing `SDTFixtureBuilder` pattern and synthesizes a 50–100 KB docx with at least 5 bookmarks, 3 hyperlinks (URL/anchor/email mix), 2 `<w:fldSimple>` blocks (SEQ + REF), 1 `<mc:AlternateContent>` math block, and 10+ namespaces declared on root. Used for CI regression coverage.
  - `mcp/che-word-mcp/test-files/*.docx` smoke-test pattern (gitignored, mirrors the existing `.note` fixture pattern from #81). The smoke test runs `xmllint --noout` validation, bookmark/hyperlink/`fldSimple` count diffs, and a sum-of-`<w:t>`-content hash diff. The test SHALL `XCTSkip` when no fixture file is present.

## Capabilities

### New Capabilities

- `ooxml-paragraph-child-schema-coverage`: codifies the requirement that every legal `<w:p>` child element from ECMA-376 has either a typed model or a raw-carrier model with a `position: Int` field, so lossless ordering is preserved across Reader → mutate → Writer cycles.

### Modified Capabilities

- `ooxml-roundtrip-fidelity`: extends lossless guarantee to cover document.xml root namespace preservation, bookmark preservation, structural wrapper preservation, and tool-mediated edit safety (not just byte-level no-op).
- `ooxml-document-part-mutations`: adds Reader parsing for `<w:bookmarkStart>` / `<w:bookmarkEnd>`, `<w:hyperlink>` (run children + raw attrs/children), `<w:fldSimple>` (typed model), `<mc:AlternateContent>` (raw + fallback runs), and the seven raw-carrier types listed above.

## Impact

- Affected specs:
  - `openspec/specs/ooxml-paragraph-child-schema-coverage/spec.md` (new)
  - `openspec/specs/ooxml-roundtrip-fidelity/spec.md` (modified — new requirements added)
  - `openspec/specs/ooxml-document-part-mutations/spec.md` (modified — new Reader requirements added)
- Affected code:
  - Modified:
    - `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift` (~600 LoC additions for bookmark + hyperlink + fldSimple + AlternateContent + raw-carrier parsing, position assignment)
    - `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxWriter.swift` (writeDocument rebuilds root open tag from documentRootAttributes; child sort-by-position before emit)
    - `packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift` (new field documentRootAttributes)
    - `packages/ooxml-swift/Sources/OOXMLSwift/Models/Paragraph.swift` (new parallel arrays for fieldSimples / alternateContents / range markers; toXML refactor to sort-by-position emit)
    - `packages/ooxml-swift/Sources/OOXMLSwift/Models/Hyperlink.swift` (add runs / rawAttributes / rawChildren / position; convert text to computed property)
    - `packages/ooxml-swift/Sources/OOXMLSwift/Models/Run.swift` (add position field)
    - `packages/ooxml-swift/Sources/OOXMLSwift/Models/Bookmark.swift` (add position field)
    - `packages/ooxml-swift/CHANGELOG.md` (v0.19.0 entry)
    - `mcp/che-word-mcp/Package.swift` (bump ooxml-swift dep to 0.19.0)
    - `mcp/che-word-mcp/CHANGELOG.md` (v3.13.0 entry)
    - `mcp/che-word-mcp/mcpb/manifest.json` (version bump)
    - `mcp/che-word-mcp/.gitignore` (add `test-files/*.docx` to exclude binary fixtures while keeping the `.gitkeep` marker tracked)
  - New:
    - `packages/ooxml-swift/Sources/OOXMLSwift/Models/FieldSimple.swift`
    - `packages/ooxml-swift/Sources/OOXMLSwift/Models/AlternateContent.swift`
    - `packages/ooxml-swift/Sources/OOXMLSwift/Models/ParagraphChildMarkers.swift` (BookmarkRangeMarker, CommentRangeMarker, PermissionRangeMarker, ProofErrorMarker, SmartTagBlock, CustomXmlBlock, BidiOverrideBlock)
    - `packages/ooxml-swift/Tests/OOXMLSwiftTests/DocumentXmlLosslessRoundTripTests.swift`
    - `packages/ooxml-swift/Tests/OOXMLSwiftTests/Fixtures/LosslessRoundTripFixtureBuilder.swift`
    - `mcp/che-word-mcp/Tests/CheWordMCPTests/RealWorldDocxRoundTripSmokeTests.swift`
  - Removed: (none)
