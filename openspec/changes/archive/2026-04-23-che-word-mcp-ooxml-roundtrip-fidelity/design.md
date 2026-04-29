## Context

`ooxml-swift` and `che-word-mcp` ship a lossy `read → modify → write` pipeline:

- `DocxReader.read(from:)` (`packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift:17`): unzips the source `.docx` into a tempDir via `ZipHelper.unzip()`, parses the parts the typed model knows about (`document.xml`, `styles.xml`, `numbering.xml`, `comments.xml`, `commentsExtended.xml`, `footnotes.xml`, `endnotes.xml`, headers, footers, images, partial fontTable), then `defer { ZipHelper.cleanup(tempDir) }` deletes the tempDir before any write happens.
- `WordDocument` (`packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift:4`) is a value type with only typed fields — no escape hatch for parts the reader did not parse.
- `DocxWriter.write(_:to:)` (`packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxWriter.swift:34-238`) emits a fresh tempDir and ZIPs only what the typed model holds. Anything the reader did not parse is gone.

Issue #23 quantified the consequences on a real NTPU thesis fixture (referenced in issue body): `word/` parts 23 → 6, `[Content_Types].xml` `<Override>` entries 27 → 8, all 6 headers + 4 footers + entire `theme/` folder + `endnotes.xml` + `footnotes.xml` + `commentsExtended/Extensible/Ids.xml` + `people.xml` + `webSettings.xml` deleted; `fontTable.xml` 13 → 3 fonts (DFKai-SB / 華康中楷體 / PMingLiU / Microsoft JhengHei / Cambria Math stripped); `<w:tblStyle>` references broken. Visible breakage: watermark removed, Chinese fonts fall back to Times New Roman (NTPU thesis format violation), table styles revert, page numbers disappear.

