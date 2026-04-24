## Context

**Current state**: `Header.toXML()` / `Footer.toXML()` re-emit only typed `paragraphs[]`. When DocxWriter overlay-mode marks a header/footer dirty (e.g., #42 `update_all_fields` flow on a doc with header SEQ field, or any `update_header(text:)` call on a watermarked template), `Header.toXML()` regenerates from typed model alone — silently dropping VML watermarks, OLE objects, ruby annotations, and any unknown OOXML construct.

Source audit traced the actual silent-drop site to `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift::parseRun` (lines 850-878). `parseRun` recognizes:
- `w:rPr` → `Run.properties`
- `w:t` → `Run.text`
- `w:drawing` → `Run.drawing` (modern DrawingML)
- `oMath` / `oMathPara` → `Run.rawXML` (OMML formula, generic stash)

Every other element is dropped on the floor. NTPU thesis VML watermark structure is `w:hdr` → `w:p` → `w:r` → `w:pict` → `v:shape` — `w:pict` falls into the unrecognized bucket.

**Constraints**:

- `Run` is a value type (`public struct Run: Equatable`) — adding a stored property is additive but requires tests for `Equatable` conformance to verify the new field participates in equality
- `Run.toXML()` (in `Models/Run+XML.swift` or similar) emits XML in a fixed order: `rPr`, then `text`/`drawing`/`rawXML`. Need to interleave `rawElements` by their original sibling-position to preserve byte-equality for the unknown portion
- `WordDocument.updateAllFields` (v0.13.4) currently uses a single `[String: Int] counters` dict scoped globally. Adding `isolatePerContainer` requires per-container counter maps without breaking the existing global-mode default
- `che-word-mcp-field-equation-crud` spec (live at `openspec/specs/che-word-mcp-field-equation-crud/spec.md`) currently documents `update_all_fields(doc_id:)` signature. Adding `isolatePerContainer` parameter is a MODIFIED requirement
- v3.7.1 CHANGELOG paragraph "Known limitation: header that legitimately contains a SEQ field (rare — chapter caption in running header) still re-emits via Header.toXML() and strips co-located VML" must be removed once this ships

**Stakeholders**:
- Academic users running NTPU/台大/政大 thesis workflows with watermarks + chapter-caption running headers
- `che-word-mcp` MCP tool callers using `update_all_fields` on watermarked templates
- `macdoc` CLI users — same DocxReader/DocxWriter path
- Downstream `ooxml-swift` consumers who programmatically construct headers (the `rawElements` field is additive; default `nil` preserves their behavior)

## Goals / Non-Goals

**Goals**:

- After this change, `update_all_fields` on a doc with VML watermark in any header/footer round-trips byte-equal for the watermark VML
- After this change, `update_header(text:)` on a watermarked header preserves the watermark VML (same root-cause path as above — Run.toXML now interleaves rawElements)
- After this change, `update_all_fields(isolatePerContainer: true)` resets SEQ counters per container family (body/header/footer/footnote/endnote independent)
- After this change, the `che-word-mcp-field-equation-crud` spec no longer carves out the "header WITH SEQ + VML still strips" exception
- All ooxml-swift tests pass + 3 new test files cover the regression surface (Run-layer carrier, header/footer byte-equality with VML fixture, counter-isolation behavior)

**Non-Goals**: see proposal.md Non-Goals section (container-layer / paragraph-layer raw-element preservation deferred; typed VML model deferred; OLE object lifecycle out of scope; section-aware counter isolation deferred).

## Decisions

### Decision: Run-layer-only fix for #52; defer Container/Paragraph layers

**What**: Fix the silent drop only at `parseRun` (Run layer). Do NOT add raw-element preservation to `parseContainerChildParagraphs:765` (Container layer) or `parseParagraph:630` default branch (Paragraph layer) in this SDD.

**Why**: NTPU watermark drops at Run layer (`w:r` → `w:pict`). Container-layer drops (`w:hdr` containing direct `<w:tbl>` / `<w:sdt>` siblings of `<w:p>`) are theoretical — Word doesn't generate this for normal templates. Paragraph-layer default branch ALREADY logs to stderr when debug logging is enabled (added v0.13.x), so we have telemetry to detect real-world Paragraph-layer impact before paying for the fix. YAGNI: build only the layer where the bug fires.

**Alternatives considered**:
- Fix all 3 layers in one SDD (~3× the model changes + 3× tests): rejected — nothing in production drops at the other layers per current evidence
- Fix only Container layer (assumed VML lived as `<w:hdr>` direct child): rejected after source audit confirmed VML lives nested inside `w:r`
- Add a generic `WordDocument.preservedArchive` write hook that surgically patches archive bytes before re-emit: rejected — violates the `modifiedParts ⇒ that part's bytes get re-emitted` contract

### Decision: Generic `[(name: String, xml: String)]` carrier over typed `pict: VMLPicture?` model

**What**: `Run.rawElements: [(name: String, xml: String)]?` stores the local element name + serialized XML for any unknown child of `<w:r>`. Future MCP tools that need to query VML watermarks can grep `rawElements` for `name == "w:pict"`; future tools that need to manipulate (e.g., remove watermark) can edit the rawElements array.

**Why**: Generic carrier handles all current AND future unknown elements (`w:pict`, `w:object`, `w:ruby`, `w:sym`, `w:fldSimple` if not yet typed) with one surface. Typed VML/OLE models double the public API surface for use cases that may never arrive. If/when a typed model is needed, it can be added later as a layer over `rawElements` (the typed model parses from the raw XML on demand).

**Alternatives considered**:
- Typed `Run.pict: VMLPicture?` + `Run.object: EmbeddedObject?`: rejected per above
- Single `Run.rawElements: [String]?` (just XML, no name tag): rejected — name tag enables filtering without re-parsing the XML
- Position-aware tuple `(insertionIndex: Int, name: String, xml: String)` for full sibling-position preservation: deferred — for round-trip preservation we just need to emit the rawElements AFTER the typed children (matches the pattern that NTPU watermarks use: drawing-bearing run carries no `w:t`, so position is unambiguous)

### Decision: `update_all_fields(isolatePerContainer:)` opt-in flag, default `false`

**What**: New optional parameter on `WordDocument.updateAllFields` and on the `update_all_fields` MCP tool. When `false` (default), preserves current global-counter-sharing behavior across all container families. When `true`, each container family (body / each header / each footer / footnotes / endnotes) maintains independent counter dictionaries — body's `Figure 3` doesn't increment header's `Figure` counter.

**Why**: The header-with-SEQ use case (chapter-caption running header) is the primary place where global counter sharing is user-visible and confusing. Now that #52 enables that use case to work at all (VML preservation), we need the counter semantics flag too. Default `false` preserves backward compat; explicit opt-in for users who need Word F9 semantics.

**Alternatives considered**:
- Make `isolatePerContainer: true` the default (matches Word F9 behavior): rejected — breaking change for existing callers; defer to a future major version
- Per-section isolation (Word's actual semantic, isolating by `<w:sectPr>` boundaries): deferred — adds significant complexity; per-container-family covers the common case
- Skip this entirely; ship #52 alone: rejected — bundling the two is cheaper than two separate releases, and the use case is coupled

### Decision: New capability `ooxml-header-footer-raw-element-preservation`; MODIFY existing `che-word-mcp-field-equation-crud`

**What**: Spec impact split across two capabilities:
- NEW spec at `openspec/specs/ooxml-header-footer-raw-element-preservation/spec.md` — describes the Run-layer raw-element preservation contract (capability is a behavior contract: "headers and footers preserve VML/object/etc.", implemented at Run layer)
- MODIFIED `openspec/specs/che-word-mcp-field-equation-crud/spec.md` — remove v3.7.1 known-limitation paragraph; add `update_all_fields` `isolatePerContainer` scenarios; add header-with-SEQ-and-VML preservation scenario referencing the new capability

**Why**: The user-facing contract ("header round-trip preserves bytes") describes a behavior that's distinct from existing capabilities. The implementation locus (Run layer) is incidental — if Container/Paragraph follow-ups ship later, they live under the same capability. Modifying `che-word-mcp-field-equation-crud` is necessary because the v3.7.1 spec carves out the limitation we're now removing.

**Alternatives considered**:
- Fold raw-element preservation into existing `ooxml-content-insertion-primitives` spec (which contains some `Header`/`Footer`-adjacent contracts already): rejected — that capability is about insertion APIs, not container-model integrity. Mixing the mental model is worse than a small new capability
- Single big MODIFIED to `che-word-mcp-field-equation-crud` capturing both the behavior AND the implementation: rejected — capability boundaries should describe behavior, not implementation locus

### Decision: Ship as `ooxml-swift v0.14.0` MINOR + `che-word-mcp v3.8.0` MINOR

**What**: ooxml-swift bumps MINOR because `Run.rawElements` is a net-new public field (additive; default nil; backward-compat for callers who construct Run programmatically without the field). che-word-mcp bumps MINOR because `update_all_fields` MCP tool gains a new parameter `isolate_per_container: Bool = false` (additive; default preserves behavior).

**Why**: Both changes are additive in API but observable in behavior (header round-trip changes byte content). MINOR honestly signals the behavior shift per semver. PATCH would be misleading.

**Alternatives considered**:
- ooxml-swift PATCH (0.13.6) since field is additive + default nil: rejected — `Run` Equatable conformance changes (rawElements participates in equality), which is a subtle observable change
- che-word-mcp MAJOR (4.0.0): rejected — no removed APIs, no signature changes, just additive parameter

## Risks / Trade-offs

- [**Position interleaving correctness**] `Run.toXML()` order matters: typed children (`rPr`, `text`, `drawing`) currently emit in fixed positions. Real Word docs with VML watermarks have empty-text Runs (`w:r` → `w:rPr` + `w:pict` only, no `w:t`), so emitting rawElements AFTER typed children is unambiguous for the common case. → Mitigation: spec scenario covers the empty-text watermark Run + tests assert byte-equality

- [**`Run.equatable` conformance change**] Adding `rawElements` to `Run` means existing Equatable comparisons that previously matched (`Run("foo", props)` vs `Run("foo", props)`) now require both sides have `rawElements == nil`. → Mitigation: default nil + nil-equals-nil makes the change invisible to programmatic construction. Reader-loaded docs always have explicit nil unless `parseRun` collected something

- [**`isolatePerContainer` counter semantic edge cases**] When `true`, Header A's `Figure` counter is independent of Body's. But if Header A appears on multiple pages (`.default` type used across all sections), should each page reset, or share within Header A? → Mitigation: spec defines "container family = the typed-model `Header` instance"; multi-page reuse of the same Header instance shares the counter. Cross-section `.default` headers (one per section) get independent counters. Document this explicitly in the spec scenario

- [**Bundled scope risk**] Two distinct features (raw-element preservation + counter isolation) in one SDD. If raw-element work hits unexpected complexity, counter-isolation gets blocked. → Mitigation: two are loosely coupled at code level (different files); could split mid-implementation if needed. Counter-isolation is bounded scope; risk concentrated in raw-element

- [**Test fixture sourcing for VML watermark**] Need a real `.docx` fixture with header containing VML watermark to verify byte-equality round-trip. NTPU thesis fixture is gitignored. → Mitigation: hand-craft a minimal synthetic fixture using `DocxWriter` test helpers + raw rawElements injection. If insufficient, fall back to `XCTSkip` pattern per `.note` smoke test precedent. Real-fixture verification can be a manual gate before release

## Migration Plan

Single coordinated release. Phase ordering within the SDD:

1. **Phase A** (ooxml-swift): `Run.rawElements` field + `parseRun` collection + `Run.toXML` interleave + 1 unit test file (`RunRawElementPreservationTests`)
2. **Phase B** (ooxml-swift): byte-equality round-trip integration test (`HeaderFooterByteEqualityWithVMLTests`) — exercises Phase A through DocxReader → updateAllFields → DocxWriter
3. **Phase C** (ooxml-swift): `updateAllFields(isolatePerContainer:)` parameter + per-container counter maps + `UpdateAllFieldsCounterIsolationTests`
4. **Phase D** (release): ooxml-swift CHANGELOG v0.14.0 + tag + GitHub release. che-word-mcp dep bump + Server.swift `isolate_per_container` MCP parameter + CHANGELOG v3.8.0 + universal binary + mcpb repackage + GitHub release with curl-uploaded assets + marketplace bump
5. **Phase E**: `/idd-close #52` with comprehensive closing summary; spec sync removes v3.7.1 known-limitation paragraph from `che-word-mcp-field-equation-crud`

**Rollback**: each phase reverts independently by reverting commits + retagging. Full rollback = pin che-word-mcp to v3.7.2 + revert Server.swift parameter + restore v3.7.1 known-limitation paragraph in `che-word-mcp-field-equation-crud` spec. Effort: ~30 min if needed.

## Open Questions

- Should `Run.rawElements` preserve insertion order across multiple unknown elements? (E.g., a hypothetical Run with both `w:pict` AND `w:object` in source order.) Tentative: yes, `[(name, xml)]` array preserves order; emit in array order after typed children
- Should `che-word-mcp` MCP server expose a tool to query the rawElements (e.g., `list_watermarks_in_header(doc_id:)`)? Tentative: no for this SDD; could be a follow-up if user demand surfaces. Adding it here doubles the MCP surface
- Should `update_all_fields` MCP tool tool-description signal the behavior change for `isolatePerContainer` default? Tentative: yes, document explicitly — both in tool description AND in the v3.8.0 CHANGELOG migration section
