## Context

Three latent defects in the post-#56 v0.19.0 typed-surface mutation API are fixed in one coherent pass: F5 (`Hyperlink.text` setter destroys formatting), F6 (default `position = 0` causes `appendRun` to behave as `prepend` in source-loaded paragraphs), and F13 (`xml:space="preserve"` flag dropped on Run re-emit). All three are silent corruption — the call appears to succeed, returns success, and produces wrong output.

The defects share three properties that justify bundling: they all live at the API boundary (caller mutation → typed model), they all became reachable only after Reader-side multi-run + position parsing landed in v0.19.0, and they all benefit from the same SemVer story (additive deprecation for v0.21.x callers, type-signature change for `position` made minimal by `Int?` defaulting to `nil`).

The fix touches:

- `Sources/OOXMLSwift/Models/Hyperlink.swift` — F5 setter `@available(*, deprecated)`; F6 position type
- `Sources/OOXMLSwift/Models/Run.swift` — F6 position type; F13 xml:space autosense in `toXML()`
- `Sources/OOXMLSwift/Models/AlternateContent.swift`, `FieldSimple.swift`, `Field.swift`, `ParagraphChildMarkers.swift` — F6 position type cascade
- `Sources/OOXMLSwift/Models/Paragraph.swift` — F6 emit-time partition + max-plus-one heuristic

## Goals / Non-Goals

**Goals:**

- Convert F5's silent formatting loss into a compile-time deprecation warning so callers learn at build time, not at user-visible diff.
- Restore append semantics for `paragraph.runs.append(...)` and equivalent operations on source-loaded paragraphs (F6).
- Preserve `xml:space="preserve"` semantics for runs whose text contains semantically significant whitespace (F13).
- Keep the v0.21.5 patch SemVer-additive for valid behaviour: caller code that did not rely on the buggy behaviour continues to work.
- Set the v0.22 milestone for removing the deprecated `Hyperlink.text` setter.

**Non-Goals:**

- Not adding a `text` setter alternative API. The `.runs` property already provides everything callers need; an alternative would just multiply the surface area.
- Not removing `Hyperlink.text` setter in this change — deprecation only. v0.22 removes it.
- Not introducing a `Position` enum (`.explicit(Int)` / `.append`). `Int?` is idiomatic Swift, less invasive, carries the same expressive power.
- Not auto-emitting `xml:space="preserve"` for runs whose text has only single internal whitespace. XML normalises single internal whitespace; emitting the flag would inflate output without semantic gain.
- Not refactoring `Paragraph.toXMLSortedByPosition()` beyond the partition step. The existing legacy / sort-by-position split logic stays.
- Not changing `position` semantics for non-typed-child collections (`bookmarks` legacy, `hasPageBreak`). Those follow legacy ordering and are out of F6 scope.

## Decisions

### D1 — F5: Deprecate via `@available(*, deprecated, message:)`, keep behaviour identical for one minor

`Hyperlink.text`'s setter is annotated:

```swift
public var text: String {
    get { runs.map { $0.text }.joined() }
    @available(*, deprecated, message: "Mutates runs destructively (loses formatting / rawElements). Use .runs directly to preserve formatting; assign a single Run to replace, append/insert Runs to extend.")
    set { runs = [Run(text: newValue)] }
}
```

The setter's runtime behaviour is unchanged. Compile-time warning fires at every set-site, producing a punch-list of callers to migrate before v0.22. The getter is unchanged (it is benign: pure derivation, no formatting loss).

### D2 — F6: `Int? = nil` over `Int = 0`, partition at emit time

Across all 13 typed-child position fields, the default becomes `nil` instead of `0`. The choice is between `Int? = nil` and a `Position` enum (`.explicit(Int)` / `.append`). `Int?` wins because:

- Idiomatic Swift — `Int?` covers exactly the "optional value" semantics required.
- Migration cost is minimal — callers reading `position` upgrade to `position ?? 0` or `position ?? someDefault` one-liner.
- Carries the same expressive power (nil = "I don't care about position; place me last").
- An enum would force every read-site to switch, even read-only sites that just want "the integer if any".

`Paragraph.toXMLSortedByPosition()` partitions each typed-child collection:

