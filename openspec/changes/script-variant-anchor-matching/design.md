## Design

This change selects the "matcher option" path instead of changing visible text output.

### Public API Shape

OOXMLSwift should introduce a public options type for text-anchor lookup, for example:

```swift
public struct AnchorLookupOptions: Sendable, Equatable {
    public var mathScriptInsensitive: Bool

    public static let exact = AnchorLookupOptions()
}
```

The existing public anchor lookup entry point, currently represented by `findBodyChildContainingText`, should accept this options value while preserving the current default:

```swift
findBodyChildContainingText(_ text: String, instance: Int = 1, options: AnchorLookupOptions = .exact)
```

Naming rationale:

- `mathScriptInsensitive` is narrower than `unicodeInsensitive`.
- `scriptVariantInsensitive` is technically accurate but easier to confuse with programming scripts at the MCP schema boundary.
- `math_script_insensitive` is explicit in JSON and matches the use case that triggered #90.

### Normalization Contract

When `mathScriptInsensitive == true`, both haystack and needle are transformed by the same canonicalization helper before searching.

The helper should map Unicode subscript and superscript variants to the closest ASCII representation:

- Subscript/superscript digits `₀..₉`, `⁰..⁹` -> `0..9`
- Script signs and grouping characters such as `₊`, `⁺`, `₋`, `⁻`, `₌`, `⁼`, `₍`, `⁽`, `₎`, `⁾` -> `+`, `-`, `=`, `(`, `)`
- Common Unicode subscript/superscript Latin letters that have clear compatibility forms -> their ASCII letters

The mapping should be explicit and test-pinned. Characters outside the table are preserved unchanged. This avoids turning the feature into broad Unicode folding.

Because insertion anchors only need a body-child location, the first implementation does not need a normalized-span to original-span map. If a future exact-span mutator reuses the helper, that follow-up must define span mapping separately.

### Matching Semantics

The option is bidirectional:

- Needle `H₀` matches haystack `H0`
- Needle `H0` matches haystack `H₀`
- Needle `xᵢ` matches haystack `xi`
- Needle `xi` matches haystack `xᵢ`

`instance` / `text_instance` semantics are applied after normalization. In other words, the nth match is counted in the normalized text universe.

Default exact matching remains unchanged, so existing tests for literal matching should continue to pass.

### MCP Schema Shape

Use a nested `match_options` object rather than one-off booleans on every insertion tool.

```json
{
  "type": "object",
  "properties": {
    "match_options": {
      "type": "object",
      "properties": {
        "math_script_insensitive": {
          "type": "boolean",
          "default": false
        }
      }
    }
  }
}
```

Reasons:

- Leaves room for later exact, case, diacritic, or whitespace options without adding flat parameter clutter.
- Makes it clear the option modifies anchor matching rather than insertion behavior.
- Lets all anchor-based tools share identical schema text and parser code.

The parser should treat omitted `match_options` and omitted `math_script_insensitive` as `false`.

### Tool Scope

Initial che-word-mcp scope:

- `insert_paragraph` `after_text` / `before_text`
- `insert_equation` display mode `after_text` / `before_text`
- `insert_image_from_path` `after_text` / `before_text`
- `insert_caption` `after_text` / `before_text`

Inline `insert_equation` anchor behavior remains governed by the existing inline-mode contract and is not expanded here.

### Backward Compatibility

This is a non-breaking additive option:

- Existing requests without `match_options` keep exact matching.
- Existing visible text output remains unchanged.
- Existing schema fields remain valid.
- Existing callers that already pass `H0` keep working.

### Test Strategy

OOXMLSwift tests:

- Normalization helper maps pinned subscript/superscript characters to ASCII.
- Exact mode does not match `H₀` against `H0`.
- `mathScriptInsensitive` mode matches `H₀` against `H0` and `H0` against `H₀`.
- `instance` selection counts normalized matches correctly when multiple candidates exist.
- Unsupported characters are preserved.

che-word-mcp tests:

- `tools/list` schema exposes `match_options.math_script_insensitive` on the 4 insertion-anchor tools.
- Omitted `match_options` keeps exact matching.
- Enabled option threads through Direct Mode and Session Mode insertion calls.
- Tool result/error wording remains attributable to the original tool.

### Implementation Notes

Keep the normalization helper small and shared. Avoid scattering per-tool string replacement logic in che-word-mcp; MCP should only parse JSON into the library option.

If implementation discovers that `findBodyChildContainingText` is not the single shared anchor lookup path, first consolidate only the minimal anchor path needed for the 4 scoped tools. Do not broaden the change into a search/replace rewrite without a follow-up proposal.
