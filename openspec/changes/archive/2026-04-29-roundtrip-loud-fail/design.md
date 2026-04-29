## Context

The post-#56 v0.19.0 surface introduced typed access to `AlternateContent.fallbackRuns` (so MCP tools like `replace_text` can edit fallback content) and Phase-4 marker-based comment range tracking (`commentRangeMarkers`). Both shipped with documented limitations:

- `AlternateContent.fallbackRuns` is read/edit-able from the typed surface but `Paragraph.toXMLSortedByPosition()` only emits `ac.rawXML` — typed edits silently disappear on save.
- `Paragraph.commentIds` and `Paragraph.commentRangeMarkers` are both populated by Reader (`Sources/OOXMLSwift/IO/DocxReader.swift:73-77`) — the legacy `commentIds` is structurally redundant with the new markers but kept for back-compat.

F8 is an active silent UX failure — users see "replaced N occurrences" success messages, save the file, and the disk content is unchanged. F9 is dormant tech debt — no current user impact, but any maintainer touching the comment-emit paths could trip the duality. Bundling because both involve "model state vs emit state divergence" and benefit from a coherent loud-fail / source-of-truth pass.

The four sub-fixes touch:

- `Sources/OOXMLSwift/Models/AlternateContent.swift` (didSet flag, doc-comment update)
- `Sources/OOXMLSwift/Models/Paragraph.swift` (emit-time throw on dirty fallback; commentIds → computed property)
- `Sources/OOXMLSwift/IO/DocxReader.swift` (stop populating `commentIds`)
- `Sources/OOXMLSwift/Models/OOXMLError.swift` (new `unserializedFallbackEdit` case)

## Goals / Non-Goals

**Goals:**

- Convert F8's silent failure into a loud throw so `replace_text` users learn at save-time that their edit did not propagate, and can either accept or repair.
- Establish `commentRangeMarkers` as the single source of truth for paragraph comment markers, with a graceful one-minor deprecation window for `commentIds`.
- Ship as SemVer patch (v0.21.4); valid no-op round-trips remain byte-equivalent.
- Set the v0.22 milestone for removing the now-deprecated `commentIds` field.

**Non-Goals:**

- Not implementing `regenerateRawXMLFromFallbackRuns` (the Complete option for F8). Splicing typed `fallbackRuns` content back into rawXML while preserving `<mc:Choice>` blocks needs an `XMLSplicer` helper and is its own SDD.
- Not removing `commentIds` in this change — deprecation only. Removal lands in v0.22.
- Not unifying every collection-vs-marker pair across the model. Bookmarks / footnotes follow a different pattern; only F9 (comments) is in scope here.
- Not adding an `auto-regenerate` opt-in flag. The chosen semantic is "throw"; opt-in regen would be a separate feature in the future Complete change.
- Not modifying MCP-side description strings (`che-word-mcp`) in this change — that is a downstream task tracked separately.

## Decisions

### D1 — F8: didSet flag is the dirty-tracking mechanism, not a manual `markDirty()` API

Adding a `private(set) var fallbackRunsModified: Bool = false` plus `didSet` on the `fallbackRuns` array gives automatic dirty tracking without exposing a `markDirty()` API for callers to forget.

```swift
public struct AlternateContent: Equatable {
    public var rawXML: String
    public var fallbackRuns: [Run] {
        didSet { fallbackRunsModified = true }
    }
    public var position: Int
    public private(set) var fallbackRunsModified: Bool = false

    public init(rawXML: String, fallbackRuns: [Run] = [], position: Int = 0) {
        self.rawXML = rawXML
        self.fallbackRuns = fallbackRuns
        self.position = position
        // fallbackRunsModified stays false after init (didSet doesn't fire on init)
    }
}
```

The `didSet` does not fire from the initializer assignment, so freshly-constructed (Reader-loaded) `AlternateContent` values start clean. Any subsequent mutation — assignment, append, replaceSubrange, etc. — flips the flag to true.

### D2 — F8: throw on emit, not on mutation

The throw lives in `Paragraph.toXMLSortedByPosition()` (and the legacy emit path that touches `alternateContents`), checking `ac.fallbackRunsModified == true` per-`AlternateContent` and throwing `OOXMLError.unserializedFallbackEdit(position: ac.position)`. Throwing on mutation would break the typed-edit ergonomics (callers expect to edit then maybe-save); throwing on emit catches the actual failure surface (the save) and still preserves audit trail.

### D3 — F9: `commentIds` becomes a computed property, not removed

Two-step deprecation:

- v0.21.4: `commentIds` is `@available(*, deprecated, message: "Use commentRangeMarkers (source of truth since Phase 4).")`. Reader stops populating the stored property; the accessor becomes a computed getter that derives the id list from `commentRangeMarkers`. Existing callers compile (warned) and observe identical values.
- v0.22 (separate change): the computed property is removed.

The computed-getter intermediate step is what makes the deprecation cheap. Removing the field outright in v0.21.4 would force every call site to migrate immediately and break in-flight branches.

### D4 — F9: round-trip regression test asserts the comment-marker invariant

A new test in `Issue6RoundtripLoudFailTests.swift` constructs a paragraph whose source XML is `<w:p><w:commentRangeStart w:id="1"/><w:r><w:commentReference w:id="1"/></w:r><w:commentRangeEnd w:id="1"/></w:p>`, parses it, emits via `toXMLSortedByPosition()`, re-parses, and asserts the three marker positions are preserved. This locks in the source-of-truth invariant: any future change that stops emitting marker-side data will fail the test, even if `commentIds` accidentally still produces the right ids.

### D5 — Single new `OOXMLError` case

`OOXMLError.unserializedFallbackEdit(position: Int)` carries the offending `AlternateContent.position` so the caller can locate the paragraph in their model. No other new error cases for F9 (the deprecation produces compile-time warnings, not runtime errors).

### D6 — Doc-comment expansion order: AlternateContent first, then Paragraph

`AlternateContent.swift` doc-comment is the canonical place to describe the dirty-tracking mechanism (it owns the field). `Paragraph.swift` emit-path doc-comment cross-references the AlternateContent comment without duplicating the explanation. Single source of truth for the runtime semantics.

## Risks / Trade-offs

- **Risk: callers that previously fired `replace_text` then `save_document` without checking results will now get a thrown error.** This is the intended outcome — silent corruption was worse — but it is technically a behaviour change for callers. Mitigation: the throw is documented in the v0.21.4 release notes with a migration recipe (catch the throw, log, decide whether to drop the edit or block the save).
- **Risk: `commentIds` deprecation warnings flood downstream consumer compile output.** Mitigation: the `@available` message points directly at `commentRangeMarkers` so the migration is mechanical. v0.22 milestone gives a one-minor window for consumers to cut over.
- **Trade-off: choosing throw over auto-regenerate means typed-edit users must explicitly rebuild `AlternateContent` to commit changes.** This is the price of the Conservative approach; the Complete approach (auto-regen) is deferred.
- **Risk: didSet on `fallbackRuns` does not detect in-place mutations through array indexing in some Swift edge cases.** Mitigation: testing covers the common mutation patterns (`runs[0] = ...`, `runs.append(...)`, `runs = [...]`) — Swift's value-semantics array triggers didSet on all of these because the array is a value type and any `inout` write propagates.
- **Risk: removing `commentIds` storage from Reader breaks any test that asserted Reader populates `commentIds`.** Mitigation: the computed getter returns the same values, so test assertions on the getter continue to pass; only tests that introspect the storage location (rare) need updating.
