## Problem

Three API mutation surface defects surfaced in the verification of PsychQuant/che-word-mcp#56 (findings F5/F6/F13). All three were unreachable before v0.19.0 because the Reader did not parse hyperlink inner runs or assign positions to typed children; the post-#56 typed-parsing surface made each silently corrupt source-loaded paragraphs:

- **F5** — `Hyperlink.text` setter (`Sources/OOXMLSwift/Models/Hyperlink.swift:61-64`) destructively assigns `runs = [Run(text: newValue)]`. Multi-run hyperlinks lose every run's `bold`, `italic`, `color`, `font`, `size`, `rStyle`, plus any `Run.rawElements` (e.g., embedded VML). Caller sees no error, just silently-flattened formatting.
- **F6** — `Hyperlink.position`, `Run.position`, `AlternateContent.position`, and 10 other typed children default to `Int = 0`. When a paragraph has source-loaded children with assigned positions (≥1) and the caller invokes `paragraph.runs.append(...)` (or any equivalent appender), the new run lands at position 0 — sort-by-position emit puts it at paragraph head, before bookmarks/hyperlinks. The semantic of `appendRun()` becomes `prepend`.
- **F13** — `Hyperlink.text` getter joins per-run text via `runs.map{$0.text}.joined()`. The `xml:space="preserve"` flag is per-run (per `<w:t>`), not per-Hyperlink. When run text contains leading, trailing, or consecutive whitespace and the run is later re-emitted (e.g., after a `replace_text` modifies adjacent runs), the `xml:space` flag may be dropped depending on emit path.

## Root Cause

- **F5**: the v0.19.0 setter design predates Reader-side multi-run parsing. The doc-comment at `Hyperlink.swift:57-60` declares this matches "the pre-fix observable behavior", which was correct when Reader produced exactly one run per hyperlink. After Reader populates multi-run hyperlinks, the setter behaviour is defensible (caller asked to replace text) but unsafe by default.
- **F6**: `Int = 0` is the path-of-least-resistance default that makes the type construct without arguments. Pre-v0.19.0 the position field was advisory only because emit fell back to legacy ordering. Post-v0.19.0 sort-by-position emit treats position 0 as a real value, triggering the prepend regression.
- **F13**: `xml:space="preserve"` is an XML-level flag, not a `<w:r>`-level field. The current `Run.toXML()` does not emit this attribute even when run text contains semantically significant whitespace. Hyperlink's text getter is downstream of the bug, not the cause.

## Proposed Solution

### F5 — Deprecate the setter, preserve behaviour for one minor

1. Mark `Hyperlink.text`'s setter with `@available(*, deprecated, message: "Mutates runs destructively (loses formatting / rawElements). Use .runs directly to preserve formatting; assign a single Run to replace, append/insert Runs to extend.")`.
2. Behaviour stays unchanged in v0.21.5 — caller continues to compile (with warning). Removal lands in v0.22 (separate change).

### F6 — Convert `position` from `Int = 0` to `Int? = nil` across all 13 typed-child models

1. Change `public var position: Int` (or `= 0`) to `public var position: Int? = nil` in: `Hyperlink.swift:55`, `Run.swift:55`, `AlternateContent.swift:47`, `FieldSimple.swift:39`, `Field.swift:1499` (`StructuredDocumentTag.position`), and the 8 marker types in `ParagraphChildMarkers.swift` (lines 40, 72, 96, 123, 140, 156, 179, 198).
2. In `Paragraph.toXMLSortedByPosition()` (and the legacy emit path), partition each typed-child collection into "has explicit position" (`position != nil`) and "no explicit position" (`position == nil`). The former are sorted-and-emitted at their positions; the latter are appended *after* the highest source position (via `let nextPos = (max(allExplicitPositions) ?? 0) + 1` per collection).
3. Reader continues to assign explicit positions — no Reader change required; only construction without explicit position now defaults to `nil` instead of `0`.
4. The position getter remains `Int?`-typed; consumers that previously read `position` as `Int` get a deprecation-style warning by default (see Non-Goals below for opt-out helper).

