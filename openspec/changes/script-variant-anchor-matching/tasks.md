## Tasks

- [x] Add OOXMLSwift `AnchorLookupOptions` or equivalent public options type with exact matching as the default.
- [x] Implement a shared math-script canonicalization helper with explicit mapping for supported Unicode subscript/superscript characters.
- [x] Thread the options type through `findBodyChildContainingText` and the insertion-anchor call sites that depend on it.
- [x] Add OOXMLSwift tests for exact mode, math-script-insensitive mode, bidirectional matching, nth-instance behavior, and unsupported-character preservation.
- [x] Add che-word-mcp `match_options.math_script_insensitive` schema support to the 4 scoped insertion tools.
- [x] Parse MCP `match_options` into the OOXMLSwift anchor lookup option for the scoped insertion tools. Current insertion mutators are Session Mode only; no `source_path` mutating Direct Mode surface exists in this change.
- [x] Add che-word-mcp tests proving schema exposure, default exact behavior, and successful `H₀` / `H0` insertion anchors when the option is enabled.
- [x] Update README/tool documentation with the exact matching default and opt-in math-script matching examples.
- [x] Verify with targeted Swift tests in both affected repos.
- [x] Open implementation PRs referencing PsychQuant/che-word-mcp#90.
