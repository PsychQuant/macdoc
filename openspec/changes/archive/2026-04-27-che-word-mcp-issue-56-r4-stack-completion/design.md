## Context

Issue #56 round 4 verify (6 reviewers, BLOCK) found that the R3 stack-completion (v0.19.4 local commits) closed its narrow tests but each fix's actual coverage was narrower than design.md claimed. The R2→R3→R4 cycle has now repeated three times. R5 must close the structural root causes, not just patch symptoms.

Current state (LOCAL ONLY, never pushed):

- `ooxml-swift` main: 7 commits ahead of `v0.19.3`, HEAD is R3-NEW-6 audit table fix.
- `che-word-mcp` main: 0 commits ahead, working tree dirty (`Package.swift` on `path:` dep, `mcpb/manifest.json` bumped to `3.13.4`, `CHANGELOG.md` `[3.13.4]` entry added).
- No git tags pushed for v0.19.4 or v3.13.4.

Constraints:

- **Per-task verify gate discipline**: same as R3 stack-completion — each P0 fix passes its own scoped Codex verify before commit, no bundled R5 verify at the end.
- **Source layering**: ooxml-swift carries all source changes; che-word-mcp is dep bump + CHANGELOG only (zero MCP source changes), preserving the R2-established discipline.
- **No breaking API changes** to public ooxml-swift types beyond what R3 already broke (`Hyperlink.id` format change documented in R3 D-8). New helpers added internally; existing public APIs gain dirty-tracking or stricter throw behavior, but signatures stay compatible.
- **Test discipline**: every R5 fix's regression test calls `DocxWriter().write(document:to:)` then `DocxReader().read(from:)` and asserts on the re-read document. R3's all-in-memory-only test pattern is the verified blind spot.

Stakeholders:

- macdoc CLI / che-word-mcp MCP server: `accept_revision`, `reject_revision`, `apply_style`, `create_style`, `update_style`, `create_numbering_definition`, `set_paragraph_border`, `move_text_as_revision`, `update_hyperlink`, `delete_hyperlink`, `replace_text` (header/footer/footnote/endnote-targeted), `insert_content_control`, `insert_footnote` are all currently affected by one or more of the 6 P0 findings.
- Downstream automation (Tatsuma manuscript pipeline) consumes `accept_revision` on documents with header tracked changes and SDT-wrapped revisions — currently silently corrupts those.

## Goals / Non-Goals

Goals:

1. Six R4 P0 findings closed with regression tests that fail on `main` (pre-R5) and pass after fix.
2. Seven R4 P1 findings closed with at least one test exercising the previously-silent path.
3. Three structural anti-patterns eliminated:
   - **Walker asymmetry** (parallel walkers of the same shape, only one fixed) → unified walker abstraction.
   - **Sentinel collision** (`position == 0` overloaded) → reader assigns `position >= 1` for source children.
   - **Audit-table-as-self-attestation** (deny-list "all sites covered") → allow-list (explicit named exemptions with rationale).
4. Save→reread roundtrip becomes the default test pattern for revision/SDT/escape/replace fixes.
5. v0.19.5 + v3.13.5 jointly tagged, marketplace synced.

Non-Goals:

- **Not** a typed `XMLAttribute` wrapper struct (deferred to Phase 2 hardening).
- **Not** a streaming-model refactor of OOXML reader/writer.
- **Not** addressing R4 P2 findings (DA-N9 acceptAll try? scope is included as P1 #9; DA-N10 brittle invariant; DA-N11 cache compatibility; DA-N12 covered-set start/end naming) — separate hardening change.
- **Not** publishing v0.19.4 (skipped tag).

## Decisions

### Decision 1: Unified walker abstraction `walkAllParagraphs` vs ad-hoc walkers

R3-NEW-5 introduced `walkAllParagraphs(in:visit:)` for `nextBookmarkId` calibration that recurses into body, tables, nested tables, content controls, headers, footers, footnotes, endnotes. R3-NEW-4's `handleMixedContentWrapperRevision` uses a separate ad-hoc walker that only goes body + first-level table cells. R5 must collapse the two to one abstraction.

**Decision**: Promote walking to a generic `DocumentWalker` namespace with two entry points:

- `DocumentWalker.walkAllParagraphs(in document: Document, visit: (Paragraph, partKey: String) -> Void)`
- `DocumentWalker.findUnrecognizedChild(in document: Document, name: String, idMarker: String) -> (paragraph: Paragraph, indexInParagraph: Int, partKey: String)?`

Both walkers internally share a `walkAllParagraphsWithPart` recursion that emits `(Paragraph, partKey)` tuples. Callers get a `partKey` (`"word/document.xml"`, `"word/header1.xml"`, etc.) for accurate `modifiedParts` tracking. `handleMixedContentWrapperRevision` becomes a thin caller of `findUnrecognizedChild`. R3-NEW-5's calibration also routes through `DocumentWalker`.

**Rejected alternative**: Keep two walkers and just sync them by hand. Rejected because that's the exact anti-pattern R4 R3-NEW-5 codex P1 catch already proved: hand-sync forgets nested tables.

**Trade-off**: New abstraction layer with one extra indirection. Acceptable; R5 has 6 P0 callers across revision, replace, hyperlink, bookmark — the abstraction pays for itself within R5 itself.

### Decision 2: Hyperlink mutation detection — deep equality vs explicit dirty flag

R3-NEW-1 `Hyperlink.toXML()` compares `runs` joined text against `children`-derived run text. R4 verify (logic L1+L2, DA-R2, regression #5) showed this misses formatting-only mutations and equal-length boundary swaps.

Two options:

- **Option A — Deep equality** on `[Run]`: compare `runs` element-wise on text + properties (bold, italic, color, fontSize, fontName, etc.).
- **Option B — Explicit dirty flag**: `Hyperlink` gains `private(set) var runsDirty: Bool = false`. Mutating accessors (any code path that writes `runs`) set the flag. `toXML()` checks the flag instead of doing equality.

**Decision**: Option A (deep equality). Rationale:

- Option B requires every mutation path to set the flag, which is the same coverage problem R3-NEW-1 had with text-equality. New mutation APIs added in future would forget the flag. Deep equality is a Self-detecting check: as long as the property survives `Codable` round-trip, the comparison is automatic.
- Performance cost is negligible — hyperlinks have few runs (typically 1-3); `Run` is `Equatable` already (used by Revision tests).
- Explicit `runsDirty` would also need analogous `childrenDirty` and `propertiesDirty` for symmetry — combinatorial state explosion.

**Caveat documented in design**: Equal `Run` arrays whose `children` representation differs (e.g., reorder of non-run elements) are still ambiguous. R5 explicitly documents this as out-of-scope (the `children` rawXML capture is the source of truth for non-run order; mutation-aware writer only handles run-text-or-properties changes). `replaceText` and other mutating APIs do not touch non-run children.

### Decision 3: SDT position sentinel — reader-side `position >= 1` vs caller-side check

R3-NEW-2 added `ContentControl.position: Int` with `default 0`. `Paragraph.toXMLSortedByPosition` filters `> 0` for sorted entries. R4 codex R4-NEW-1 showed first-child source SDT (which gets `position == 0` from reader) is filtered out and demoted to legacy emit at end.

**Decision**: `DocxReader.parseParagraph` assigns `position` starting at `1` for all source children (paragraphs, content controls, runs that route through positioned emit). `position == 0` becomes the unambiguous "API-built sentinel" — a value only set when callers create a new `ContentControl` programmatically without specifying position.

Implementation:

- `parseParagraph` initializes `var childPosition = 1` (was `0`).
- All call sites that pass `childPosition += 1` continue as-is; net effect is positions start at 1 instead of 0.
- `Paragraph.toXMLSortedByPosition` includes ALL `contentControls` in positioned entries (drops `> 0` filter).
- Legacy emit path (which prepends API-built children at end) includes only `position == 0` items.
- `hasSourcePositionedChildren` checks `contentControls.contains { $0.position > 0 }` (drops the now-redundant filter on contentControls but keeps it as the source-marker semantic).

**Trade-off / Migration**: Existing serialized `Document` JSON snapshots (if any consumer caches them) with `ContentControl.position == 0` would have been "API-built sentinel" before the change too, so no semantic shift on existing data. New documents reread under v0.19.5 get `position >= 1` for source children.

### Decision 4: XML attribute escape — shared module + allow-list audit

R3-NEW-6 created `fileprivate escapeXMLAttribute` in `Run.swift`. R4 security review found 22 P0 unescaped sinks across 8 files, plus 15+ duplicated `fileprivate` escape helpers spread across files (each file's own implementation, slightly different `&apos;` vs `&#39;` choices).

**Decision**: Create `Sources/OOXMLSwift/IO/XMLAttributeEscape.swift` exposing `internal func escapeXMLAttribute(_ s: String) -> String`. Single source of truth. Sweep:

- All 15+ `fileprivate escapeXMLAttribute` definitions deleted, replaced with `import` of internal symbol (already in same module — no import needed; just call directly).
- All raw `String` interpolations into `w:val="..."`, `w:color="..."`, `w:name="..."`, `w:fill="..."`, `w:val2="..."`, `w:author="..."` etc. routed through the helper.
- Five XML special chars: `&`, `<`, `>`, `"`, `'`. Use `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;` (note: standardize on `&apos;` for byte-equality with Word's own emit; R3-NEW-6's `&#39;` was a divergence flagged in logic L7).

**Audit table flips to allow-list**: `Issue56R4StackTests.swift` includes a comment block listing files/sites that are **NOT** routed through the helper, with rationale for each:

- Test fixture builders that emit known-safe constants
- Hardcoded XML preamble strings (xmlns declarations)
- Numeric attribute values that go through `String(Int)` (no user-controlled chars)
- etc.

Reviewer can then verify by checking only the named exemptions, not by re-scanning the entire codebase.

### Decision 5: Container parser `<w:tbl>` capture — extend `paragraphs` vs add `bodyChildren`

`parseContainerParagraphs` (`DocxReader.swift:1101/1123`) returns `[Paragraph]` for `<w:hdr>/<w:ftr>/<w:footnote>/<w:endnote>`. R4 codex R4-NEW-3 + DA-R3 showed `<w:tbl>` siblings are silently dropped, hiding header table bookmarks from `nextBookmarkId` calibration.

**Decision**: Rename function to `parseContainerBody` returning `[BodyChild]` (existing enum used by `Document.body.children`). Update Header/Footer/Footnote/Endnote models:

- Add `public var bodyChildren: [BodyChild]` field.
- Keep existing `public var paragraphs: [Paragraph]` as a backward-compat computed view: `bodyChildren.compactMap { if case .paragraph(let p) = $0 { return p } else { return nil } }`.
- `toXML()` emits from `bodyChildren` (handles paragraph + table). Old emit path that iterated `paragraphs` is replaced.

Caller compat: existing public `Header.paragraphs[i]` reads still work. Mutators that wrote to `paragraphs` directly are migrated to write `bodyChildren` and the spec gains a deprecation note (no breaking change in v0.19.5; targeted for removal in v0.20.0).

`DocumentWalker` (Decision 1) recurses into `bodyChildren` for these containers, surfacing all bookmarks/revisions inside header tables to calibrators and revision walkers.

### Decision 6: Test pattern — save→reread roundtrip mandate

R3 stack tests had zero `DocxWriter.write` calls. R4 verify (DA-N5) flagged this as the proven blind spot of the R2→R3 cycle.

**Decision**: R5 introduces a test helper `Tests/OOXMLSwiftTests/Helpers/RoundtripHelper.swift`:

```
func roundtrip(_ document: Document) throws -> Document {
    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).docx")
    try DocxWriter().write(document, to: tmpURL)
    defer { try? FileManager.default.removeItem(at: tmpURL) }
    return try DocxReader().read(from: tmpURL)
}
```

Every R5 P0/P1 test:

1. Builds document state (in-memory or by reading a fixture).
2. Performs the mutation under test.
3. Calls `roundtrip(doc)` to get the re-read document.
4. Asserts on the re-read document.

R5 also retro-fits the R3 tests: `Issue56R3StackTests.swift` gains a parallel "RoundtripVariants" test group that wraps each existing R3 test through `roundtrip`. Any R3 test that fails on roundtrip variant becomes an R5 fix or a documented limitation.

### Decision 7: Release artifact handling — skip v0.19.4 vs back-out

R4 verify regression #2 + DA recommendation 1 flagged that CHANGELOG `[0.19.4]` and manifest `3.13.4` are committed locally but no tag exists, breaking end-user clones if they checkout `v3.13.4`.

**Decision**: Skip v0.19.4 entirely. R5 work merges into v0.19.5 / v3.13.5 directly. CHANGELOG handling:

- `packages/ooxml-swift/CHANGELOG.md` `[0.19.4]` section header gets renamed to `[0.19.5]` and gains R5 entries below the existing R3 stack content (which stays as-was — accurate for the R3 stack work that landed). A new "Skipped versions" subsection at top of CHANGELOG documents that v0.19.4 was BLOCKed by R4 verify and never released, content rolled into v0.19.5.
- `mcp/che-word-mcp/CHANGELOG.md` follows the same pattern: `[3.13.4]` becomes `[3.13.5]`, R5 entries appended, "Skipped versions" subsection at top.
- `mcp/che-word-mcp/mcpb/manifest.json` bumps from `3.13.4` to `3.13.5`.
- `mcp/che-word-mcp/Package.swift` reverts from `path:` dep to `.package(url: "https://github.com/PsychQuant/ooxml-swift.git", from: "0.19.5")` as the final R5 task before tag.

**Rejected alternative**: Back out v0.19.4 commits, redo as v0.19.5 squashed. Rejected because the R3 stack work is correct (closed its narrow tests), just incomplete; squashing loses the per-fix granularity that documents what each R3 fix did.

## Risks / Trade-offs

- **Risk**: R5 itself replicates the bundle-and-regress pattern. **Mitigation**: per-task verify gate (same discipline as R3 stack), each P0 commits independently after passing scoped Codex verify; final R5 verify is a regression-floor check, not the per-fix gate.
- **Risk**: `DocumentWalker` abstraction adds indirection that obscures hot paths. **Mitigation**: wrap with `@inlinable` if profiling shows overhead; current paths are not in tight loops (revision accept/reject is once-per-user-action).
- **Risk**: Deep equality on `[Run]` for hyperlink mutation detection misses non-`Equatable` properties added in future. **Mitigation**: `Run` already has `Equatable` synthesis; future fields added must conform. R5 design.md documents this as a maintenance contract.
- **Risk**: Container model migration (Header.bodyChildren) breaks downstream consumers that read `Header.paragraphs.count`. **Mitigation**: `paragraphs` becomes a computed property over `bodyChildren`, preserving the read API. Writers migrated as part of R5; no deprecation period needed because the only writer is internal `DocxReader`.

## Migration Plan

1. R5 development on local `ooxml-swift` `main` (continues from R3 stack 7-commit local-only state).
2. Each P0 fix: failing test → impl → green → suite check → scoped Codex verify → individual commit (same per-task gate as R3 stack-completion).
3. P1 fixes batched into one commit per P1 (or grouped by file).
4. After all P0+P1: full `swift test` for ooxml-swift (582+ tests stay green).
5. R5 final 6-AI verify (Agent Team + Codex) — if BLOCK → R6 spectra change; if PASS → release.
6. Release sequence (only after PASS):
   1. Revert `mcp/che-word-mcp/Package.swift` from `path:` to `from: "0.19.5"`.
   2. `cd packages/ooxml-swift && git tag v0.19.5 && git push --tags && git push origin main`.
   3. `cd mcp/che-word-mcp && swift package update && swift test` (verify against released v0.19.5).
   4. Commit che-word-mcp dep + CHANGELOG + manifest as `chore: bump ooxml-swift to v0.19.5`, tag `v3.13.5`, push.
   5. `/plugin-tools:plugin-update che-word-mcp` to sync marketplace.
7. Post R5 verify comment to #56 + run `/issue-driven-dev:idd-close #56` if R5 verify clean.
8. Update PsychQuant/macdoc#75 (umbrella) checkbox for "Issue #56 manuscript review automation: hyperlink mutation round-trip".

## Open Questions

- Should `XMLAttributeEscape` standardize on `&apos;` vs `&#39;`? **Resolved in Decision 4**: `&apos;` for byte-equality with Word's own emit.
- Should R5 also fix R4 P2 findings (DA-N9-N12)? **Resolved in Non-Goals**: deferred to a separate hardening change to keep R5 scope manageable.
- Should `Header.paragraphs` be removed in v0.19.5 or deprecated? **Resolved in Decision 5**: kept as computed property with deprecation marker; removal deferred to v0.20.0.
