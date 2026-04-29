## Context

The che-word-mcp Office.js Roadmap ([che-word-mcp#43](https://github.com/PsychQuant/che-word-mcp/issues/43)) decomposes Word's OOXML feature surface into ~20 sub-issues. After shipping #44 (Content Controls), 7 P0 sub-issues remain (#45-51). Three of them — #46 (Numbering), #47 (Sections), #48 (Styles) — share a common architectural pattern: they each mutate a top-level WordprocessingML XML part (`numbering.xml`, `document.xml` for sectPr, `styles.xml`) and require the writer's overlay-mode round-trip to detect dirty parts via the `WordDocument.modifiedParts: Set<String>` mechanism introduced in v0.13.0.

The remaining four P0s — #49 (Tables), #50 (Hyperlinks), #51 (Headers), #45 (Track Changes) — depend on this foundation: #49 and #50 reference style ids; #51 references sectPr's `<w:headerReference>`; #45 needs `nextStyleId` for revision-on-style-apply. Bundling the foundation triplet first unblocks the other four.

Stakeholders: che-word-mcp users authoring corporate templates (multi-section reports with Roman-numeral prefaces, multi-language style aliases, tiered numbering hierarchies). Also downstream: every future SDD that touches styles/numbering/sectPr inherits the dirty-tracking discipline established here.

## Goals / Non-Goals

**Goals:**

- 19 new MCP tools + 6 extended args on existing tools cover every checkbox in #46/#47/#48 acceptance criteria.
- ooxml-swift v0.16.0 delivers a coherent `WordDocument` mutation API for styles / numbering / sectPr with consistent dirty-tracking — every new method explicitly calls `modifiedParts.insert("word/<part>.xml")`.
- Round-trip fidelity verified by 3 new test fixtures: corporate template (Heading inheritance + qFormat + linked styles), academic preface (Roman numerals + line numbers + cover page vAlign), tiered list (9-level numbering with override).
- All 4 capability specs (`che-word-mcp-numbering-tools`, `che-word-mcp-sections-tools`, `ooxml-document-part-mutations`, modified `che-word-mcp-insertion-tools`) include scenarios mapping 1:1 to the tools.

**Non-Goals:**

- Theme integration deeper than current state (#43 §15 is its own SDD).
- Bookmark cross-references (#43 §17 is its own SDD).
- Cross-document style import/export.
- Mid-list `<w:lvlText>` reformat (creation-time only).
- Track Changes for numbering modifications (covered by #45 SDD).
- Auto-GC of orphan numIds on save (explicit tool only — see Decision 1).

## Decisions

### Numbering GC is an explicit user tool, not an auto-on-save sweep

**Decision:** `gc_orphan_numbering` is a separate MCP tool that scans every paragraph's `<w:pPr><w:numPr><w:numId>` to build a referenced-set, then deletes any `<w:num>` from `numbering.xml` whose `w:numId` is not referenced. The tool is invoked by user choice. Save operations do NOT auto-GC.

**Rationale:** Multi-step edit workflows transiently detach numIds — example: "delete a paragraph that owned numId=5, then immediately re-paste a copy" would temporarily orphan numId=5 between the two operations. An auto-GC on save during that window destroys the user's intended state. Explicit GC matches the discipline of `update_all_fields` (also user-invoked, never auto). The user always knows when they're cleaning up; the tool never surprises them.

**Alternatives considered:**

- *Auto-GC on every save:* Risk of mid-edit data loss. Rejected.
- *Auto-GC on `finalize_document` only:* Less risky but still surprising. Rejected — finalize is for "I'm done editing", not for cleanup. Cleanup deserves its own intent.
- *GC on document open:* Read-time mutation contradicts the "read is pure, write is intent" model. Rejected.

### Style inheritance chain is computed on demand, no cache

**Decision:** `get_style_inheritance_chain(styleId)` traverses the `basedOn` reference chain from the queried style upward to root each call. No caching across calls. Cycle detection: walk with a visited-set, stop on revisit (cycles in styles.xml are malformed but real Word files occasionally exhibit them; the tool returns the prefix-up-to-cycle plus a `cycle_detected: true` flag).

**Rationale:** Inheritance chains are typically 2-4 levels deep (`Normal` → `Heading 1` → `Heading 1 Bold`). Each traversal is O(depth) hash lookups against the in-memory `[Style]` array — under a microsecond. Caching introduces invalidation complexity (when does cache reset? every `update_style`? every `delete_style`?) that costs more than the traversal saves. Same reason WordDocument doesn't cache `getParagraphs()`.

**Alternatives considered:**

- *Lazy cache invalidated on style mutation:* requires every style mutation to clear the cache, adding coupling. Rejected — premature optimization for a rare query.
- *Eager cache built on document open:* wastes memory for documents the user never queries inheritance on. Rejected.

### Dirty-tracking discipline is per-mutation explicit insert, not AOP

**Decision:** Every new mutation method on `WordDocument` ends with an explicit `modifiedParts.insert("word/<part>.xml")` call. We do NOT introduce a property wrapper, decorator, or method-swizzling layer that auto-marks dirty.

**Rationale:** The existing v0.13.0+ codebase already uses this pattern at 50+ call sites (see `Document.swift:230, 254, 269, 364, 380, 393, 407, 420, 717, 754, 775, 796, 815`). Consistency with the existing pattern dominates over DRY. AOP would obscure where the dirty-mark happens, making bugs harder to trace (e.g., #36/#37/#38 root causes were dirty-tracking gaps — explicit calls would have made those bugs grep-discoverable). Explicit is auditable.

**Alternatives considered:**

- *Property wrapper `@MarksDirty(part: "word/styles.xml")`:* magic that hides the side effect. Rejected.
- *Centralized `WordDocument.markDirty(_ part: PartIdentifier)` enum-typed helper:* improves typo safety but adds an indirection layer. Rejected — string literals are reviewable, enum migration can happen later as a separate cleanup if needed.

### latentStyles is a single Document-level collection, not per-Style

**Decision:** `Document.latentStyles: [LatentStyle]` is a top-level model field separate from `Document.styles: [Style]`. LatentStyle struct: `name: String, uiPriority: Int?, semiHidden: Bool, unhideWhenUsed: Bool, qFormat: Bool`. Reader populates from `<w:latentStyles>` block. Writer emits the block in styles.xml when non-empty.

**Rationale:** `<w:latentStyles>` in styles.xml is a flat list parallel to `<w:style>` entries, not a nested structure. A latent style is the "would-be settings if this style ever materializes" — it has no `<w:rPr>` or `<w:pPr>`. Forcing it into the existing `Style` struct (via an `isLatent: Bool` flag) would mean every Style instance carries always-nil formatting properties. Cleaner to keep separate.

**Alternatives considered:**

- *Merge into `Style` with `isLatent: Bool`:* type pollution; latent styles have no formatting. Rejected.
- *Skip latentStyles entirely (they're optional):* templates ship with explicit latentStyles blocks to control Word's Quick Style Gallery; missing this loses round-trip fidelity. Rejected.

### Section model extensions live on existing `SectionProperties`, no new container

**Decision:** New fields `lineNumbers`, `verticalAlignment`, `pageNumberFormat`, `titlePageDistinct`, `sectionBreakType` (replaces existing usage of separate enum) attach directly to `SectionProperties`. `Document.body.children` already terminates with sectPr-bearing paragraphs — no new container introduced.

**Rationale:** Sections in OOXML are NOT a top-level container — they're sectPr fragments that live inside paragraph properties at the section boundary. Wrapping them in a Swift `Section` struct would force every body iteration to traverse a wrapper that has no semantic equivalent in the file format. Extending `SectionProperties` matches the file's structure.

**Alternatives considered:**

- *New `Section: BodyChild` enum case wrapping multiple paragraphs:* contradicts the OOXML model where sectPr is a property on a paragraph, not a container of paragraphs. Rejected — would force lossy translation on read.

## Risks / Trade-offs

[Risk] Style inheritance chain computation is O(depth) per call, but a deeply pathological document (depth=50+) traversed once per paragraph during hypothetical "render" tooling could become O(n*depth). Mitigation: tools that need bulk traversal call `getStyleInheritanceChain` once per unique styleId and cache locally — document this in the tool description.

[Risk] `gc_orphan_numbering` deletes data. If the user is mid-multi-step-edit and runs GC at the wrong time, in-progress numIds disappear. Mitigation: tool description explicitly warns "run only after all numbering edits complete"; tool returns the count + list of deleted numIds so caller can re-create if needed.

[Risk] `<w:latentStyles>` block has hundreds of entries in some Word templates (controlling visibility of every built-in style). Round-trip without modification must preserve ordering and all attributes — test fixture covers this.

[Trade-off] Bundling 3 issues into one SDD breaches the "1 issue 1 SDD" idiom. Defended by: (a) shared architectural pattern (XML part dirty-tracking), (b) shared release ceremony saves 2 deployment cycles, (c) issues are atomically closeable — if Phase 1 ships but Phase 2 stalls, only Phase 1's portion of each issue is unlocked. Trade-off accepted.

[Trade-off] 19 new tools is the largest tool addition since v3.4.0 (13 tools). Tool count grows ~155 → ~174. MCP clients with tool-list size limits may notice. Acceptable — these tools are independently useful and follow existing naming conventions.

## Migration Plan

- ooxml-swift v0.15.x → v0.16.0 — minor version (additive API, no removals; existing methods unchanged).
- che-word-mcp v3.9.x → v3.10.0 — minor version (additive tools + extended args on `create_style` / `update_style`; default args preserve v3.9.x behavior).
- word-to-md-swift unchanged (no BodyChild enum changes this round).
- Binary release triggers marketplace sync per common-release-flow rule.
- Rollback: revert che-word-mcp Package.swift's ooxml-swift dep to ^0.15.1. Re-build. No data migration concerns — new mutations only appear when the new tools are called.

## Open Questions

- Should `set_section_header_footer_references` bundle `default` / `first` / `even` types into one call (with a dictionary arg) or be 3 separate calls? Leaning toward 1 call with an enum-keyed dictionary — matches how Word stores them in sectPr.
- For `start_new_list` vs `continue_list`, does the spec require these to be two distinct tools or one tool with a `mode: 'continue' | 'restart'` arg? Issue body lists them separately; following issue verbatim unless reviewer pushes back.