The same lossiness blocks the entire `OOXML parts CRUD completeness` milestone (#24-#31). Adding `get_theme` / `update_theme_fonts` / `list_headers` / `delete_header` / etc. is meaningless if `save_document` strips theme1.xml and headers afterwards. All 9 issues unify under one architectural fix.

Stakeholders:
- NTPU thesis writers: immediate P0 — current state breaks template fidelity and forces manual re-formatting after every Claude session.
- Future `che-word-mcp` callers needing template-based authoring: same problem, latent.
- `che-pptx-mcp` maintainer: identical pattern will reappear when PPTX equation tooling lands; this change validates the overlay pattern that PPTX can adopt.

Repository constraints:
- `ooxml-swift` is a remote-url Swift Package owned by `PsychQuant/ooxml-swift`. v0.11.0 just shipped (MathAccent). Bumping to v0.12.0 for this architectural change.
- `che-word-mcp` is a git submodule under `mcp/che-word-mcp`. Currently v3.2.0 (LaTeX parser delegation). Phased ship to v3.5.0 across 3 batches.
- `pptx-swift` already depends on `ooxml-swift ^0.7.0`; bumping to ^0.12.0 will require it to opt-in to overlay mode (no breaking API change, just additive close() and overlay-mode trigger).

## Goals / Non-Goals

**Goals:**

- Make `DocxReader.read(thesis) → DocxWriter.write(_, to: out)` (with no edits in between) produce a `.docx` whose ZIP entry list and unmodified parts are byte-identical to the input.
- Unblock the 8 milestone CRUD APIs (#24-#31) so each can be implemented and tested in isolation without fighting the writer.
- Establish a `RelationshipIdAllocator` that prevents `rId` collisions between preserved original relationships and newly added ones, so future Add CRUD tools (e.g., `add_image`, `add_header`) work without breaking existing references.
- Define the `Content_Types.xml` overlay merge so unknown PartNames survive while typed parts get a single Override entry (no duplicates, no missing entries when typed model adds new parts).
- Ship Phase 2 in 3 batches (v3.3.0 / v3.4.0 / v3.5.0) so users get the highest-value tools (theme/headers/footers — the thesis fix) within ~1 week of Phase 1, rather than waiting ~3 weeks for one monolithic release.

**Non-Goals:**

- Typed-model parsing for every part. `commentsExtensible.xml`, `commentsIds.xml`, `tableStyles.xml`, `fontTable.xml` non-East-Asian entries remain opaque — preserved through the tempDir but not exposed as Swift types until a future change brings a CRUD API needing them.
- In-memory archive map (`[String: Data]`). Rejected in /spectra-discuss because tempDir is on disk for free; in-memory adds 5-50MB RAM per open document for no benefit.
- Background tempDir cleanup, LRU eviction, or any implicit lifecycle. `WordDocument.close()` is the only release path; callers that forget to call it leak tempDirs until process exit (acceptable for short-lived MCP sessions and CLI processes).
- Cross-platform tempDir handling beyond what `FileManager.default.temporaryDirectory` already provides. macOS-only is fine; matches the rest of the project.
- `che-pptx-mcp` adoption of overlay mode in this change. Separate change opened when PPTX needs equivalent fidelity.
- Refactoring `word-to-md-swift` `WordConverter` to call `close()`. Read-only one-shot CLI converters can leak tempDirs since the process exits anyway. Long-running consumers (none today) will revisit when they appear.
- Introducing concurrency primitives for thread-safe shared `WordDocument` access. Each MCP session owns its own document; no shared mutation today, no need for locking now.

## Decisions

### Decision: PreservedArchive is a tempDir-backed reference, not an in-memory `[String: Data]`

**Choice**: `WordDocument` gains a private property `archiveTempDir: URL?` that points to the unzip tempDir created by `DocxReader.read()`. The Reader removes its current `defer { ZipHelper.cleanup(tempDir) }` and instead stores the tempDir URL on the returned `WordDocument`. The Writer in overlay mode reads from the tempDir as the base, overwrites typed-model parts in place, then `ZipHelper.zip(tempDir, to: dest)`. A new public `WordDocument.close()` method calls `ZipHelper.cleanup(archiveTempDir)` and sets the URL to nil.

**Rationale**: Three reasons. (1) `ZipHelper.unzip()` already produces a tempDir on disk; reusing it costs zero extra I/O. (2) NTPU thesis ZIPs are 5-50MB; in-memory copies of 100MB+ M365 collaborative docs would consume RAM unnecessarily. (3) `ZipHelper.zipToData(directory:)` already walks tempDirs to build output ZIPs — overlay mode reuses the same code path. This is a ~30 LOC change in DocxReader/Writer, not a rewrite.

**Alternatives considered**:

- **In-memory `[String: Data]` map of all entries**. Rejected: 5-50MB RAM per open document with no benefit; needs a parallel write-back to tempDir before zipping, doubling I/O.
- **Lazy on-demand part reading from the source `.docx` ZIP without ever extracting**. Rejected: ZIPFoundation's random access has higher overhead than tempDir flat-file reads, and complicates write paths that need to inject new parts.
- **Hybrid: typed parts in memory, unknown parts via on-demand archive reads**. Rejected as premature optimization; if memory becomes a problem, switch later.

### Decision: WordDocument.close() is explicit; no automatic cleanup

**Choice**: `WordDocument` exposes `public mutating func close()` that releases the tempDir. Documents created via `WordDocument(...)` initializers (the `create_document` MCP tool path, in-memory authoring) have `archiveTempDir == nil` and `close()` is a no-op. Reader callers SHALL call `close()` when finished. `che-word-mcp`'s session lifecycle (which already tracks open documents per `doc_id`) will call `close()` on `close_document` MCP tool invocations and on session shutdown.

**Rationale**: Swift value types do not support `deinit`; a class wrapper would change the entire `WordDocument` API surface. The MCP server already has clear close points (`close_document` tool, session lifecycle), so explicit is fine. Process exit cleans up `/tmp` automatically on macOS, so leaks are bounded.

**Alternatives considered**:

- **Class-wrap `WordDocument` for `deinit` cleanup**. Rejected: turns a value type into a reference type, breaking copy semantics that 200+ callers depend on, and deinit timing is unpredictable.
- **Auto-cleanup via a registry tracked by `DocxReader`**. Rejected: adds a global mutable registry, threading concerns, and hides the lifecycle from callers.
- **Background cleanup task scanning `/tmp` for stale `che-word-mcp/*` dirs**. Rejected: implicit cleanup obscures bugs; one process clobbering another's tempDir is a real risk.

### Decision: DocxWriter has two modes — overlay (when archiveTempDir set) and scratch (when nil)

**Choice**: `DocxWriter.write(_ document: WordDocument, to dest: URL)` checks `document.archiveTempDir`:
- **If set (round-trip mode)**: write all typed-model parts directly into the existing tempDir, overwriting `word/document.xml`, `word/styles.xml`, header/footer files, `word/footnotes.xml`, `word/endnotes.xml`, `word/comments*.xml`, `word/media/*`, `word/_rels/document.xml.rels`, and `[Content_Types].xml` (the latter two via overlay merge). Then `ZipHelper.zip(tempDir, to: dest)`.
- **If nil (scratch mode)**: behaves exactly as today — build a fresh scratch tempDir from the typed model. Path used by `create_document` and any future programmatic builder that doesn't have a source `.docx`.

**Rationale**: Two modes cleanly separate "round-trip preserve" semantics from "build from scratch" semantics. Scratch mode requires no behavior change (back-compat). Overlay mode reuses the file-writing helpers that scratch mode already has, just targeting a different directory. Minimum diff.

**Alternatives considered**:

- **Always rebuild from typed model + a separate "preserved parts" map maintained alongside**. Rejected: requires the Reader to load every unknown part into memory, and the Writer to know how to merge them with typed parts — more complex than the tempDir overlay.
- **Always run overlay mode by extracting an empty docx skeleton when there's no source**. Rejected: extra I/O and complexity for documents that don't need preservation.

### Decision: RelationshipIdAllocator scans original rels and types together

**Choice**: A new `class RelationshipIdAllocator` (initialized at write time) takes the original `_rels/document.xml.rels` content (parsed from `archiveTempDir`) plus the typed model's relationship-bearing fields (`document.headers`, `document.footers`, `document.images`, `document.hyperlinkReferences`, `document.comments`, `document.footnotes`, `document.endnotes`). On `init`, it scans both for in-use `rId` integers and computes `nextId = max(observed) + 1`. Methods: `allocate() -> String` returns `"rId\(nextId)"` and increments; `reserve(_ id: String)` marks an ID as taken (for typed parts that already have stable rIds from the reader).

**Rationale**: The current code at `DocxWriter.swift:238` uses `usedCount = document.headers.count + document.footers.count + ...` which assumes the typed model knows about all existing relationships. With preserve-by-default, original rels are kept verbatim → naive counter collides. Allocator centralizes ID generation so any future `add_header` / `add_image` / `add_footer` tool gets a clash-free rId.

**Alternatives considered**:

- **Keep naive counter and rely on tests to catch collisions**. Rejected: collisions corrupt cross-references invisibly, and the new tools (#26 `delete_header`, #27 `delete_footer`) actively need rId stability across operations.
- **UUID-based rId generation**. Rejected: Word accepts long IDs but UUID-style breaks readability of the rels XML in tooling, and mixing numeric + UUID confuses the reader.

### Decision: Content_Types.xml overlay merge — preserve unknown Overrides, dedupe typed Overrides

**Choice**: A new `struct ContentTypesOverlay` parses the original `[Content_Types].xml` from `archiveTempDir` and exposes `merge(typedParts: [PartDescriptor]) -> String`:
1. Extract original `<Override>` entries → keep all of them as a starting set.
2. For each typed part the writer is about to emit (e.g. `/word/document.xml`, `/word/header2.xml`, `/word/media/image3.png`), look up its declared content type from a static table.
3. If the original set has an `<Override>` with the same PartName, replace it with the typed-part-derived one (typed model is authoritative for parts it manages).
4. If the original set has no entry for this PartName, add the typed-part-derived one (handles newly-added parts like a fresh `insert_image`).
5. Original entries for unknown PartNames (theme, webSettings, people, etc.) are preserved unchanged.
6. Same algorithm runs for `<Default>` content type extensions.

**Rationale**: This is the simplest correct merge — caller-extensible (any typed part the writer manages contributes one Override), preservation-respecting (anything the writer doesn't touch survives). Tested by round-trip fidelity assertion.

**Alternatives considered**:

- **Always emit a fresh `[Content_Types].xml` from typed parts only**. Rejected: this is the current bug — strips theme/webSettings/etc. Overrides.
- **Always preserve the original `[Content_Types].xml` verbatim**. Rejected: breaks when caller adds a new image (typed model has new `/word/media/imageN.png` but Content_Types lacks the Override → Word complains on open).
- **Diff-and-patch the XML AST**. Rejected: more complex than the simple set merge.

### Decision: Phase 2 ships in 3 batches by SDD value, not all at once

**Choice**: After Phase 1 (`ooxml-swift` v0.12.0) ships, Phase 2 splits into:
- **Batch 2A — `che-word-mcp` v3.3.0**: theme tools (#28) + headers/footers tools (#26 #27). User-visible: NTPU thesis fix.
- **Batch 2B — `che-word-mcp` v3.4.0**: comment thread tools (#29) + people tools (#30). User-visible: collaborative comment workflow fidelity.
- **Batch 2C — `che-word-mcp` v3.5.0**: notes update tools (#24 #25) + web settings tools (#31). User-visible: polish.

Each batch is a separate `che-word-mcp` minor version with its own release notes, .mcpb upload, and marketplace sync. Each batch's `che-word-mcp` repo PR can land 1-3 days after Phase 1 ships.

**Rationale**: The thesis fix is the original triggering need (issue #23 was filed during NTPU thesis work). Shipping 2A within ~1 week of Phase 1 lets users start using the thesis-correct tools immediately. Batches 2B and 2C are valuable but downstream of authoring. Monolithic single SDD-apply session bundling all 21 new MCP tools would take ~2-3 weeks of implementation, blocking users for the duration.

**Alternatives considered**:

- **Single monolithic `che-word-mcp` v3.3.0 with all 21 tools**. Rejected: long blocking window; harder to review; if any one tool's design needs revision, the whole release stalls.
- **One issue per batch (3 separate spec changes)**. Rejected: the proposal/design context is shared across all 3 batches; splitting forces duplicate spec writing and risks design drift between batches.
- **Ship Phase 1 + Batch 2A together as v0.12.0 + v3.3.0 atomic pair**. Considered but rejected: Phase 1 needs to ship and bake (CI green, no consumer breakage observed) before downstream consumers integrate it. ~1 day of bake time costs nothing.

### Decision: Regression test fixture is a hand-crafted minimal multipart docx, not the NTPU thesis

**Choice**: Create `packages/ooxml-swift/Tests/OOXMLSwiftTests/Fixtures/minimal-multipart.docx` — a deliberately constructed minimal `.docx` (~30KB) containing exactly: 1 paragraph in body, 1 default header, 1 default footer, theme1.xml with one `minorEastAsia` font set, one `<w15:person>` in people.xml, one webSettings.xml setting (`relyOnVML=true`), one image in media/, and minimal styles/numbering/comments. The round-trip test reads, writes without edits, and asserts the output ZIP entry list equals the input entry list AND each unmodified part is byte-equal.

**Rationale**: NTPU thesis is private (privacy + copyright) and 5MB+ — too large for repo and untestable in CI. A 30KB fixture covers every relevant code path (header/footer/theme/people/webSettings/image overlay) and stays under git LFS thresholds. Hand-crafting once is a 1-2 hour task; the fixture lives forever as a regression guard.

**Alternatives considered**:

- **Use the NTPU thesis as fixture**. Rejected: privacy + size + copyright.
- **Generate fixture programmatically at test setup**. Rejected: the thing being tested IS the writer, so generating with the writer is circular.
- **Use a public template from Microsoft templates gallery**. Considered: viable but the templates are large and feature-mixed, hurting test diagnostics. The minimal hand-crafted approach is more targeted.

## Risks / Trade-offs

- **Memory + disk pressure on long-lived MCP sessions** → Mitigation: `che-word-mcp` `close_document` MCP tool already exists; this change wires it to call `WordDocument.close()`. Document MCP-server-side timeouts that auto-close idle docs after N minutes (out of scope for this change but tracked as Phase 4 follow-up if reports surface).

- **Tests must run in parallel without tempDir collisions** → Mitigation: `ZipHelper.unzip()` already uses `UUID().uuidString` for tempDir naming → no collision risk; verify in `RoundTripFidelityTests` that parallel execution stays clean.

- **Reader-side parser changes (Phase 2 typed parsing for theme/people/etc.) could regress preservation** → Mitigation: every Phase 2 batch SHALL re-run `RoundTripFidelityTests` on the minimal-multipart fixture before merge. Adding typed parsing for a part means `DocxWriter` will overwrite that part on save — which is correct behavior, but the round-trip-without-edits test needs to verify the typed serializer is byte-equivalent to the original (or at least semantically equivalent — likely XML-canonical-equality, not byte-equality, since attribute order may differ).

- **Byte-for-byte equality is too strict for typed parts after Phase 2** → Mitigation: split the round-trip test into two assertions: (a) ZIP entry list equality (rigid), (b) per-entry XML equality with mode "exact-bytes for unknown parts, canonical-XML for typed parts". Defer the canonical-XML implementation to Phase 2 first batch.

- **`RelationshipIdAllocator` initialization performance on docs with many existing rels (>1000)** → Mitigation: scanning the rels XML with regex is O(n) one-time per document open; bench against a synthetic 5000-rel document to confirm <50ms.

- **`Content_Types.xml` overlay drops a typed-part Override the Reader thought existed but writer doesn't emit (e.g., footnote part deleted by `delete_footnote`)** → Mitigation: the overlay treats the typed model as authoritative for known PartNames — if the writer doesn't emit `/word/footnotes.xml`, the overlay drops the entry. Add an explicit "deletable typed parts" enumeration so the deletion behavior is intentional, not accidental.

- **Phase 2 batches might find architectural gaps in Phase 1** → Mitigation: Phase 1 ships v0.12.0 with explicit tagged release; if Phase 2A (or later) needs a Phase 1 patch, ship v0.12.1 / v0.12.2 etc. Phased shipping makes this tractable.

- **`pptx-swift` dep bump from `^0.7.0` to `^0.12.0` could regress PPTX consumers** → Mitigation: `pptx-swift` doesn't currently use any of the new APIs added in 0.8.x-0.11.x or this change; the bump is purely for `MathAccent` and overlay-mode availability. CI in `pptx-swift` should run before merging the dep bump in `mcp/che-pptx-mcp`.

- **Unknown parts could contain malicious content (XML bomb, ZIP slip)** → Mitigation: ZIPFoundation already protects against ZIP slip; we don't parse the unknown parts so XXE/XML-bomb risk is zero for them. Document this in `SECURITY.md`.

- **`fontTable.xml` partial typed parsing today loses 10/13 fonts on round-trip** → Mitigation: in Phase 1, leave `fontTable.xml` typed-part-managed (current behavior), but ALSO preserve the original via overlay if the writer's emitted version drops fonts the original had. This requires `fontTable.xml` to NOT be in the "deletable typed parts" set — it's read-and-merged: typed model adds fonts the typed paths used, original fonts the typed model didn't see are preserved. Specific implementation detail: after Phase 1, in `Tests/OOXMLSwiftTests/RoundTripFidelityTests`, verify the fixture's 13 fonts all survive.

- **`Tests/OOXMLSwiftTests/Fixtures/minimal-multipart.docx` is a binary fixture in git** → Acceptable: 30KB is well under git LFS thresholds; one-time creation, infrequent change. If the fixture needs editing, document the procedure in a `Fixtures/README.md`.

- **`che-word-mcp` v3.3.0 / 3.4.0 / 3.5.0 phased ship triples release ceremony cost** → Acceptable: each release is automated via CHANGELOG + tag + .mcpb upload + marketplace sync; ~10 min per batch. Worth it to unblock users incrementally.