### F13 — Auto-emit `xml:space="preserve"` from `Run.toXML()` when text contains semantically significant whitespace

1. In `Run.toXML()`, after composing the `<w:t>` element, inspect the assigned `text` string. If it has leading whitespace, trailing whitespace, or two-or-more consecutive whitespace characters, emit `<w:t xml:space="preserve">` instead of `<w:t>`.
2. `Hyperlink.text` getter is unchanged — F13 is fixed at the Run boundary where the property semantically belongs.

## Non-Goals (optional)

- Not adding a `text` setter alternative API (e.g., `replaceText(_:preservingFormatting:)`). The deprecation message points callers at `.runs` directly, which already provides the precise control they need.
- Not removing `Hyperlink.text` setter in this change — deprecation only. Removal lands in v0.22.
- Not introducing a `Position` enum (`.explicit(Int)` / `.append`) instead of `Int?`. `Int?` is idiomatic Swift, less invasive for callers, and carries the same expressive power.
- Not auto-converting non-significant whitespace (single internal space) to `xml:space="preserve"` — XML treats single internal whitespace as normalised, and emitting the flag for every space-bearing run would inflate output without semantic gain.
- Not refactoring `Paragraph.toXMLSortedByPosition()` beyond the partition step. The existing legacy / sort-by-position split logic is preserved; only the position-resolution heuristic changes.
- Not changing `position` semantics for non-typed-child collections (e.g., `bookmarks` legacy, `hasPageBreak`). Those follow legacy ordering and are out of F6 scope.

## Capabilities

### New Capabilities

- `ooxml-mutation-surface-safety`: defines the deprecation contract for `Hyperlink.text` setter (F5), the `Int? = nil` position semantics with explicit-vs-append partitioning at sort-by-position emit time (F6), and the `xml:space="preserve"` autosense on Run emit (F13). Owns the deprecation timeline through v0.22.

### Modified Capabilities

(none. The new safety invariants are additive at the API surface; no existing capability requirements are changing.)

## Success Criteria

- `Hyperlink.text` setter compiles with a deprecation warning at every call site; the runtime behaviour SHALL remain identical to v0.21.4 (set replaces all runs with a single Run carrying the new text — caller-observable equivalence).
- A paragraph loaded from disk with hyperlinks at positions 1, 2, 3, then `paragraph.runs.append(Run(text: "z"))` followed by `toXMLSortedByPosition()` SHALL emit the new run at position 4 (after the source children), not at position 0 (before them).
- A `.docx` round-trip (Reader → Writer → Reader) where no caller code touches `position` SHALL produce byte-equivalent output (Reader-assigned positions preserved through emit).
- A `Run` whose text is `" leading"` / `"trailing "` / `"two  spaces"` SHALL emit as `<w:t xml:space="preserve">…</w:t>`. A `Run` whose text is `"single internal"` SHALL emit as `<w:t>…</w:t>` (no flag).
- Full test suite remains green (722 baseline + new tests added in this change).
- Hyperlink with `<w:r><w:t xml:space="preserve">  spaces  </w:t></w:r>` SHALL preserve the `xml:space` flag through Reader → caller mutation of *adjacent* runs → emit (the flag is per-run, sourced from Run, so adjacent edits do not affect it).

## Impact

- **Affected code**:
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Hyperlink.swift`
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Run.swift`
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/AlternateContent.swift`
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/FieldSimple.swift`
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Field.swift`
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/ParagraphChildMarkers.swift`
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Paragraph.swift`
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/Issue5MutationSurfaceTests.swift`
- **APIs**: `Hyperlink.text` setter becomes `@available(*, deprecated)` (compile warning, no runtime change); 13 `position` properties change type from `Int` (or `Int = 0`) to `Int? = nil` (caller-visible signature change but `??` falls back trivially); no new error cases.
- **Capabilities**: new `ooxml-mutation-surface-safety` capability captures the F5/F6/F13 invariants. Existing capabilities unchanged.
- **Release**: ooxml-swift v0.21.5 patch; v0.22 milestone removes the deprecated `Hyperlink.text` setter.
