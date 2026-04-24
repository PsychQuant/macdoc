## MODIFIED Requirements

### Requirement: update_all_fields MCP tool recomputes SEQ counters across the document

The `che-word-mcp` server SHALL provide an `update_all_fields(doc_id, isolate_per_container?)` MCP tool that calls `WordDocument.updateAllFields(isolatePerContainer:)` and returns a summary. The response SHALL include the per-identifier final counter values and the total count of fields updated.

The `isolate_per_container` parameter SHALL default to `false` (preserves prior global-counter-sharing behavior across all container families). When set to `true`, SEQ counters SHALL reset at each container family boundary: body, each `Header` instance, each `Footer` instance, the footnotes collection, and the endnotes collection each maintain independent counter dictionaries. Body's `SEQ Figure` increments do NOT contribute to a header's `SEQ Figure` counter when isolation is enabled.

When the underlying call to `WordDocument.updateAllFields` rewrites a SEQ field's cached value in a header or footer that contains co-located VML watermarks (`<w:pict>`), OLE objects (`<w:object>`), or other unknown OOXML constructs, the saved `word/headerN.xml` / `word/footerN.xml` SHALL preserve the unknown portion byte-for-byte (delegated to the `ooxml-header-footer-raw-element-preservation` capability).

#### Scenario: Update renumbers captions after insertion

- **WHEN** a document has SEQ-based figures numbered `1`, `2`, `3` and a new figure is inserted between figure 1 and figure 2 (with initial cached `"1"`), then `update_all_fields(doc_id)` is called
- **THEN** the response indicates `Figure: 4` final counter and the four figures' cached results are now `"1"`, `"2"`, `"3"`, `"4"` in document order

#### Scenario: Default behavior shares counters across containers

- **GIVEN** a document with body containing 3 `SEQ Figure` fields and a header containing 1 `SEQ Figure` field
- **WHEN** `update_all_fields(doc_id)` is called WITHOUT the `isolate_per_container` parameter (or with explicit `false`)
- **THEN** the body's three `Figure` counters become `1`, `2`, `3` and the header's `Figure` counter becomes `4` (global sharing)
- **AND** the response indicates `Figure: 4` as the final counter

#### Scenario: Isolation flag resets counters per container family

- **GIVEN** the same document as above (3 body Figures + 1 header Figure)
- **WHEN** `update_all_fields(doc_id, isolate_per_container: true)` is called
- **THEN** the body's three `Figure` counters become `1`, `2`, `3` and the header's `Figure` counter becomes `1` (isolated per container family)
- **AND** the response indicates `Figure: 3` for body and `Figure: 1` for the header in a per-container counter breakdown

#### Scenario: Header with SEQ and VML watermark round-trips byte-equal

- **GIVEN** a `.docx` whose `word/header1.xml` contains a paragraph with a `<w:pict>` watermark AND a separate paragraph with a `SEQ Chapter` field
- **WHEN** `update_all_fields(doc_id)` is called
- **AND** the document is saved
- **THEN** the saved `word/header1.xml` byte content for the `<w:pict>` block equals the source byte content (per `ooxml-header-footer-raw-element-preservation` capability)
- **AND** the `SEQ Chapter` cached value reflects the recomputed counter

