## Context

`WordDocument` currently mixes at least three index spaces under similar integer labels:

- `insertParagraph(_:at:)` uses a raw top-level `body.children` index.
- `updateParagraph(at:)`, `deleteParagraph(at:)`, formatting APIs, and list APIs translate through top-level paragraphs only.
- `getParagraphs()` returns a recursive paragraph list that includes nested containers and is not compatible with either top-level index space.

This ambiguity affects downstream automation because agents often pass the count or position returned by one API into another. `che-word-mcp` already compensates at selected call sites, but the library contract remains unclear.

## Goals / Non-Goals

**Goals:**

- Make every paragraph/body mutation API name reveal its index basis.
- Preserve source compatibility during one minor release while producing deprecation warnings for ambiguous legacy entry points.
- Avoid a same-signature semantic swap that would silently change existing callers.
- Centralize index validation so body-child and paragraph-only semantics are implemented consistently.
- Give `che-word-mcp` a clear migration target.

**Non-Goals:**

- Introduce compile-time index wrapper types in this change.
- Change recursive read ordering from `getParagraphs()`.
- Implement downstream `che-word-mcp` migration in the Spectra proposal PR.

## Decisions

### Use explicit labels instead of changing same-signature semantics immediately

Adopt Option A's underlying semantic direction: body insertion and structural mutation APIs use top-level body-child positions, while paragraph-only operations use explicitly named paragraph positions. However, do not immediately change the behavior of existing same-signature methods such as `updateParagraph(at:)` in a minor release.

Rationale: Swift cannot expose both `updateParagraph(at:)` with legacy paragraph-index behavior and `updateParagraph(at:)` with body-child behavior at the same time. Reusing the same signature with new behavior would silently break existing callers and violate the library's human-like operation principles. A staged rename/deprecation path gives callers compiler-visible migration guidance.

Alternatives considered:

- Option A immediate semantic swap: rejected for minor release because existing callers would compile and behave differently.
- Option B paragraph-index unification: rejected because body-level insertion must be able to target positions around tables, content controls, and body-level markers.
- Option C index newtypes: deferred because it is the most correct long-term surface but too invasive for the immediate cleanup.

### Introduce body-child APIs and preserve ambiguous methods during one minor release

Add explicit body-child APIs for mutation points that operate on top-level `body.children`, for example `updateParagraph(atBodyChildIndex:text:)` and `deleteParagraph(atBodyChildIndex:)`. Existing ambiguous APIs stay available for one minor release with deprecation warnings and unchanged behavior.

Rationale: callers get a mechanical migration path without losing the ability to compile. New code can immediately select the correct index space.

### Introduce paragraph-index APIs for paragraph-only operations

Add explicitly named paragraph-index APIs for operations that intentionally target the nth top-level paragraph, for example `updateTopLevelParagraph(atParagraphIndex:text:)`, `deleteTopLevelParagraph(atParagraphIndex:)`, `formatTopLevelParagraph(atParagraphIndex:with:)`, and list-formatting equivalents.

Rationale: paragraph-only operations remain useful, but their names must not imply compatibility with raw body-child positions or recursive paragraph reads.

### Document recursive paragraph reads as non-index-compatible

Document `getParagraphs()` as a read convenience that returns recursive paragraph content and does not produce indexes suitable for body mutation APIs.

Rationale: this is the most common agent mistake: use a recursive read result, then pass that ordinal into a top-level mutator. Documentation and named APIs must prevent that confusion.

## Risks / Trade-offs

- Existing callers may ignore deprecation warnings -> migration guide and `che-word-mcp` follow-up PR use the explicit labels immediately.
- More API names increase surface area -> each name carries its index basis, reducing hidden semantics.
- Body-child APIs need clear refusal when the target is not a paragraph -> throw `WordError.invalidIndex` or a more specific existing-compatible error rather than mutating a different paragraph.
- Future index newtypes remain deferred -> leave names compatible with a later typed-index overload if the team chooses Option C.

## Migration Plan

1. Add shared internal helpers for `bodyChildIndex` and `topLevelParagraphIndex` validation.
2. Add explicit body-child and paragraph-index public APIs.
3. Deprecate ambiguous legacy APIs without changing runtime behavior in the same minor release.
4. Migrate `che-word-mcp` callers to the explicit APIs in a separate implementation PR.
5. Remove or repurpose ambiguous legacy APIs only in the next major release, after callers have compiler-visible warning time.

## Open Questions

- Whether the eventual major release removes ambiguous `at:` APIs entirely or reintroduces them only for body-child semantics.
- Whether Option C typed indexes become mandatory after the explicit-label migration proves stable.