```swift
let explicit = collection.compactMap { $0.position != nil ? ($0.position!, $0) : nil }
let appendees = collection.filter { $0.position == nil }
let nextPos = (explicit.map(\.0).max() ?? 0) + 1
// emit explicit at their positions, then appendees at nextPos, nextPos+1, …
```

The append base (`max(explicit) + 1`) is computed per-collection, so each typed-child kind appends within its own append-window. This matches the v0.21.4 legacy behaviour (`hasPageBreak` / `bookmarks` etc. emit at legacy positions) without changing it.

### D3 — F13: `xml:space="preserve"` autosense in `Run.toXML()`, owner-correct fix

`xml:space` is a per-`<w:t>` attribute, so the responsibility lives in `Run.toXML()`. The autosense rule is:

```swift
let needsPreserve =
    text.first?.isWhitespace == true ||
    text.last?.isWhitespace == true ||
    text.range(of: #"\s\s"#, options: .regularExpression) != nil

let openTag = needsPreserve ? "<w:t xml:space=\"preserve\">" : "<w:t>"
```

Single internal whitespace (e.g., `"hello world"`) does NOT trigger — XML normalises single internal whitespace, and emitting the flag would inflate output. Hyperlink's `text` getter is downstream of the emit and is left unchanged; F13 is fixed at the boundary that owns the property.

### D4 — Two-step deprecation timeline (v0.21.5 → v0.22)

- v0.21.5 (this change): F5 setter `@available(*, deprecated)`. Callers warned. Type signature changes for F6 (`Int? = nil`) ship simultaneously — minor caller migration but additive.
- v0.22 (separate change): F5 setter removed. Callers must use `.runs` directly. Two-minor migration window.

The v0.22 milestone is documented in `CHANGELOG.md` "Unreleased" so consumers can track.

### D5 — No new `OOXMLError` cases

F5/F6/F13 are silent-corruption fixes; the right surface for the warning is the compiler (deprecation message) and the type system (`Int?`), not runtime throws. Adding an error case would force callers to catch — over-engineering. Compare to F8 (#6 / `roundtrip-loud-fail`) which DOES add a new error case because the failure is editor-driven, not signature-driven.

### D6 — Position type cascade affects 13 sites; cascade is mechanical

The 13 sites discovered via `grep "public var position: Int" Sources/OOXMLSwift/Models/`:

| File | Line(s) |
| ---- | ------- |
| `Hyperlink.swift` | 55 |
| `Run.swift` | 55 |
| `AlternateContent.swift` | 47 |
| `FieldSimple.swift` | 39 |
| `Field.swift` | 1499 (StructuredDocumentTag.position) |
| `ParagraphChildMarkers.swift` | 40, 72, 96, 123, 140, 156, 179, 198 |

(Field.swift:466 is already `Int?` for an unrelated use; not in scope.)

All 13 sites get the same mechanical edit: `Int = 0` → `Int? = nil` (and `Int` → `Int? = nil` where no default was set). Each model's initializer propagates the new optional.

## Risks / Trade-offs

- **Risk: `position` type signature change is a SemVer-borderline event.** Adding `?` to a stored property's type changes the property's interface but stays source-compatible for callers that read with `??` fallback. Mitigation: ship as v0.21.5 patch with prominent CHANGELOG note; provide a migration recipe (`pos ?? 0` for legacy assumptions, or use the new "no position == append" semantic).
- **Risk: deprecation warnings flood downstream consumer compile output.** Mitigation: `@available` message is explicit and migration is mechanical (replace `hl.text = "x"` with `hl.runs = [Run(text: "x")]`). v0.22 milestone gives a one-minor window.
- **Risk: emit-time `max(explicit) + 1` heuristic produces unintuitive ordering when explicit positions are sparse (e.g., 1, 100, 1000).** Mitigation: this is the documented behaviour — `nil` means "after the last explicit", so callers wanting tight packing should assign explicit positions. Tests cover the sparse case to lock in the contract.
- **Trade-off: F13 autosense regex `\s\s` runs on every Run emit.** Mitigation: regex is anchored, runs are typically short, and the autosense path only fires when the cheap leading/trailing checks fail. Profiler can optimise later if hot.
- **Risk: the F6 cascade affects 13 sites — easy to miss one in the apply phase.** Mitigation: `grep "public var position: Int = 0" Sources/OOXMLSwift/Models/ | wc -l` SHALL return 0 after apply; verification step in tasks.
