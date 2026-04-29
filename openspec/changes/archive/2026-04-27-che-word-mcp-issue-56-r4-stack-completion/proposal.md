## Problem

Issue #56 round 4 verify (6 independent reviewers — 5 Claude teammates + Codex gpt-5.5) returned **BLOCK** with 6 P0 + 7 P1 findings. The R3 stack-completion fixes (v0.19.4, currently local-only commits) closed the R3 narrow tests but each fix's coverage was narrower than its design.md claim, replicating the R2→R3 bundle-and-regress anti-pattern at the reviewer-test boundary.

Concretely, R3-NEW-4 (mixed-content revision wrapper) only walks `body.children` + first-level table cells; R3-NEW-2 (SDT position) collides `position == 0` between source-position-0 and API-built sentinel; R3-NEW-6 (XML attribute escape) audit table self-attested coverage of "all attribute sites" but only patched `Run.swift` and `Revision.swift` while 22 unescaped `String` → `w:val="..."` interpolations remain across `Style.swift`, `Numbering.swift`, `Table.swift`, `Field.swift`, `MathComponent.swift`, `DocxWriter.swift`. Block-level SDT typed Revision is never propagated to `document.revisions.revisions` (`DocxReader.swift:280-286 case .contentControl: break`), making MCP `accept_revision` throw `notFound` for SDT-wrapped content. `Document.replaceText` headers/footers/footnotes/endnotes path only walks `para.runs`, asymmetric to body which routes through `replaceInParagraphSurfaces`, silently dropping edits to text inside hyperlinks/fieldSimples in headers.

Finally, the v0.19.4/v3.13.4 release artifact is internally inconsistent: CHANGELOG entries claim the version but no git tag exists and `che-word-mcp/Package.swift` is on `path:` dep, so end-user clones of `v3.13.4` would fail to build.

## Root Cause

The R2→R3→R4 cycle root cause is that each fix's verification scope was narrower than the structural invariant it claimed to restore:

1. **Walker asymmetry**: `walkAllParagraphs` (calibration) was hardened to recurse into all parts and nested tables, but the parallel walker `handleMixedContentWrapperRevision` (revision accept/reject) was not. Two walkers of the same shape, one fixed, one stale.
2. **Sentinel collision**: `position == 0` was overloaded as both "first source position" and "API-built default" because `ContentControl.position` was added with `default 0` for source-compat. R3-NEW-2 routed `position > 0` into sorted emit and kept `position == 0` on legacy emit path, which silently demotes source-position-0 SDTs to end of paragraph.
3. **Audit-table-as-self-attestation anti-pattern**: R3-NEW-6's audit table was a **deny-list** (claims "every attribute site escaped") with no negative test. A reviewer must scan the entire codebase to refute it; the change-author's own scope didn't include `Style.swift`/`Numbering.swift`/etc.
4. **Container parser drops `<w:tbl>`**: `parseContainerParagraphs` (`DocxReader.swift:1101/1123`) only collects direct `<w:p>` children of `<w:hdr>/<w:ftr>/<w:footnote>/<w:endnote>`, silently discarding `<w:tbl>` siblings — so even the R3-NEW-5 calibration walker's recursion into headers/footers can't see bookmarks inside header tables.
5. **Test-suite blind spot**: `Issue56R3StackTests.swift` (932 lines, 12 R3 tests) has zero `DocxWriter.write` calls. Every R3 test bypasses full save → re-read roundtrip, the exact dimension R2→R3 cycle proved costly.

## Proposed Solution

