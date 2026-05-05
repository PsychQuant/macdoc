## Why

`mdocx-syntax` (sibling change, just landed) produced a working spec for an embedded DSL by groping toward Requirements + Scenarios + SBE Examples + a non-normative composition tree, instead of using EBNF / PEG / formal grammar notation. The choice was deliberate but undocumented — the next person designing an embedded DSL (`.mpdf`, `.mbib`, `.mpptx`, or any future host-language-enforced authoring surface) will face the same "what shape should the spec take?" question and may default to EBNF / PEG out of academic instinct, producing a grammar specification that doesn't match how host-language compilers actually enforce the syntax.

This change codifies the embedded-DSL spec pattern as a `.claude/rules/` rule so future DSL design changes inherit the convention without re-deriving it.

## What Changes

- New `.claude/rules/embedded-dsl-spec-pattern.md` capturing the embedded vs external DSL distinction, the spec-shape convention (Requirements + Scenarios + SBE Examples + non-normative composition tree), composition-tree notation conventions, and cross-references to existing `extension-first-dsl.md` and the `mdocx-grammar` spec as the reference implementation.
- Cross-references added from `.claude/rules/extension-first-dsl.md` and from `docs/swift-as-document-source.md` to the new rule so an author landing on the existing artefacts is guided to the spec pattern when they need to write the spec.

## Capabilities

### New Capabilities

- `embedded-dsl-spec-pattern`: Normative rule defining how to write a Spectra spec for an embedded DSL whose syntax is enforced by the host language compiler. Distinguishes embedded vs external DSLs, prescribes the spec composition (Requirements + Scenarios + SBE Examples + non-normative composition tree), and standardises the composition-tree notation.

### Modified Capabilities

(none)

## Impact

- Affected specs: NEW `embedded-dsl-spec-pattern` capability.
- Affected code:
  - New: `.claude/rules/embedded-dsl-spec-pattern.md`
  - Modified: `.claude/rules/extension-first-dsl.md` (add cross-reference link to the new rule from the "已註冊副檔名" table footer or a related-rules section), `docs/swift-as-document-source.md` (add cross-reference link from the §10 `.mdocx` extension section).
  - Removed: (none)
