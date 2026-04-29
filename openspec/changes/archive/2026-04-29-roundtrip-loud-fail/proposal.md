## Problem

Two wrapper round-trip gaps surfaced in the verification of PsychQuant/che-word-mcp#56 (findings F8 and F9) cause silent failure of the "lossless edit" guarantee:

- **F8** — `AlternateContent.fallbackRuns` edits made via the typed surface (`replace_text`, `format_text`) succeed, return success, but `Paragraph.toXMLSortedByPosition()` only emits `ac.rawXML` (line ~537 in `Sources/OOXMLSwift/Models/Paragraph.swift`). The disk save writes stale rawXML; the user sees a "replaced N occurrences" success message but the saved `.docx` contains unchanged content. This is the highest-impact failure mode in the post-#56 surface.
- **F9** — Comment markers travel through two parallel collections: legacy `Paragraph.commentIds` and Phase-4 `Paragraph.commentRangeMarkers`. `DocxReader.swift:73-77` populates both. The two emit paths (sort-by-position vs legacy) traverse different collections; round-trip works in practice for source-loaded paragraphs because the marker collection has positions, but the structural duality means any future maintainer touching one path without the other introduces a regression. Pure technical debt that hasn't bitten yet.

## Root Cause

- **F8**: the v3.13.0 `AlternateContent` design declared "Out-of-scope: edits to `fallbackRuns` are NOT automatically re-serialized into `rawXML`" (see doc-comment in `Sources/OOXMLSwift/Models/AlternateContent.swift:27-31`) but provided no runtime signal to either user or caller. The typed surface and the rawXML emit path share no dirty-tracking state.
- **F9**: legacy `commentIds` predates Phase-4 markers. Reader populates both for back-compat, but `commentIds` is now redundant — `commentRangeMarkers` carries the same information plus `position`, which the sort-by-position emit path requires. Keeping both populated is the source of the duality.

## Proposed Solution

### F8 — Conservative + Documentation, not Complete

Two-layer approach (Complete option — full `regenerateRawXMLFromFallbackRuns` with XML splicing — is deferred to a future SDD).

**Conservative layer — runtime loud failure on dirty-but-not-regenerated state:**

1. Add `private(set) var fallbackRunsModified: Bool = false` to `AlternateContent`.
2. Convert `fallbackRuns` from a stored property to a property with `didSet` that flips `fallbackRunsModified = true` whenever the array is mutated (assigned, appended, replaced, etc.).
3. In `Paragraph.toXMLSortedByPosition()` (and the legacy emit path that touches `alternateContents`), check each `ac.fallbackRunsModified`. If `true`, throw `OOXMLError.unserializedFallbackEdit(position: ac.position)` so the save fails loudly rather than writing stale data.

**Documentation layer — make the limitation visible at every entry point:**

4. Expand the doc-comment on `AlternateContent.fallbackRuns` to describe the new dirty-tracking and how to clear (re-build the `AlternateContent` with regenerated rawXML).
5. Surface the limitation in MCP tool descriptions for `che-word-mcp` `replace_text` and `format_text` (separate downstream task — not in this spec).

### F9 — Deprecate `commentIds`; markers as source of truth

1. Mark `Paragraph.commentIds` with `@available(*, deprecated, message: "Use commentRangeMarkers (source of truth since Phase 4).")`.
2. Stop populating the stored property in `DocxReader` (v0.21.4 — the field is no longer `Reader`-touched).
3. Convert `commentIds` to a computed property that derives the id list from `commentRangeMarkers` so existing callers continue to compile and observe the same values.
4. Add a round-trip regression test asserting that a paragraph with `<w:commentRangeStart><w:r><w:commentReference/></w:r><w:commentRangeEnd>` survives Reader → emit (sort-by-position) → re-Reader with all three markers preserved at the original positions.
5. v0.22 milestone: remove the computed `commentIds` field entirely (separate change).

## Non-Goals (optional)

- Not implementing `regenerateRawXMLFromFallbackRuns` (Complete option for F8). Splicing typed `fallbackRuns` content back into rawXML while preserving `<mc:Choice>` blocks needs an `XMLSplicer` helper and a focused SDD; out of scope here.
- Not removing `commentIds` in this change. Two-step deprecation (deprecate v0.21.x → remove v0.22) preserves caller compile-compatibility through one minor.
- Not unifying every collection-vs-marker pair. F9 specifically targets the comment-marker case because it has a downstream consumer (`commentIds`). Other pairs (bookmarks, footnotes) follow a different pattern and are not in scope.
- Not auto-regenerating rawXML on `fallbackRuns` mutation. Loud throw is the chosen semantic; auto-regen is what `Complete` would deliver in a future change.

## Capabilities

### New Capabilities

- `ooxml-roundtrip-completeness`: defines the loud-fail invariants for typed-edit propagation (AlternateContent dirty-tracking + emit-time throw) and the source-of-truth model for paragraph comment markers (deprecation of `commentIds`, markers as canonical). Owns the new `OOXMLError.unserializedFallbackEdit` case.

### Modified Capabilities

(none. The new invariants are additive at runtime; no existing capability requirements are changing.)

## Success Criteria

- Editing `AlternateContent.fallbackRuns` via the typed surface and then calling `Paragraph.toXMLSortedByPosition()` (or any `Document.write(to:)` path that traverses paragraphs containing the modified `AlternateContent`) SHALL throw `OOXMLError.unserializedFallbackEdit(position:)` instead of silently writing stale rawXML.
- A `.docx` round-trip (Reader → Writer → Reader) that does not mutate `fallbackRuns` SHALL produce byte-equivalent output (no behaviour change for the no-op case).
- `Paragraph.commentIds` continues to return the same ids as before for any paragraph loaded from disk; callers that already compile against `commentIds` SHALL continue to compile (warned) without source-level changes.
- A paragraph loaded with a single `<w:commentRangeStart>` + inner `<w:r><w:commentReference/></w:r>` + `<w:commentRangeEnd>` SHALL re-emit all three markers at their original positions through the sort-by-position path; the round-trip regression test SHALL pass.
- New `OOXMLError.unserializedFallbackEdit(position:)` case SHALL be pattern-matchable in a `switch` over `OOXMLError`.
- Full test suite remains green (722 baseline + new tests added in this change).

## Impact

- **Affected code**:
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/AlternateContent.swift`
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Paragraph.swift`
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift`
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/OOXMLError.swift`
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/Issue6RoundtripLoudFailTests.swift`
- **APIs**: one new `OOXMLError` case (`unserializedFallbackEdit(position:)`); `AlternateContent.fallbackRunsModified` new public read-only field; `Paragraph.commentIds` becomes `@available(*, deprecated)` and converts from stored to computed (caller-visible deprecation warning, no behaviour change for read).
- **Capabilities**: new `ooxml-roundtrip-completeness` capability captures the loud-fail-on-dirty + source-of-truth invariants. `ooxml-roundtrip-fidelity` is unchanged (byte-equivalent claim still holds for the no-op path).
- **Release**: ooxml-swift v0.21.4 patch; v0.22 milestone removes the computed `commentIds` field.