**Per-task verify gate discipline continues** (R3 stack-completion's structural counter to bundle-and-regress). 6 P0 + 7 P1 fixes, each with: failing test → impl → green → suite check → scoped Codex verify → individual commit. ooxml-swift carries all source changes; che-word-mcp is dep bump + CHANGELOG only.

P0 fixes:

1. **Unify revision wrapper walker**: Refactor `handleMixedContentWrapperRevision(revisionId:wrapperName:accept:)` (`Document.swift:2329`) to delegate to a generalized `findUnrecognizedChildAcrossParts` helper that walks body (incl. nested tables, content-control children), headers, footers, footnotes, endnotes — same shape as `walkAllParagraphs` from R3-NEW-5. Helper returns `(found: Bool, partKey: String)`. Caller sets `modifiedParts.insert(partKey)` (not blanket `word/document.xml`) on success and `throw RevisionError.notFound(revisionId)` on miss. Replace silent return.

2. **SDT position collision**: Reader assigns `position` starting at `1` for all source children (paragraphs and content controls). `position == 0` becomes the unambiguous "API-built sentinel" meaning. `Paragraph.toXMLSortedByPosition` includes ALL contentControls in positioned entries (drops the `> 0` filter); legacy emit path includes only `position == 0`. Update `hasSourcePositionedChildren` to check `contentControls.contains { $0.position > 0 }` consistently. Roundtrip test: `<w:sdt>...</w:sdt><w:r>B</w:r>` round-trips with SDT first, R first.

3. **Shared `XMLAttributeEscape` module**: New `Sources/OOXMLSwift/IO/XMLAttributeEscape.swift` with `public func escapeXMLAttribute(_:)`. Sweep all 15+ fileprivate duplicates and replace with the shared helper. Sweep `String` → `w:val="..."` / `w:color="..."` / `w:name="..."` / `w:fill="..."` interpolations across `Style.swift`, `Numbering.swift`, `Table.swift`, `Field.swift`, `MathComponent.swift`, `DocxWriter.swift`, `Paragraph.swift`, `Revision.swift` (MoveTracking.moveId). Audit table flips to **allow-list**: explicit list of files/sites NOT yet routed through the helper, with rationale (test-only emitters, hardcoded constants, etc.).

4. **Block-level SDT typed Revision propagation**: `DocxReader.swift:280-286` change `case .contentControl: break` to recurse into `contentControl.children` (which contain `BodyChild` paragraphs/tables) and propagate any typed Revisions found into `document.revisions.revisions`. Match the existing recursion pattern used for tables.

5. **`Document.replaceText` headers/footers/footnotes/endnotes symmetry**: Refactor the four container loops in `Document.swift:429-480` to call `replaceInParagraphSurfaces(...)` (the body path's helper). Surfaces include hyperlinks, fieldSimples, alternateContents, etc. Single source of truth for replace logic; container loops just iterate paragraphs and delegate.

6. **Release bump v0.19.5 / v3.13.5**: Keep R4 commits local; R5 stack adds on top. Final release tags v0.19.5 + v3.13.5 jointly. CHANGELOG `[0.19.5]` and `[3.13.5]` sections cite both R3 stack content (carried from v0.19.4 local commits) and R4 fixes. Mark `[0.19.4]` as "skipped — see [0.19.5]" to record the BLOCKed release for posterity.

P1 fixes (rolled into same R5):

- **Hyperlink mutation deep equality**: Change `Hyperlink.toXML()` mutation detection from text-equality to a deep equality on `Run` (text + properties). Or introduce explicit `runsDirty: Bool` flag set by mutating accessors. Decision in design.md.
- **Container parser `<w:tbl>` capture**: `parseContainerParagraphs` (`DocxReader.swift:1101/1123`) becomes `parseContainerBody` returning `[BodyChild]`, capturing both `<w:p>` and `<w:tbl>` direct children. Header/Footer/Footnote/Endnote models gain `bodyChildren` (or extend `paragraphs` semantics).
- **`acceptAllRevisions`/`rejectAllRevisions` error propagation**: Replace `try?` with explicit `do { try } catch { /* collect, continue, rethrow at end */ }`. Surface notFound from per-revision helper rather than swallow.
- **`Footnote.toXML` paragraph emit**: Replace hardcoded single-text-run template with `paragraphs.map { $0.toXML() }.joined()`. Same fix likely needed for `Endnote.toXML`.
- **`updateHyperlink`/`deleteHyperlink` cross-part**: Walk all paragraph surfaces (body, table cells, nested tables, content controls, headers, footers, footnotes, endnotes) instead of body `.paragraph` only. Reuse same `walkAllParagraphs` helper.
- **`SDTParser.parseSDT` recursive position**: Recursive call (`SDTParser.swift:42`) passes child's index as `position` so nested SDTs get correct positioning post-R3-NEW-2.
- **R5 tests use full save→reread roundtrip**: Every R5 fix's test calls `DocxWriter().write(document, to: tmpURL)` then `DocxReader().read(from: tmpURL)` and asserts on the re-read document. New test file `Issue56R4StackTests.swift`. R3 stack tests file gains a separate "save-roundtrip variants" group that wraps existing R3 tests.

## Non-Goals

- **Not** rewriting the OOXML reader/writer architecture. Targeted fixes only; no streaming-model refactor.
- **Not** introducing a typed `XMLAttribute` wrapper struct (deferred — Phase 2 hardening).
- **Not** changing che-word-mcp source. Same as R3 stack: dep bump + CHANGELOG only.
- **Not** addressing P2 findings from R4 verify (DA-N9 acceptAll try? scope is included as P1 #9; DA-N10 hasSourcePositionedChildren invariant is brittle but works; DA-N11 Equatable cache; DA-N12 covered set start/end naming) — defer to a separate hardening change.
- **Not** publishing intermediate v0.19.4 release. The local R4 commits stay under v0.19.5 banner.

## Success Criteria

- All 6 R4 P0 findings have a regression test that fails on `main` (pre-R5) and passes after R5 fix.
- All 7 R4 P1 findings are addressed and have at least one test exercising the previously-silent path.
- Every R5 test (P0 + P1) calls `DocxWriter().write(document:to:)` followed by `DocxReader().read(from:)` and asserts on the re-read document, not the in-memory model.
- ooxml-swift suite stays green (582+ R5 new tests / 0 fail). che-word-mcp suite stays green (172+ / 0 fail).
- Final R5 verify (full Agent Team + Codex) returns PASS with zero new P0 findings.
- v0.19.5 git tag pushed; v3.13.5 git tag pushed; marketplace synced via plugin-update.
- audit table in `Issue56R4StackTests.swift` is **allow-list**: explicit named files/sites NOT yet routed through `XMLAttributeEscape`, with rationale (e.g., "constants only", "test fixture emitter").

## Impact

- Affected code:
  - Modified:
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Hyperlink.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Paragraph.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Footnote.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Endnote.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Style.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Numbering.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Table.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Field.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/MathComponent.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Revision.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/Models/Run.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxWriter.swift
    - packages/ooxml-swift/Sources/OOXMLSwift/IO/SDTParser.swift
    - packages/ooxml-swift/CHANGELOG.md
    - mcp/che-word-mcp/Package.swift
    - mcp/che-word-mcp/CHANGELOG.md
    - mcp/che-word-mcp/mcpb/manifest.json
    - openspec/specs/docx-revision-parsing/spec.md
    - openspec/specs/docx-container-parsing/spec.md
  - New:
    - packages/ooxml-swift/Sources/OOXMLSwift/IO/XMLAttributeEscape.swift
    - packages/ooxml-swift/Tests/OOXMLSwiftTests/Issue56R4StackTests.swift
