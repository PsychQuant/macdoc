## Why

che-word-mcp v3.9.0 reaches the **Office.js OOXML Roadmap** ([che-word-mcp#43](https://github.com/PsychQuant/che-word-mcp/issues/43)) Phase 1 boundary: the parser/IO infrastructure (preserve-by-default, raw-element carriers, SDT first-class model) is solid, but three foundational document-XML capabilities remain partial:

- **Styles** ([#48](https://github.com/PsychQuant/che-word-mcp/issues/48)) — current 5 tools (`list_styles` / `create_style` / `update_style` / `delete_style` / `apply_style`) cannot express `basedOn` inheritance chains, linked paragraph↔character styles, `nextStyleId`, `qFormat` (Quick Style Gallery), `latentStyles`, or localized `<w:name>` aliases. Real Word templates use these — corporate themes inherit, language packs alias, Heading 1 chains to Heading 2 via `nextStyleId`.
- **Sections** ([#47](https://github.com/PsychQuant/che-word-mcp/issues/47)) — current 5 tools (`set_page_size` / `set_page_orientation` / `set_page_margins` / `insert_section_break` / `set_columns` / `get_section_properties`) cover page geometry but omit `<w:lnNumType>` (line numbers — required for legal documents), `<w:vAlign>` (vertical alignment — required for cover pages), `<w:pgNumType w:fmt>` (Roman numerals — required for academic prefaces), section-break-type switching (`nextPage` / `evenPage` / `oddPage`), and `<w:titlePg/>` per-section.
- **Numbering** ([#46](https://github.com/PsychQuant/che-word-mcp/issues/46)) — current 3 tools (`insert_bullet_list` / `insert_numbered_list` / `set_list_level`) only insert new lists. Cannot enumerate existing `<w:abstractNum>` / `<w:num>` definitions, override level start values via `<w:lvlOverride>`, assign existing numId to a paragraph, restart vs continue lists, or garbage-collect orphan `<w:num>` entries that no paragraph references (a known leak source in many .docx libraries).

These three gaps share an architectural pattern: each capability mutates a top-level XML part (`styles.xml`, `numbering.xml`, sectPr inside `document.xml`) and must mark the part dirty so the writer's overlay-mode round-trip emits the change. Bundling them lets us extend the existing dirty-tracking discipline consistently and ship one cohesive minor release rather than three back-to-back patches.

## What Changes

### Phase 1 — ooxml-swift v0.16.0 (model + WordDocument extensions)

- Extend `Style` model with `basedOn`, `linkedStyleId`, `nextStyleId`, `qFormat`, `hidden`, `semiHidden` fields. Reader populates from `<w:basedOn>` / `<w:link>` / `<w:next>` / `<w:qFormat/>` / `<w:hidden/>` / `<w:semiHidden/>`. Writer emits all when present.
- New `LatentStyle` struct + `Document.latentStyles: [LatentStyle]` collection + reader/writer for `<w:latentStyles>` block in `styles.xml`.
- New `StyleAlias` struct (lang + name) + `Style.aliases: [StyleAlias]` for localized names.
- Extend `Numbering` reading: `Numbering.numbering` already reads on parse — extend writer + add `Numbering.gcOrphans(referencedNumIds: Set<Int>) -> Int` helper.
- Extend `SectionProperties` model with `lineNumbers: LineNumbers?`, `verticalAlignment: VerticalAlignment?`, `pageNumberFormat: PageNumberFormat?`, `titlePageDistinct: Bool`, `sectionBreakType: SectionBreakType`. Reader/writer covers all.
- New `WordDocument` mutation methods: `getStyleInheritanceChain(styleId:)`, `linkStyles(paragraphStyleId:characterStyleId:)`, `setLatentStyles(_:)`, `addStyleNameAlias(styleId:lang:name:)`, `createNumberingDefinition(levels:)`, `overrideNumberingLevel(numId:ilvl:startValue:)`, `assignNumberingToParagraph(paragraphIndex:numId:level:)`, `continueList(paragraphIndex:previousListId:)`, `gcOrphanNumbering()`, `setSectionLineNumbers(sectionIndex:)`, `setSectionVerticalAlignment(sectionIndex:)`, `setSectionPageNumberFormat(sectionIndex:start:format:)`, `setSectionBreakType(sectionIndex:type:)`, `setTitlePageDistinct(sectionIndex:enabled:)`, `getAllSections()`. Each mutation explicitly marks the relevant XML part dirty.

### Phase 2 — che-word-mcp v3.10.0 (~25 new MCP tools)

**Styles tools (6 modified + 4 new):**

- `create_style` — extended args: `based_on`, `linked_style_id`, `next_style_id`, `q_format`, `hidden`, `semi_hidden`
- `update_style` — same extended args
- `get_style_inheritance_chain` (NEW)
- `link_styles` (NEW)
- `set_latent_styles` (NEW)
- `add_style_name_alias` (NEW)

**Numbering tools (8 NEW):**

- `list_numbering_definitions`, `get_numbering_definition`, `create_numbering_definition`, `override_numbering_level`, `assign_numbering_to_paragraph`, `continue_list`, `start_new_list`, `gc_orphan_numbering`

**Sections tools (7 NEW):**

- `set_line_numbers_for_section`, `set_section_vertical_alignment`, `set_page_number_format`, `set_section_break_type`, `set_title_page_distinct`, `set_section_header_footer_references`, `get_all_sections`

### Phase 3 — Release ceremony

- ooxml-swift v0.16.0 push + tag + GitHub release
- che-word-mcp v3.10.0 build, install, mcpb package, GitHub release
- psychquant-claude-plugins marketplace.json sync
- Close #46 #47 #48 via `/idd-close`

## Non-Goals

- **#43 §15 Theme deeper integration** — Style references to theme symbols are already partially supported; reworking them is its own SDD.
- **#43 §17 Bookmarks 進階 + cross-references** — distinct capability, separate SDD.
- **Style import / export between documents** — useful but out of scope; the 4 capabilities here are about in-document operations.
- **Numbering override of `<w:lvlText>` format string at runtime** — supported only at creation; mid-list reformat is rare and adds parser complexity.
- **Section-level page background colors / images** — `<w:background>` lives at body root not sectPr; separate concern.
- **`<w:numberingChange>` revision tracking on numbering modifications** — Track Changes for numbering is part of [#45](https://github.com/PsychQuant/che-word-mcp/issues/45) (separate SDD).
- **Auto-GC on save** — `gc_orphan_numbering` is an explicit user tool call. Auto-GC risks deleting numIds the user transiently detached during multi-step edits.

## Capabilities

### New Capabilities

- `che-word-mcp-numbering-tools`: 8 new MCP tools for full numbering.xml lifecycle (list / get / create / override / assign / continue / start_new / GC)
- `che-word-mcp-sections-tools`: 7 new MCP tools for sectPr completeness (line numbers / vertical alignment / page number format / break type / title page / header refs / list all)
- `ooxml-document-part-mutations`: WordDocument-level Swift API for styles / numbering / sections mutations with consistent dirty-tracking discipline

### Modified Capabilities

- `che-word-mcp-insertion-tools`: existing `create_style` / `update_style` gain new extended args (`based_on`, `linked_style_id`, `next_style_id`, `q_format`, `hidden`, `semi_hidden`); 4 new style tools added (`get_style_inheritance_chain`, `link_styles`, `set_latent_styles`, `add_style_name_alias`)

## Impact

- Affected specs:
  - New: `openspec/specs/che-word-mcp-numbering-tools/spec.md`
  - New: `openspec/specs/che-word-mcp-sections-tools/spec.md`
  - New: `openspec/specs/ooxml-document-part-mutations/spec.md`
  - Modified: `openspec/specs/che-word-mcp-insertion-tools/spec.md`
- Affected code:
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Style.swift` (add basedOn / linked / next / qFormat / hidden / semiHidden / aliases)
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Numbering.swift` (add createCustomDefinition, overrideLevel, gcOrphans helpers)
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Section.swift` (add LineNumbers / VerticalAlignment / PageNumberFormat structs + fields on SectionProperties)
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift` (add 16 new mutation methods, all explicitly marking relevant XML parts dirty)
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift` (parse new style / section / numbering attributes)
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxWriter.swift` (emit new attributes; latentStyles block in styles.xml)
  - Modified: `mcp/che-word-mcp/Sources/CheWordMCP/Server.swift` (extend insert_content_control style args; register 19 new tools + dispatcher cases + helper functions)
  - Modified: `packages/ooxml-swift/Package.swift` (version bump to 0.16.0)
  - Modified: `mcp/che-word-mcp/Package.swift` (ooxml-swift dep bump to 0.16.0)
  - Modified: `mcp/che-word-mcp/mcpb/manifest.json` (version 3.10.0)
  - Modified: `mcp/che-word-mcp/CHANGELOG.md` (v3.10.0 entry)
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/StylesInheritanceTests.swift`
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/NumberingLifecycleTests.swift`
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/SectionPropertiesExtendedTests.swift`
  - New: `mcp/che-word-mcp/Tests/CheWordMCPTests/StylesNumberingSectionsToolsTests.swift`
  - New: `mcp/che-word-mcp/Tests/CheWordMCPTests/CorporateTemplateE2ETests.swift`
