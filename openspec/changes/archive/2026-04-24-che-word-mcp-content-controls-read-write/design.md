## Context

che-word-mcp currently treats SDTs as write-only opaque XML. The existing path:

```
insert_content_control (tool)
  → StructuredDocumentTag + ContentControl (ooxml-swift model)
    → ContentControl.toXML() serializes full SDT
      → Document.swift:2259 writes XML into Run.rawXML
```

The round-trip works for write-read-write because `Run.rawXML` is preserved as-is by DocxReader — but DocxReader never parses `<w:sdt>` into structured values. Post-read, the SDT is visible as opaque XML inside a Run, not as a `ContentControl` object with tag/alias/currentText.

This blocks all read-dependent operations: `list_content_controls` cannot enumerate what exists, `update_content_control_text` cannot locate an SDT by tag, `delete_content_control` cannot surgically remove one without XML-string manipulation.

Stakeholders: che-word-mcp users doing template automation (contracts, invoices, reports) — the primary use case Content Controls exist for. Also downstream: §22 Bibliography (roadmap #43) reuses SDT infrastructure for `<b:Source>` binding.

## Goals / Non-Goals

**Goals:**

- DocxReader produces structured `ContentControl` values for every `<w:sdt>` element in a document, with parity to the write-path model (all 12 SDT types recognized).
- 8 new che-word-mcp tools enable complete SDT lifecycle: discover, read, modify, delete.
- Existing `insert_content_control` / `insert_repeating_section` remain backwards-compatible. All extensions are additive optional arguments.
- SDT ids become deterministic (max+1) to prevent collisions in documents with many content controls.
- Test fixtures verify round-trip fidelity: read docx → inspect via tools → modify → write → re-open in Word without errors.

**Non-Goals:**

- CustomXml part management and `<w:dataBinding>` (deferred to Change B).
- New specs / capabilities (three existing specs are modified).
- Bibliography-typed APIs (§22 future change).
- Regex-based SDT search over rawXML blobs (rejected — SDT parser is the foundation).
- Merging `insert_repeating_section` into `insert_content_control` (rejected — argument shapes differ).

## Decisions

### DocxReader SDT parser attaches SDTs as a first-class Paragraph child, not a Run.rawXML blob

**Decision:** `<w:sdt>` elements inside a paragraph become `Paragraph.contentControls: [ContentControl]` alongside existing `Paragraph.runs`. Block-level SDTs (wrapping entire paragraphs or tables) become a new `BodyElement.contentControl(ContentControl, children: [BodyElement])` case.

**Rationale:** Keeping SDTs as `Run.rawXML` means every downstream operation (list/get/update/delete) must re-parse the XML blob every time. First-class structured representation parses once at read time. The tradeoff — more code in DocxReader — is paid once; the blob approach pays parse cost on every tool invocation.

**Alternatives considered:**

- *rawXML blob preserved + regex helper:* Fast to ship but creates technical debt. Every new CRUD tool duplicates the XML parsing logic. Rejected.
- *Lazy parse on first access:* Adds state management to `Paragraph` and complicates serialization. Eager parse is simpler.

### SDT id allocation uses scan-max + 1

**Decision:** On `insert_content_control`, compute `nextId = maxExistingSdtId + 1` by walking all existing SDTs. Server.swift:8393's `Int.random(in: 100000...999999)` is removed.

**Rationale:** Random 6-digit ids have a birthday-problem collision probability that grows rapidly. A document with 200 SDTs has roughly 2% chance of collision per new insert. Max+1 is deterministic, debuggable, and matches Word's own allocator behavior for new SDTs in interactive use.

**Alternatives considered:**

- *UUID:* SDT id field is `w:val` as integer in OOXML spec. Converting UUIDs to ints loses information. Rejected.
- *Keep random but widen to 9 digits:* Reduces collision probability but still nondeterministic. Rejected — no upside over max+1.

### list_custom_xml_parts ships as an empty-list stub

**Decision:** Add `list_custom_xml_parts` in this change, implementation returns `[]` with a TODO comment pointing to Change B.

**Rationale:** Forward-compatible tool schema. Callers writing tooling against che-word-mcp v3.8.0 can start targeting the tool; when Change B lands in v3.9.0, the tool begins returning data without a schema change. Documents today rarely contain `/customXml/` parts; an empty list is semantically correct for most inputs.

**Alternatives considered:**

- *Wait until Change B to add the tool:* Forces callers to check che-word-mcp version before calling. Rejected — negligible cost to stub now.

### Repeating section stays separate from insert_content_control

**Decision:** `insert_repeating_section` remains its own tool. `list_repeating_section_items` and `update_repeating_section_item` are added alongside it for symmetry. The existing repeatingSection SDT type in `SDTType` enum remains available via `insert_content_control(type: "repeatingSection", ...)` but that path will throw with a "use insert_repeating_section for this type" message.

**Rationale:** Repeating sections wrap a list of `RepeatingSectionItem`s, not a single content. Their MCP args (`items: [String]`, `section_title`) differ from content control args (`content: String`, `alias`). Merging would require a tagged-union schema where `type: "repeatingSection"` forbids `content` and requires `items`. Two tools with cohesive args is more ergonomic than one tool with conditional args.

**Alternatives considered:**

- *Full merge with polymorphic args:* Rejected — schema complexity > tool-count convenience.
- *Deprecate insert_repeating_section in favor of merged tool:* Breaking change with no offsetting gain. Rejected.

### SDT parse in DocxReader handles nested SDTs by preserving tree structure

**Decision:** A SDT inside another SDT (e.g., a `Group` containing `PlainText` children) produces a `ContentControl` with nested `ContentControl` values in its `children` field. `list_content_controls` returns a flat list by default with `parentId` references; an optional `nested: true` arg returns a tree.

**Rationale:** Word allows arbitrary SDT nesting. The flat-list-with-parent-id format matches most downstream use cases (find by tag); the tree format serves introspection tools. Supporting both avoids guessing wrong.

**Alternatives considered:**

- *Flat only:* Loses structure info, harder to reason about grouped controls.
- *Tree only:* Harder for "find the SDT with tag X" queries.

## Risks / Trade-offs

[Risk] DocxReader SDT parse might miss edge cases in field-containing SDTs (TOC field is wrapped in an SDT per Field.swift:60-117).
Mitigation: Build fixture set from 5+ real-world Word documents with known field+SDT combinations. Fuzz with existing che-word-mcp test corpus. Field detection inside SDT must fall back cleanly to Field parser, not corrupt the SDT structure.

[Risk] Changing id allocation from random to max+1 on an in-place update of a document with existing random-id SDTs could create id adjacency that reveals bugs in downstream tools expecting sparse ids.
Mitigation: When computing max+1, scan the entire document including SDTs with ids outside the 100000-999999 range. Initial test fixture includes a document with mixed random-id and sequential-id SDTs.

[Risk] `replace_content_control_content` accepts raw XML from the caller — injection vector for malformed OOXML that corrupts the document.
Mitigation: Validate input XML against a whitelist of allowed elements (runs, paragraphs, tables, standard properties). Reject input containing `<w:sdt>`, `<w:body>`, `<w:sectPr>`, or XML declaration. Document the restriction in tool description.

[Risk] Max-id scan is O(n) on SDT count per insert. Documents with 1000+ SDTs see measurable latency.
Mitigation: Cache max id on Document open, update on every insert. O(1) per call after initial open. If cache miss, fall back to scan.

[Trade-off] Nested SDT flat-list representation duplicates data for callers who want the tree — they traverse parentId chains. Tree representation duplicates data for callers who want flat — they walk and flatten. Supporting both is a small code increase vs. forcing every caller to transform.

## Migration Plan

- che-word-mcp v3.7.x → v3.8.0 (this change).
- All changes are additive. No breaking changes to tool schemas.
- One internal breaking change: SDTs inserted via v3.8.0 have sequential ids; callers relying on random id "uniqueness-by-chance" across documents must switch to tag-based lookup.
- Binary release triggers marketplace sync per common-release-flow rule.
- Rollback: revert the che-word-mcp repo to v3.7.x release. ooxml-swift changes are version-pinned in Package.swift; rollback of che-word-mcp alone restores prior behavior.

## Open Questions

- Should `delete_content_control(keepContent: true)` leave the content inline in the paragraph (appears as regular text) or convert it to a new paragraph-level annotation? Current default assumption: inline (simpler). Confirm before implementing task 6.2.
- `list_custom_xml_parts` stub: raise a warning in tool description, or silent empty list? Leaning silent — warnings in tool output may be parsed incorrectly by MCP clients expecting structured JSON.
