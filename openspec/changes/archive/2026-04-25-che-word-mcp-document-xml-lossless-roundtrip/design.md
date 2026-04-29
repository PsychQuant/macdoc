## Context

`save_document` re-serializes `word/document.xml` losing data, even with zero user mutations. Three orthogonal causes co-fire on every body-mutating MCP call ([che-word-mcp#56](https://github.com/PsychQuant/che-word-mcp/issues/56)):

1. **Hardcoded namespace decls** — `DocxWriter.writeDocument` emits only `xmlns:w` + `xmlns:r` regardless of source document. Body still references `mc:`, `a:`, `wp:`, `v:`, `o:`, `w14:`, `w16cex:`, etc. — libxml2 fails with "Namespace prefix mc on AlternateContent is not defined". Reader never captures the original 34 namespaces.
2. **Reader doesn't parse bookmarks** — `Paragraph.bookmarks: [Bookmark]` model exists but is populated only by `WordDocument.insertBookmark()`. `DocxReader` has zero hits for `bookmarkStart` / `bookmarkEnd`. Round-trip wipes 100% of source bookmarks.
3. **Reader doesn't parse structural wrappers** — `<w:hyperlink>`, `<w:fldSimple>`, `<mc:AlternateContent>` blocks (TOC entries, cross-references, table caption SEQ fields, embedded math) are unread. Their inner `<w:r>` children are silently dropped along with the wrapper. NTPU thesis loses 354 `<w:t>` nodes / 191 unique strings (`[tab:gjr_garch_subperiod]` cross-refs, `Pearson (Spearman)` math, Chinese chapter markers).

Reporter (#56) proposed the obvious fix template: v3.8.0 (#52) Header/Footer raw-element preservation pattern, applied to `document.xml`. Discussion (`/spectra-discuss`) refined this to a **lossless-first hybrid model** after recognizing raw-only carriers fail tool-mediated edits silently.

## Goals / Non-Goals

### Goals

- After `open → no-op save`, `word/document.xml` SHALL be byte-equivalent to source for: namespace declarations, bookmark count + ids + names, hyperlink count + anchors + URLs + text, `<w:fldSimple>` count + instr + result text, `<mc:AlternateContent>` blocks, all 14 ECMA-376 `<w:p>` child element types in original order.
- After `open → tool-mediated edit (replace_text / format_text / update_paragraph) → save`, edits inside hyperlinks, `<w:fldSimple>`, and `<mc:Fallback>` SHALL be applied (no silent failure).
- libxml2 `xmllint --noout` SHALL parse the output without unbound prefix errors.
- 218 existing MCP tools that read `paragraph.runs[i]` SHALL continue working unchanged (zero breaking changes).
- NTPU master's thesis (169 KB, 42 parts, 45 bookmarks, 13 fonts including DFKai-SB) SHALL survive `open → insert_paragraph → save` with all 45 bookmarks preserved, all `<w:t>` text strings present, and `xmllint --noout` clean.

### Non-Goals

- **Word's `mc:Choice` reconciliation**: when an edit applied to `fallbackRuns` (extracted from `<mc:Fallback>`) modifies text that also exists in `<mc:Choice>`, the Choice content goes stale. Word handles reconciliation per its own rules; this design accepts the divergence as documented behavior.
- **Performance microbenchmarks**: capturing rawElements verbatim adds memory overhead. Out of scope unless NTPU thesis round-trip exceeds 5 seconds (it currently completes in <1s).
- **Migrating existing 218 MCP tool callers to use new `Hyperlink.runs`**: keeping `Hyperlink.text` as a computed property is sufficient; tools may opt in to the typed surface incrementally in future SDDs.
- **Hotfixing Phase 1 separately as v3.12.1**: rejected — Phase 1 alone changes the failure mode (XML parses but bookmarks/text still missing) and creates user confusion ("you said it was fixed"). Bundle into v3.13.0.
- **CustomXml part round-trip**: `<w:customXml>` block-level model preservation is in scope; full `customXml/` part round-trip already covered by `ooxml-roundtrip-fidelity`.
- **`update_caption` / `update_all_fields` (#54) typing migration**: keep their current SEQ-special-case path; the new `FieldSimple` model is additive and does not replace the field-code-tools layer.

## Decisions

### 1. Position-index ordering, not enum refactor

Every `<w:p>` child type (Run, Bookmark, Hyperlink, FieldSimple, AlternateContent, range markers) gains a `position: Int` field. Reader assigns positions 0, 1, 2, ... in source-document order while walking children. Writer collects all child instances from all parallel arrays, sorts by `position`, and emits in order.

**Why not** `enum ParagraphChild { case run(Run); case hyperlink(Hyperlink); ... }`: an enum would force migration of 218 MCP tool call sites from `paragraph.runs[i]` to switch-statement traversal. Position-index is additive — existing code that doesn't read `position` continues working. Tools that need order-aware operations (Reader, Writer, plus future order-sensitive tools) read `position`.

**Alternatives considered**:
- **Enum with computed `runs: [Run]` accessor**: still requires touching every tool that mutates runs, since insertion order matters. Rejected.
- **Single `children: [ParagraphChild]` array with type discriminator**: same problem as enum. Rejected.
- **Position-index pattern**: chosen. Mirrors how v3.12.0 (#45) `Run.revisionId` pairs typed link by id without restructuring the run array.

### 2. Hybrid model (typed surface + raw passthrough), not raw-only carriers

Each unmodeled wrapper gets BOTH a typed editable surface (so MCP tools can find/modify content inside) AND raw passthrough fields (so unrecognized attributes/children survive byte-identical):

- `Hyperlink`: `runs: [Run]` (typed editable) + `rawAttributes: [String: String]` + `rawChildren: [String]` (passthrough escape hatch)
- `FieldSimple`: `instr: String` + `runs: [Run]` (typed editable) + `rawAttributes: [String: String]`
- `AlternateContent`: `rawXML: String` (preserve verbatim) + `fallbackRuns: [Run]` (typed editable mirror of `<mc:Fallback>` content)

**Why not** raw-only (`{ rawXML: String }` carrier for everything): satisfies byte-level no-op round-trip but breaks tool-mediated edits silently. `replace_text("[tab:foo]", ...)` walks `Paragraph.runs` — if `[tab:foo]` text lives in `Hyperlink.rawXML`, it's invisible to the tool. User sees success, file unchanged. **This is a worse failure mode than the current bug** (which at least gives a visible XML error). Rejected.

**Why not** fully typed (model every possible OOXML element): `<mc:AlternateContent>` has 50+ schema variants (charts, drawings, math, OLE, ink, custom shapes). Designing exhaustive typed models is infeasible scope. Hybrid pragma: type what we can edit, raw-carry what we just need to preserve.

**Pattern source**: v3.8.0 (#52) `Run.rawElements` carrier for unknown `<w:r>` children. This decision applies the same pattern at the wrapper level (`<w:p>` children, not `<w:r>` children).

### 3. `Hyperlink.text` becomes computed property (option a from discuss)

Existing `Hyperlink.text: String` is the single source of hyperlink display text. New design adds `Hyperlink.runs: [Run]`. To avoid breaking 218 MCP tools that read `hyperlink.text`, convert `text` to a computed property:

```swift
public var text: String { runs.map { $0.text }.joined() }
```

Setter: assigning `text = "foo"` collapses to `runs = [Run(text: "foo")]` (loses prior multi-run formatting — acceptable since the old `text: String` field already had this property).

**Alternatives considered**:
- **Deprecate `text`, add `runs` in parallel**: requires migration window + deprecation warnings. More work for no benefit since computed property is observationally equivalent.
- **Direct breaking change**: would require updating 218 tool call sites in che-word-mcp Server.swift. Net-negative.

### 4. ECMA-376 `<w:p>` schema as the completeness checklist

The proposal lists 14 child element types. To verify completeness, design specifies enumerating ECMA-376 Part 1 §17.3.1 (`<w:p>` complex type) and §EG_PContent / §EG_RunLevelElts content groups. Each child element name SHALL be matched against:

- Already typed (7): `<w:r>`, `<w:pPr>`, `<w:ins>`, `<w:del>`, `<w:moveFrom>`, `<w:moveTo>`, `<w:sdt>`
- New typed (3): `<w:hyperlink>`, `<w:fldSimple>`, `<mc:AlternateContent>`
- New raw-carrier with position (7+): `<w:bookmarkStart>`, `<w:bookmarkEnd>`, `<w:commentRangeStart>`, `<w:commentRangeEnd>`, `<w:permStart>`, `<w:permEnd>`, `<w:proofErr>`, `<w:smartTag>`, `<w:customXml>`, `<w:dir>`, `<w:bdo>`, plus any unlisted-in-ECMA-376-but-found-in-NTPU-thesis elements (verified by sampling).

The NTPU thesis sampling step in Phase 4 (run xmllint output through a sort-uniq filter for child element names) catches spec gaps. Any unrecognized child element triggers an XCTFail in the round-trip test with the element name in the failure message.

### 5. Test fixture dual-track (synthesize + real-world smoke)

CI regression test uses `LosslessRoundTripFixtureBuilder` (extends existing `SDTFixtureBuilder` pattern in `Tests/OOXMLSwiftTests/Fixtures/`). Synthesizes a 50–100 KB docx with the minimum elements needed to exercise every code path: 5+ bookmarks, 3+ hyperlinks (one URL, one anchor, one email), 2+ `<w:fldSimple>` (one SEQ Table, one REF), 1+ `<mc:AlternateContent>` math block, 10+ namespace declarations on `<w:document>` root, mixed runs/wrappers across 3+ paragraphs to exercise position-index ordering.

Real-world smoke test fires from `mcp/che-word-mcp/Tests/CheWordMCPTests/RealWorldDocxRoundTripSmokeTests.swift`. Reads `mcp/che-word-mcp/test-files/*.docx` (gitignored, mirrors existing `.note` smoke pattern from #81). For each file: opens, no-op saves, reopens, asserts `xmllint --noout` clean, asserts bookmark count match, asserts hyperlink count match, asserts `<w:fldSimple>` count match, asserts sum-of-`<w:t>`-content SHA256 match. `XCTSkip` when no fixture present.

**Why dual-track**: builder fixture catches "we didn't regress this case"; real-world smoke catches "we didn't think of this case". NTPU thesis cannot be committed (IP risk + 169 KB binary). User-supplied real-world docs cover what the builder cannot anticipate.

## Risks / Trade-offs

- **Position-index drift on insert/delete**: when MCP tools insert or delete a child, neighboring positions become stale. → Mitigation: define `position` as ordering-only, not contiguous; Writer sorts before emit so gaps are harmless. Insert tools assign `position = max(neighbors) + 1` or `(prev + next) / 2` (use `Double` if precision needed). Define a renumber sweep for extreme drift cases.
- **`Hyperlink.runs` computed-property setter loses formatting**: assigning `hyperlink.text = "foo"` to a multi-run hyperlink collapses to single Run, losing intra-link bold/italic. → Mitigation: documented as expected behavior (matches pre-fix). New typed mutators (e.g., `appendRun(to:)`) are out of scope; future SDD if needed.
- **`mc:Choice` / `mc:Fallback` divergence after fallback edit**: editing `fallbackRuns` then saving leaves `<mc:Choice>` (which is preserved as raw) with stale text. → Mitigation: documented in Non-Goals. Word reconciles per its own rules; users editing math in che-word-mcp are an edge case (math editing is its own SDD).
- **NTPU thesis fixture availability**: smoke test silently skips when fixture absent → CI on fresh clones never validates against real-world docs. → Mitigation: README documents how to add a thesis-class fixture locally; follow-up SDD considers committing a small synthetic-but-realistic doc.
- **ECMA-376 spec table interpretation drift**: the spec is dense; a reviewer might miss a child element type. → Mitigation: NTPU thesis sampling step catches gaps; XCTFail with element name surfaces unknown elements at test time.
- **`<w:hyperlink>` with `r:id` rels reference**: external hyperlinks reference a relationship in `document.xml.rels`. Reader-populated `Hyperlink.relationshipId` must round-trip the rels reference. → Mitigation: existing `RelationshipsOverlay` (v3.5.2 / #35) handles rels round-trip; just ensure hyperlink Reader populates `relationshipId` from the source `r:id` attribute.
- **`update_all_fields` (#54) interaction**: existing F9-equivalent SEQ recount walks current `Paragraph` model. New `FieldSimple` typed model adds a parallel data source. → Mitigation: `update_all_fields` continues using its current code path; `FieldSimple` is read-only-from-reader for v3.13.0. Future SDD migrates the field-code tools.

## Migration Plan

1. Land `ooxml-swift v0.19.0` first (additive — existing tests must all pass with new fields). Tag and release.
2. Bump `che-word-mcp/Package.swift` to `ooxml-swift from: "0.19.0"`. Run full `che-word-mcp` test suite — should pass with zero source changes (all additions are read-side).
3. Add `RealWorldDocxRoundTripSmokeTests` to `che-word-mcp` test suite. Verify XCTSkip behavior on CI (no fixture present).
4. Local validation: drop NTPU thesis into `mcp/che-word-mcp/test-files/`, run smoke test locally, verify all assertions pass.
5. Tag `che-word-mcp v3.13.0`. Release with binary.
6. Plugin shell update: `che-word-mcp` plugin v3.14.0 (skill + CLAUDE.md mention of new lossless guarantees).

Rollback: revert `che-word-mcp/Package.swift` to `ooxml-swift from: "0.18.0"`. v3.13.0 binary remains in GitHub Releases for users who want to opt out. ooxml-swift v0.19.0 is additive so consumers other than che-word-mcp see no breaking change either way.

## Open Questions

None — all 4 questions raised in `/spectra-discuss` are locked:
- **Order preservation strategy**: parallel arrays + position index (Decision 1).
- **typed vs raw for wrappers**: hybrid — typed editable surface + raw passthrough (Decision 2).
- **Fixture strategy**: builder + NTPU smoke dual-track (Decision 5).
- **Release split vs bundled**: bundled v3.13.0 (Non-Goals — split rejected).
